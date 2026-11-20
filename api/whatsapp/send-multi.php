<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
require_once __DIR__ . '/recipient-resolver.php';
require_once __DIR__ . '/delivery-status.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode HTTP non autorisée');
}
$pdo = getDatabaseConnection();
$user = requirePermission($pdo, 'whatsapp.message.send');
requireCsrfToken();
$data = readJsonBody();

$purpose = $data['purpose'] ?? '';
$templateName = $data['template_name'] ?? '';
$language = $data['language'] ?? 'fr';
$rootKey = $data['idempotency_key'] ?? '';
$parameters = $data['parameters'] ?? [];
$recipientType = strtoupper((string) ($data['recipient_type'] ?? 'STUDENT'));
$recipientId = $data['recipient_id'] ?? '';
$scope = strtoupper((string) ($data['scope'] ?? 'STUDENT_ONLY'));
$uuid = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';
$purposes = ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'];

if (!is_string($purpose) || !in_array($purpose, $purposes, true)) apiError(422, 'Finalité WhatsApp invalide');
if (!is_string($templateName) || !preg_match('/^[a-z0-9_]{1,128}$/', $templateName)) apiError(422, 'Modèle Meta invalide');
if (!is_string($language) || !preg_match('/^[a-z]{2,3}(?:_[A-Z]{2})?$/', $language)) apiError(422, 'Langue du modèle invalide');
if (!is_string($rootKey) || !preg_match('/^[A-Za-z0-9._:-]{16,80}$/', $rootKey)) apiError(422, 'Clé idempotente invalide');
if (!is_array($parameters) || count($parameters) > 20) apiError(422, 'Paramètres du modèle invalides');
$bodyParameters = [];
foreach ($parameters as $parameter) {
    if (!is_string($parameter) || trim($parameter) === '' || strlen($parameter) > 1024) apiError(422, 'Paramètre de modèle invalide');
    $bodyParameters[] = ['type' => 'text', 'text' => $parameter];
}

$enabled = getenv('WHATSAPP_SEND_ENABLED') === 'true';
$token = getenv('WHATSAPP_ACCESS_TOKEN');
$phoneNumberId = getenv('WHATSAPP_PHONE_NUMBER_ID');
$apiVersion = getenv('WHATSAPP_API_VERSION');
$templatesRaw = getenv('WHATSAPP_ALLOWED_TEMPLATES');
$allowedTemplates = is_string($templatesRaw) ? array_values(array_filter(array_map('trim', explode(',', $templatesRaw)))) : [];
$configured = $enabled && is_string($token) && $token !== ''
    && is_string($phoneNumberId) && preg_match('/^[0-9]+$/', $phoneNumberId)
    && is_string($apiVersion) && preg_match('/^v[0-9]+\\.[0-9]+$/', $apiVersion)
    && function_exists('curl_init') && in_array($templateName, $allowedTemplates, true);
if (!$configured) apiError(503, 'Envoi Meta non configuré ou modèle non autorisé; aucun message envoyé.');

if (!in_array($recipientType, ['STUDENT', 'PARENT', 'STAFF', 'TEACHER'], true)
    || !is_string($recipientId) || !preg_match($uuid, $recipientId)) {
    apiError(422, 'Type ou identifiant du destinataire invalide');
}
$consentTargets = resolveWhatsAppConsentTargets($pdo, $recipientType, $recipientId, $scope, $purpose);

if (!$consentTargets) apiError(403, 'Aucun destinataire ne possède un consentement WhatsApp actif pour cette finalité.');

