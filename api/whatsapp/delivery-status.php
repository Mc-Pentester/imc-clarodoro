<?php
declare(strict_types=1);

/**
 * Reconcile Meta receipts that may arrive before the send transaction commits.
 * Call only after the webhook event or message-log transaction has committed.
 */
function reconcileWhatsAppDeliveryStatus(PDO $pdo, string $providerMessageId): void
{
    if ($providerMessageId === '' || strlen($providerMessageId) > 255) return;

    $ownsTransaction = !$pdo->inTransaction();
    if ($ownsTransaction) $pdo->beginTransaction();
    try {
        $logStmt = $pdo->prepare(
            'SELECT id, status FROM whatsapp_recipient_message_log
             WHERE provider_message_id = :message_id
             FOR UPDATE'
        );
        $logStmt->execute([':message_id' => $providerMessageId]);
        $log = $logStmt->fetch(PDO::FETCH_ASSOC);
        if (!$log) {
            if ($ownsTransaction) $pdo->commit();
            return;
        }

        $eventsStmt = $pdo->prepare(
            "SELECT provider_status, provider_error_code
             FROM whatsapp_webhook_events
             WHERE provider_message_id = :message_id
             ORDER BY provider_timestamp ASC,
               CASE provider_status
                 WHEN 'SENT' THEN 1
                 WHEN 'DELIVERED' THEN 2
                 WHEN 'READ' THEN 3
                 WHEN 'FAILED' THEN 4
                 ELSE 0
               END ASC"
        );
        $eventsStmt->execute([':message_id' => $providerMessageId]);
        $events = $eventsStmt->fetchAll(PDO::FETCH_ASSOC);

        $rank = ['PROCESSING' => 0, 'SENT' => 1, 'DELIVERED' => 2, 'READ' => 3, 'FAILED' => 4];
        $currentStatus = (string) $log['status'];
        $errorCode = null;
        foreach ($events as $event) {
            if (in_array($currentStatus, ['READ', 'FAILED'], true)) break;
            $nextStatus = (string) $event['provider_status'];
            if (($rank[$nextStatus] ?? 0) >= ($rank[$currentStatus] ?? 0)) {
                $currentStatus = $nextStatus;
                if ($nextStatus === 'FAILED') $errorCode = $event['provider_error_code'];
            }
        }

        if ($currentStatus !== (string) $log['status'] || $errorCode !== null) {
            if ($errorCode !== null) {
                $update = $pdo->prepare(
                    'UPDATE whatsapp_recipient_message_log
                     SET status = :status, provider_error_code = :error_code, updated_at = NOW()
                     WHERE id = :id'
                );
                $update->execute([
                    ':status' => $currentStatus,
                    ':error_code' => $errorCode,
                    ':id' => $log['id'],
                ]);
            } else {
                $update = $pdo->prepare(
                    'UPDATE whatsapp_recipient_message_log
                     SET status = :status, updated_at = NOW()
                     WHERE id = :id'
                );
                $update->execute([':status' => $currentStatus, ':id' => $log['id']]);
            }
        }
        if ($ownsTransaction) $pdo->commit();
    } catch (Throwable $error) {
        if ($ownsTransaction && $pdo->inTransaction()) $pdo->rollBack();
        throw $error;
    }
}
