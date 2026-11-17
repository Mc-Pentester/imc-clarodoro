<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
require_once __DIR__ . '/../../config/email.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode HTTP non autorisée');
}
$pdo = getDatabaseConnection();
$user = requirePermission($pdo, 'whatsapp.consent.manage');
requireCsrfToken();
$data = readJsonBody();
$parentId = $data['parent_id'] ?? '';
if (!is_string($parentId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $parentId)) {
    apiError(422, 'Identifiant parent invalide');
}
$stmt = $pdo->prepare('SELECT id, first_name, last_name, email FROM parents WHERE id = :id');
$stmt->execute([':id' => $parentId]);
$parent = $stmt->fetch();
if (!$parent || !filter_var((string) $parent['email'], FILTER_VALIDATE_EMAIL)) {
    apiError(422, 'Aucune adresse e-mail valide n’est enregistrée pour ce parent.');
}
$baseUrl = rtrim((string) (getenv('APP_BASE_URL') ?: ''), '/');
if ($baseUrl === '' || !filter_var($baseUrl, FILTER_VALIDATE_URL) || !in_array((string) parse_url($baseUrl, PHP_URL_SCHEME), ['https', 'http'], true)) {
    apiError(503, 'APP_BASE_URL doit être configurée avant l’envoi des invitations.');
}
$token = bin2hex(random_bytes(32));
$code = (string) random_int(100000, 999999);
$challengeId = null;
try {
    $pdo->beginTransaction();
    $invalidate = $pdo->prepare('UPDATE whatsapp_consent_email_challenges SET used_at = NOW() WHERE parent_id = :parent_id AND used_at IS NULL');
    $invalidate->execute([':parent_id' => $parentId]);
    $insert = $pdo->prepare(
        'INSERT INTO whatsapp_consent_email_challenges
          (parent_id, email, invitation_token_hash, verification_code_hash, expires_at, initiated_by)
         VALUES (:parent_id, :email, :token_hash, :code_hash, NOW() + INTERVAL \'30 minutes\', :actor)
         RETURNING id'
    );
    $insert->execute([
        ':parent_id' => $parentId,
        ':email' => $parent['email'],
        ':token_hash' => hash('sha256', $token),
        ':code_hash' => hash('sha256', $code),
        ':actor' => $user['id'],
    ]);
    $challengeId = $insert->fetchColumn();
    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('WhatsApp consent invitation creation failed: ' . $e->getMessage());
    apiError(503, 'Impossible de préparer l’invitation.');
}
$link = $baseUrl . '/whatsapp-parent-consent.html?token=' . rawurlencode($token);
$body = "Bonjour " . $parent['first_name'] . ",\n\n"
    . "L’établissement vous invite à définir vos préférences de communication WhatsApp. "
    . "Aucun accord n’est présumé et aucun message ne sera envoyé sans votre choix explicite.\n\n"
    . "Ouvrir le formulaire sécurisé : " . $link . "\n\n"
    . "Code de confirmation : " . $code . "\n"
    . "Ce lien et ce code expirent dans 30 minutes. Si vous n’êtes pas à l’origine de cette demande, ignorez ce courriel.\n";
try {
    imcSendSmtpEmail((string) $parent['email'], 'Préférences WhatsApp — Clarodaro', $body);
} catch (Throwable $e) {
    error_log('WhatsApp consent invitation email failed: ' . $e->getMessage());
    $fail = $pdo->prepare('UPDATE whatsapp_consent_email_challenges SET used_at = NOW() WHERE id = :id');
    $fail->execute([':id' => $challengeId]);
    apiError(503, 'Le courriel n’a pas pu être envoyé. Vérifiez la configuration SMTP.');
}
echo json_encode(['success' => true, 'message' => 'Invitation envoyée à l’adresse e-mail enregistrée du parent.'], JSON_UNESCAPED_UNICODE);
