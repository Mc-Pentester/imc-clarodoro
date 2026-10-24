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
$templateName = $data['template_name'] ?? null;
$language = $data['language'] ?? 'fr';
$idempotencyKey = $data['idempotency_key'] ?? null;
$parameters = $data['parameters'] ?? [];

$uuidPattern = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';
if (!is_string($parentId) || !preg_match($uuidPattern, $parentId)) {
    apiError(422, 'parent_id UUID invalide');
}
if (!is_string($purpose) || !in_array($purpose, ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'], true)) {
    apiError(422, 'Finalité WhatsApp invalide');
}
if (!is_string($templateName) || !preg_match('/^[a-z0-9_]{1,128}$/', $templateName)) {
    apiError(422, 'Nom de modèle WhatsApp invalide');
}
if (!is_string($language) || !preg_match('/^[a-z]{2,3}(?:_[A-Z]{2})?$/', $language)) {
    apiError(422, 'Code de langue invalide');
}
if (!is_string($idempotencyKey) || !preg_match('/^[A-Za-z0-9._:-]{16,120}$/', $idempotencyKey)) {
    apiError(422, 'idempotency_key requis (16 à 120 caractères)');
}
if (!is_array($parameters) || count($parameters) > 20) {
    apiError(422, 'Paramètres du modèle invalides');
}
$bodyParameters = [];
foreach ($parameters as $parameter) {
    if (!is_string($parameter) || trim($parameter) === '' || strlen($parameter) > 1024) {
        apiError(422, 'Chaque paramètre doit être un texte non vide de 1024 caractères maximum');
    }
    $bodyParameters[] = ['type' => 'text', 'text' => $parameter];
}

// Keep the consent row locked until the provider has accepted/rejected the request.
 // The consent-update endpoint takes the same row lock, so revocation and send start
 // are serialized. This transaction intentionally spans the bounded provider call.
$pdo->beginTransaction();
$stmt = $pdo->prepare(
    "SELECT id, phone_e164, status
     FROM whatsapp_consents
     WHERE parent_id = :parent_id AND purpose = :purpose
     FOR UPDATE"
);
$stmt->execute([':parent_id' => $parentId, ':purpose' => $purpose]);
$consent = $stmt->fetch();
if (!$consent || $consent['status'] !== 'OPTED_IN') {
    $pdo->rollBack();
    apiError(403, 'Aucun consentement WhatsApp actif pour ce parent et cette finalité');
}

$enabled = getenv('WHATSAPP_SEND_ENABLED') === 'true';
$token = getenv('WHATSAPP_ACCESS_TOKEN');
$phoneNumberId = getenv('WHATSAPP_PHONE_NUMBER_ID');
$apiVersion = getenv('WHATSAPP_API_VERSION');
$allowedTemplatesRaw = getenv('WHATSAPP_ALLOWED_TEMPLATES');
$allowedTemplates = is_string($allowedTemplatesRaw)
    ? array_filter(array_map('trim', explode(',', $allowedTemplatesRaw)))
    : [];

if ($enabled) {
    if (!is_string($token) || $token === '' ||
        !is_string($phoneNumberId) || !preg_match('/^[0-9]+$/', $phoneNumberId) ||
        !is_string($apiVersion) || !preg_match('/^v[0-9]+\.[0-9]+$/', $apiVersion) ||
        !in_array($templateName, $allowedTemplates, true)) {
        apiError(503, 'Envoi réel non configuré ou modèle non autorisé');
    }
}

$payload = [
    'messaging_product' => 'whatsapp',
    'recipient_type' => 'individual',
    'to' => ltrim($consent['phone_e164'], '+'),
    'type' => 'template',
    'template' => [
        'name' => $templateName,
        'language' => ['code' => $language],
    ],
];
if ($bodyParameters !== []) {
    $payload['template']['components'] = [[
        'type' => 'body',
        'parameters' => $bodyParameters,
    ]];
}
$payloadJson = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
$payloadHash = hash('sha256', $payloadJson);

try {
    $insert = $pdo->prepare(
        "INSERT INTO whatsapp_message_log
            (consent_id, idempotency_key, purpose, status, template_name, payload_sha256, initiated_by)
         VALUES (:consent_id, :idempotency_key, :purpose, 'PROCESSING', :template_name, :payload_sha256, :initiated_by)
         ON CONFLICT (idempotency_key) DO NOTHING
         RETURNING id"
    );
    $insert->execute([
        ':consent_id' => $consent['id'],
        ':idempotency_key' => $idempotencyKey,
        ':purpose' => $purpose,
        ':template_name' => $templateName,
        ':payload_sha256' => $payloadHash,
        ':initiated_by' => $user['id'],
    ]);
    $logId = $insert->fetchColumn();
    if (!$logId) {
        $pdo->rollBack();
        apiError(409, 'Cette clé idempotente a déjà été utilisée; aucun nouvel envoi lancé');
    }
} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    apiError(503, 'Journal WhatsApp indisponible; aucun envoi lancé');
}

