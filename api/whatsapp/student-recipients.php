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
requirePermission($pdo, 'whatsapp.message.send');

$uuidPattern = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';
$studentId = trim((string) ($_GET['student_id'] ?? ''));
$purpose = $_GET['purpose'] ?? '';

if (!preg_match($uuidPattern, $studentId)) {
    apiError(422, 'Identifiant élève invalide.');
}
if (!is_string($purpose) || !in_array($purpose, ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'], true)) {
    apiError(422, 'Finalité WhatsApp invalide.');
}

try {
    $studentStmt = $pdo->prepare(
        "SELECT id, first_name, last_name, matricule
         FROM students
         WHERE id = :student_id AND status = 'ACTIVE'
         LIMIT 1"
    );
    $studentStmt->execute([':student_id' => $studentId]);
    $student = $studentStmt->fetch(PDO::FETCH_ASSOC);
    if (!$student) {
        apiError(404, 'Élève actif introuvable.');
    }

    $stmt = $pdo->prepare(
        "SELECT
            p.id AS parent_id,
            p.first_name,
            p.last_name,
            sp.relationship_type,
            sp.is_primary,
            c.phone_e164,
            c.status AS consent_status,
            CASE
                WHEN c.status = 'OPTED_IN'
                 AND c.phone_e164 ~ '^[+][1-9][0-9]{7,14}$'
