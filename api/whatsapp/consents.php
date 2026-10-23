<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    requirePermission($pdo, 'whatsapp.consent.read');
    $parentId = $_GET['parent_id'] ?? '';
    if (!is_string($parentId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $parentId)) {
        apiError(400, 'parent_id UUID invalide');
    }

    $stmt = $pdo->prepare(
        'SELECT id, parent_id, purpose, phone_e164, status, consent_source,
                evidence_reference, consented_at, revoked_at, created_at, updated_at
         FROM whatsapp_consents
         WHERE parent_id = :parent_id
         ORDER BY purpose'
    );
    $stmt->execute([':parent_id' => $parentId]);
    echo json_encode(['success' => true, 'consents' => $stmt->fetchAll()], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    apiError(405, 'Méthode HTTP non autorisée');
}

$user = requirePermission($pdo, 'whatsapp.consent.manage');
requireCsrfToken();
$data = readJsonBody();

$parentId = $data['parent_id'] ?? '';
$purpose = $data['purpose'] ?? '';
$phone = $data['phone_e164'] ?? '';
$status = $data['status'] ?? '';
$source = $data['consent_source'] ?? null;
$evidence = $data['evidence_reference'] ?? null;

if (!is_string($parentId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $parentId)) {
    apiError(422, 'parent_id UUID invalide');
}
if (!in_array($purpose, ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'], true)) {
    apiError(422, 'Finalité WhatsApp invalide');
}
if (!is_string($phone) || !preg_match('/^\\+[1-9][0-9]{7,14}$/', $phone)) {
    apiError(422, 'Le téléphone doit être au format international E.164');
}
if (!in_array($status, ['PENDING', 'OPTED_IN', 'OPTED_OUT'], true)) {
    apiError(422, 'Statut de consentement invalide');
}
foreach (['consent_source' => $source, 'evidence_reference' => $evidence] as $field => $value) {
    if ($value !== null && (!is_string($value) || strlen($value) > 255)) {
        apiError(422, $field . ' invalide');
    }
}
if ($status === 'OPTED_IN' && (!is_string($source) || trim($source) === '')) {
    apiError(422, 'La source du consentement est obligatoire pour OPTED_IN');
}

$parent = $pdo->prepare('SELECT id FROM parents WHERE id = :id LIMIT 1');
$parent->execute([':id' => $parentId]);
if (!$parent->fetchColumn()) {
    apiError(404, 'Parent introuvable');
}

$now = (new DateTimeImmutable())->format(DateTimeInterface::ATOM);
$consentedAt = $status === 'OPTED_IN' ? $now : null;
$revokedAt = $status === 'OPTED_OUT' ? $now : null;

$stmt = $pdo->prepare(
    'INSERT INTO whatsapp_consents
        (parent_id, purpose, phone_e164, status, consent_source, evidence_reference,
         consented_at, revoked_at, created_by, updated_by)
     VALUES
        (:parent_id, :purpose, :phone, :status, :source, :evidence,
         :consented_at, :revoked_at, :actor, :actor)
     ON CONFLICT (parent_id, purpose) DO UPDATE SET
        phone_e164 = EXCLUDED.phone_e164,
        status = EXCLUDED.status,
        consent_source = EXCLUDED.consent_source,
        evidence_reference = EXCLUDED.evidence_reference,
        consented_at = CASE WHEN EXCLUDED.status = \'OPTED_IN\' THEN NOW() ELSE NULL END,
        revoked_at = CASE WHEN EXCLUDED.status = \'OPTED_OUT\' THEN NOW() ELSE NULL END,
        updated_by = EXCLUDED.updated_by,
        updated_at = NOW()
     RETURNING id, parent_id, purpose, phone_e164, status, consent_source,
               evidence_reference, consented_at, revoked_at, updated_at'
);
$pdo->beginTransaction();
try {
    $previousStmt = $pdo->prepare(
        'SELECT id, status FROM whatsapp_consents WHERE parent_id = :parent_id AND purpose = :purpose FOR UPDATE'
    );
    $previousStmt->execute([':parent_id' => $parentId, ':purpose' => $purpose]);
    $previous = $previousStmt->fetch();

    $stmt->execute([
        ':parent_id' => $parentId,
        ':purpose' => $purpose,
        ':phone' => $phone,
        ':status' => $status,
        ':source' => $source,
        ':evidence' => $evidence,
        ':consented_at' => $consentedAt,
        ':revoked_at' => $revokedAt,
        ':actor' => $user['id'],
    ]);
    $consent = $stmt->fetch();

    $audit = $pdo->prepare(
        'INSERT INTO whatsapp_consent_audit
            (consent_id, parent_id, purpose, previous_status, new_status, actor_user_id)
         VALUES (:consent_id, :parent_id, :purpose, :previous_status, :new_status, :actor)'
    );
    $audit->execute([
        ':consent_id' => $consent['id'],
        ':parent_id' => $parentId,
        ':purpose' => $purpose,
        ':previous_status' => $previous['status'] ?? null,
        ':new_status' => $status,
        ':actor' => $user['id'],
    ]);
    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    throw $e;
}

echo json_encode(['success' => true, 'consent' => $consent], JSON_UNESCAPED_UNICODE);
