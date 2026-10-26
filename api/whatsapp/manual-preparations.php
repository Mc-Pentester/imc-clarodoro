<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode HTTP non autorisée');
}

$pdo = getDatabaseConnection();
$user = requirePermission($pdo, 'whatsapp.message.send');
requireCsrfToken();
$data = readJsonBody();

$parentId = $data['parent_id'] ?? null;
$purpose = $data['purpose'] ?? null;
$message = $data['message'] ?? null;
$uuidPattern = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';

if (!is_string($parentId) || !preg_match($uuidPattern, $parentId)) {
    apiError(422, 'parent_id UUID invalide');
}
if (!is_string($purpose) || !in_array($purpose, ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'], true)) {
    apiError(422, 'Finalité WhatsApp invalide');
}
if (!is_string($message) || trim($message) === '' || mb_strlen($message) > 4000) {
    apiError(422, 'Le message doit contenir de 1 à 4000 caractères');
}

try {
    $pdo->beginTransaction();
    // Serialize this preparation against consent revocation for the same parent/purpose.
    $lock = $pdo->prepare('SELECT pg_advisory_xact_lock(hashtextextended(:lock_key, 0))');
    $lock->execute([':lock_key' => $parentId . ':' . $purpose]);

    $stmt = $pdo->prepare(
        'SELECT id, phone_e164, status
         FROM whatsapp_consents
         WHERE parent_id = :parent_id AND purpose = :purpose
         FOR UPDATE'
    );
    $stmt->execute([':parent_id' => $parentId, ':purpose' => $purpose]);
    $consent = $stmt->fetch();

    if (!$consent || $consent['status'] !== 'OPTED_IN') {
        $pdo->rollBack();
        apiError(403, 'Aucun consentement WhatsApp actif pour ce parent et cette finalité');
    }
    if (!preg_match('/^\+[1-9][0-9]{7,14}$/', (string) $consent['phone_e164'])) {
        $pdo->rollBack();
        apiError(422, 'Le numéro enregistré est invalide');
    }

    $insert = $pdo->prepare(
        'INSERT INTO whatsapp_manual_preparations
            (initiated_by, parent_id, consent_id, purpose, phone_sha256, message_sha256)
         VALUES (:actor, :parent_id, :consent_id, :purpose, :phone_hash, :message_hash)
         RETURNING id'
    );
    $insert->execute([
        ':actor' => $user['id'],
        ':parent_id' => $parentId,
        ':consent_id' => $consent['id'],
        ':purpose' => $purpose,
        ':phone_hash' => hash('sha256', (string) $consent['phone_e164']),
        ':message_hash' => hash('sha256', trim($message)),
    ]);
    $preparationId = $insert->fetchColumn();
    $phone = (string) $consent['phone_e164'];
    $pdo->commit();

    echo json_encode([
        'success' => true,
        'preparation_id' => $preparationId,
        'phone_e164' => $phone,
        'message' => 'Consentement revérifié et préparation journalisée. Aucun envoi WhatsApp n’a été effectué.',
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('WhatsApp manual preparation failed: ' . $e->getMessage());
    apiError(503, 'Impossible de journaliser la préparation WhatsApp');
}
