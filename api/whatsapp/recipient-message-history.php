<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    apiError(405, 'Méthode HTTP non autorisée');
}
$pdo = getDatabaseConnection();
requirePermission($pdo, 'whatsapp.message.audit');

try {
    $stmt = $pdo->query(
        "SELECT l.id, c.recipient_type,
                COALESCE(
                    NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
                    NULLIF(TRIM(CONCAT_WS(' ', s.first_name, s.last_name)), ''),
                    NULLIF(TRIM(CONCAT_WS(' ', st.first_name, st.last_name)), ''),
                    NULLIF(TRIM(CONCAT_WS(' ', t.first_name, t.last_name)), ''),
                    'Destinataire'
                ) AS recipient_name,
                l.purpose, l.status, l.template_name,
                l.provider_message_id, l.provider_error_code, l.created_at, l.updated_at
         FROM whatsapp_recipient_message_log l
         INNER JOIN whatsapp_recipient_consents c ON c.id = l.consent_id
         LEFT JOIN parents p ON p.id = c.parent_id
         LEFT JOIN students s ON s.id = c.student_id
         LEFT JOIN staff st ON st.id = c.staff_id
         LEFT JOIN teachers t ON t.id = c.teacher_id
         ORDER BY l.created_at DESC
         LIMIT 100"
    );
    echo json_encode(['success' => true, 'messages' => $stmt->fetchAll()], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
} catch (Throwable $error) {
    error_log('WhatsApp message history failed: ' . $error->getMessage());
    apiError(503, 'Historique WhatsApp temporairement indisponible');
}