if (!$enabled) {
    $update = $pdo->prepare(
        "UPDATE whatsapp_message_log SET status = 'SIMULATED', updated_at = NOW() WHERE id = :id"
    );
    $update->execute([':id' => $logId]);
    $pdo->commit();
    echo json_encode([
        'success' => true,
        'mode' => 'simulation',
        'message_log_id' => $logId,
        'message' => 'Aucun appel réseau WhatsApp effectué.',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if (!function_exists('curl_init')) {
    $pdo->prepare("UPDATE whatsapp_message_log SET status = 'FAILED', provider_error_code = 'CURL_UNAVAILABLE', updated_at = NOW() WHERE id = :id")
        ->execute([':id' => $logId]);
    $pdo->commit();
    apiError(503, 'Extension cURL indisponible');
}

$url = 'https://graph.facebook.com/' . $apiVersion . '/' . $phoneNumberId . '/messages';
$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_TIMEOUT => 20,
    CURLOPT_HTTPHEADER => [
        'Authorization: Bearer ' . $token,
        'Content-Type: application/json',
    ],
    CURLOPT_POSTFIELDS => $payloadJson,
]);
$responseBody = curl_exec($ch);
$httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlError = curl_errno($ch);
curl_close($ch);

$response = is_string($responseBody) ? json_decode($responseBody, true) : null;
$providerMessageId = is_array($response) ? ($response['messages'][0]['id'] ?? null) : null;
if ($curlError === 0 && $httpCode >= 200 && $httpCode < 300 && is_string($providerMessageId)) {
    $pdo->prepare("UPDATE whatsapp_message_log SET status = 'SENT', provider_message_id = :message_id, updated_at = NOW() WHERE id = :id")
        ->execute([':message_id' => $providerMessageId, ':id' => $logId]);
    $pdo->commit();
    echo json_encode([
        'success' => true,
        'mode' => 'live',
        'message_log_id' => $logId,
        'provider_message_id' => $providerMessageId,
        'message' => 'WhatsApp a accepté la demande; cela ne confirme pas encore la livraison.',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$errorCode = is_array($response) ? (string) ($response['error']['code'] ?? 'PROVIDER_ERROR') : 'PROVIDER_ERROR';
$pdo->prepare("UPDATE whatsapp_message_log SET status = 'FAILED', provider_error_code = :error_code, updated_at = NOW() WHERE id = :id")
    ->execute([':error_code' => substr($errorCode, 0, 80), ':id' => $logId]);
$pdo->commit();
http_response_code(502);
echo json_encode([
    'success' => false,
    'message_log_id' => $logId,
    'error' => 'Le fournisseur WhatsApp a refusé ou n’a pas confirmé la demande.',
    'provider_error_code' => substr($errorCode, 0, 80),
], JSON_UNESCAPED_UNICODE);
