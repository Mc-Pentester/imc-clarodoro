<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/delivery-status.php';

header('Cache-Control: no-store');
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $verifyToken = getenv('WHATSAPP_WEBHOOK_VERIFY_TOKEN');
    $mode = $_GET['hub.mode'] ?? $_GET['hub_mode'] ?? '';
    $providedToken = $_GET['hub.verify_token'] ?? $_GET['hub_verify_token'] ?? '';
    $challenge = $_GET['hub.challenge'] ?? $_GET['hub_challenge'] ?? '';
    if (
        $mode !== 'subscribe' ||
        !is_string($verifyToken) || $verifyToken === '' ||
        !is_string($providedToken) || !hash_equals($verifyToken, $providedToken) ||
        !is_string($challenge) || $challenge === ''
    ) {
        http_response_code(403);
        header('Content-Type: text/plain; charset=utf-8');
        exit('Vérification webhook refusée.');
    }
    header('Content-Type: text/plain; charset=utf-8');
    echo $challenge;
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    http_response_code(405);
    exit;
}

$appSecret = getenv('WHATSAPP_APP_SECRET');
$signature = $_SERVER['HTTP_X_HUB_SIGNATURE_256'] ?? '';
$rawBody = file_get_contents('php://input');
if (!is_string($appSecret) || $appSecret === '' || !is_string($rawBody) || $rawBody === '') {
    http_response_code(503);
    exit;
}
if (strlen($rawBody) > 1048576) {
    http_response_code(413);
    exit;
}
$expectedSignature = 'sha256=' . hash_hmac('sha256', $rawBody, $appSecret);
if (!is_string($signature) || !hash_equals($expectedSignature, $signature)) {
    http_response_code(403);
    exit;
}

try {
    $payload = json_decode($rawBody, true, 512, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    http_response_code(400);
    exit;
}
if (!is_array($payload)) {
    http_response_code(400);
    exit;
}

$pdo = getDatabaseConnection();
$payloadHash = hash('sha256', $rawBody);
$processed = 0;
$messageIdsToReconcile = [];
$pdo->beginTransaction();
try {
    foreach (($payload['entry'] ?? []) as $entry) {
        if (!is_array($entry)) continue;
        foreach (($entry['changes'] ?? []) as $change) {
            if (!is_array($change)) continue;
            $statuses = $change['value']['statuses'] ?? [];
            if (!is_array($statuses)) continue;
            foreach ($statuses as $statusEvent) {
                if (!is_array($statusEvent)) continue;
                $messageId = $statusEvent['id'] ?? null;
                $rawStatus = strtolower((string) ($statusEvent['status'] ?? ''));
                $timestamp = $statusEvent['timestamp'] ?? null;
                $statusMap = ['sent' => 'SENT', 'delivered' => 'DELIVERED', 'read' => 'READ', 'failed' => 'FAILED'];
                if (
                    !is_string($messageId) || $messageId === '' || strlen($messageId) > 255 ||
                    !isset($statusMap[$rawStatus]) ||
                    !(is_string($timestamp) || is_int($timestamp) || is_float($timestamp)) ||
                    !ctype_digit((string) $timestamp) || (int) $timestamp <= 0
                ) {
                    continue;
                }
                $providerStatus = $statusMap[$rawStatus];
                $providerTime = (new DateTimeImmutable('@' . (int) $timestamp))->format('Y-m-d H:i:sP');
                $errorCode = null;
                if ($providerStatus === 'FAILED') {
                    $providerErrors = $statusEvent['errors'] ?? [];
                    if (is_array($providerErrors) && isset($providerErrors[0]) && is_array($providerErrors[0]) && isset($providerErrors[0]['code'])) {
                        $errorCode = substr((string) $providerErrors[0]['code'], 0, 80);
                    }
                }

                $eventInsert = $pdo->prepare(
                    'INSERT INTO whatsapp_webhook_events
                        (provider_message_id, provider_status, provider_timestamp, provider_error_code, payload_sha256)
                     VALUES (:message_id, :status, :provider_time, :error_code, :payload_hash)
                     ON CONFLICT (provider_message_id, provider_status, provider_timestamp) DO NOTHING
                     RETURNING id'
                );
                $eventInsert->execute([
                    ':message_id' => $messageId,
                    ':status' => $providerStatus,
                    ':provider_time' => $providerTime,
                    ':error_code' => $errorCode,
                    ':payload_hash' => $payloadHash,
                ]);
                if (!$eventInsert->fetchColumn()) continue;
                $messageIdsToReconcile[$messageId] = true;

                $log = $pdo->prepare(
                    'SELECT id, status FROM whatsapp_recipient_message_log
                     WHERE provider_message_id = :message_id
                     FOR UPDATE'
                );
                $log->execute([':message_id' => $messageId]);
                $messageLog = $log->fetch(PDO::FETCH_ASSOC);
                if (!$messageLog) continue;

                $rank = ['PROCESSING' => 0, 'SENT' => 1, 'DELIVERED' => 2, 'READ' => 3, 'FAILED' => 4];
                $currentStatus = (string) $messageLog['status'];
                // Ignore late/out-of-order events after a terminal status or an advanced receipt.
                if (in_array($currentStatus, ['READ', 'FAILED'], true)) continue;
                if (($rank[$providerStatus] ?? 0) < ($rank[$currentStatus] ?? 0)) continue;

                $update = $pdo->prepare(
                    'UPDATE whatsapp_recipient_message_log
                     SET status = :status,
                         provider_error_code = CASE WHEN :has_error THEN :error_code ELSE provider_error_code END,
                         updated_at = NOW()
                     WHERE id = :id'
                );
                $update->execute([
                    ':status' => $providerStatus,
                    ':has_error' => $errorCode !== null,
                    ':error_code' => $errorCode,
                    ':id' => $messageLog['id'],
                ]);
                $processed++;
            }
        }
    }
    $pdo->commit();
    // Reconcile again after commit to close the race where the webhook arrives
    // while the send log is still uncommitted and therefore invisible.
    foreach (array_keys($messageIdsToReconcile) as $messageId) {
        try {
            reconcileWhatsAppDeliveryStatus($pdo, (string) $messageId);
        } catch (Throwable $reconcileError) {
            error_log('WhatsApp webhook receipt reconciliation failed: ' . $reconcileError->getMessage());
        }
    }
} catch (Throwable $error) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('WhatsApp webhook processing failed: ' . $error->getMessage());
    http_response_code(503);
    exit;
}

header('Content-Type: application/json; charset=utf-8');
echo json_encode(['success' => true, 'processed' => $processed], JSON_UNESCAPED_UNICODE);