$url = 'https://graph.facebook.com/' . $apiVersion . '/' . $phoneNumberId . '/messages';
$results = [];
$accepted = 0;
foreach ($consentTargets as $target) {
    $phone = (string) $target['phone_e164'];
    if (!preg_match('/^\\+[1-9][0-9]{7,14}$/', $phone)) {
        $results[] = ['consent_id' => $target['id'], 'status' => 'SKIPPED', 'reason' => 'INVALID_PHONE'];
        continue;
    }
    $key = $rootKey . ':' . (string) $target['id'];
    $payload = [
        'messaging_product' => 'whatsapp',
        'recipient_type' => 'individual',
        'to' => ltrim($phone, '+'),
        'type' => 'template',
        'template' => ['name' => $templateName, 'language' => ['code' => $language]],
    ];
    if ($bodyParameters) $payload['template']['components'] = [['type' => 'body', 'parameters' => $bodyParameters]];
    $payloadJson = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);

    try {
        $pdo->beginTransaction();
        $lock = $pdo->prepare('SELECT id, status, phone_e164 FROM whatsapp_recipient_consents WHERE id = :id FOR UPDATE');
        $lock->execute([':id' => $target['id']]);
        $current = $lock->fetch(PDO::FETCH_ASSOC);
        if (!$current || $current['status'] !== 'OPTED_IN' || $current['phone_e164'] !== $phone) {
            $pdo->rollBack();
            $results[] = ['consent_id' => $target['id'], 'status' => 'SKIPPED', 'reason' => 'CONSENT_NOT_ACTIVE'];
            continue;
        }
        // Claim the idempotency key and re-check consent in a short transaction.
        // The transaction is committed before any network I/O to Meta.
        $insert = $pdo->prepare(
            "INSERT INTO whatsapp_recipient_message_log
                (consent_id, idempotency_key, purpose, status, template_name, payload_sha256, initiated_by)
             VALUES (:consent, :key, :purpose, 'PROCESSING', :template, :hash, :actor)
             ON CONFLICT (idempotency_key) DO NOTHING RETURNING id"
        );
        $insert->execute([
            ':consent' => $target['id'], ':key' => $key, ':purpose' => $purpose,
            ':template' => $templateName, ':hash' => hash('sha256', $payloadJson), ':actor' => $user['id'],
        ]);
        $logId = $insert->fetchColumn();
        if (!$logId) {
            $existing = $pdo->prepare('SELECT id, status, provider_error_code FROM whatsapp_recipient_message_log WHERE idempotency_key = :key');
            $existing->execute([':key' => $key]);
            $existingLog = $existing->fetch(PDO::FETCH_ASSOC);
            $pdo->commit();
            $results[] = [
                'consent_id' => $target['id'],
                'status' => is_array($existingLog) ? (string) $existingLog['status'] : 'DUPLICATE',
                'reason' => 'IDEMPOTENCY_KEY_ALREADY_CLAIMED',
                'message_log_id' => is_array($existingLog) ? $existingLog['id'] : null,
            ];
            continue;
        }
        $pdo->commit();

        // Meta may take several seconds to answer. No PostgreSQL transaction
        // or consent row lock is held during this call.
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_TIMEOUT => 20,
            CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . $token, 'Content-Type: application/json'],
            CURLOPT_POSTFIELDS => $payloadJson,
        ]);
        $body = curl_exec($ch);
        $http = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_errno($ch);
        curl_close($ch);
        $provider = is_string($body) ? json_decode($body, true) : null;
        $messageId = is_array($provider) ? ($provider['messages'][0]['id'] ?? null) : null;

        if ($curlError === 0 && $http >= 200 && $http < 300 && is_string($messageId)) {
            $pdo->beginTransaction();
            $update = $pdo->prepare("UPDATE whatsapp_recipient_message_log SET status='SENT', provider_message_id=:message, updated_at=NOW() WHERE id=:id AND status='PROCESSING'");
            $update->execute([':message' => $messageId, ':id' => $logId]);
            $pdo->commit();
            try {
                reconcileWhatsAppDeliveryStatus($pdo, (string) $messageId);
            } catch (Throwable $reconcileError) {
                error_log('WhatsApp post-send receipt reconciliation failed: ' . $reconcileError->getMessage());
            }
            $accepted++;
            $finalStatus = 'SENT';
            try {
                $finalStatusStmt = $pdo->prepare('SELECT status FROM whatsapp_recipient_message_log WHERE id = :id');
                $finalStatusStmt->execute([':id' => $logId]);
                $storedStatus = $finalStatusStmt->fetchColumn();
                if (is_string($storedStatus)) $finalStatus = $storedStatus;
            } catch (Throwable $statusReadError) {
                error_log('WhatsApp post-send status read failed: ' . $statusReadError->getMessage());
            }
            $results[] = ['consent_id' => $target['id'], 'status' => $finalStatus, 'message_log_id' => $logId, 'provider_message_id' => $messageId];
        } else {
            $errorCode = is_array($provider) ? (string) ($provider['error']['code'] ?? 'PROVIDER_ERROR') : ($curlError ? 'NETWORK_UNCERTAIN' : 'PROVIDER_ERROR');
            $pdo->beginTransaction();
            $update = $pdo->prepare("UPDATE whatsapp_recipient_message_log SET status='FAILED', provider_error_code=:code, updated_at=NOW() WHERE id=:id AND status='PROCESSING'");
            $update->execute([':code' => substr($errorCode, 0, 80), ':id' => $logId]);
            $pdo->commit();
            $results[] = ['consent_id' => $target['id'], 'status' => 'FAILED', 'message_log_id' => $logId, 'provider_error_code' => substr($errorCode, 0, 80)];
        }
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        error_log('WhatsApp multi-recipient send failed: ' . $error->getMessage());
        // If Meta may already have accepted the request, leave PROCESSING in
        // place. The idempotency key remains consumed and must not be replayed.
        $results[] = ['consent_id' => $target['id'], 'status' => 'PROCESSING', 'reason' => 'OUTCOME_UNCERTAIN'];
    }
}

if ($accepted === 0) {
    http_response_code(502);
    echo json_encode([
        'success' => false,
        'error' => 'Aucun destinataire n’a reçu une acceptation de Meta. Consultez les résultats individuels avant toute nouvelle tentative.',
        'accepted_by_meta' => 0,
        'total_eligible' => count($consentTargets),
        'results' => $results,
        'message' => 'Une erreur réseau peut avoir une issue incertaine; aucun nouvel envoi automatique n’est lancé.',
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    exit;
}

echo json_encode([
    'success' => true,
    'accepted_by_meta' => $accepted,
    'total_eligible' => count($consentTargets),
    'results' => $results,
    'message' => 'Les résultats sont indiqués individuellement. Une acceptation par Meta ne confirme pas la livraison.',
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
