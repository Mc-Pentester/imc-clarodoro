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
requirePermission($pdo, 'whatsapp.recipient.read');

$type = strtoupper((string) ($_GET['recipient_type'] ?? ''));
$q = trim((string) ($_GET['q'] ?? ''));
if (!in_array($type, ['PARENT', 'STUDENT', 'STAFF', 'TEACHER'], true)) {
    apiError(422, 'Type de destinataire invalide');
}
if (mb_strlen($q) < 2 || mb_strlen($q) > 100) {
    apiError(422, 'Saisissez au moins 2 caractères');
}
$like = '%' . $q . '%';
$digits = preg_replace('/\D+/', '', $q) ?? '';
try {
    if ($type === 'PARENT') {
        $sql = "SELECT id, first_name, last_name, phone FROM parents
                WHERE first_name ILIKE :q1 OR last_name ILIKE :q2
                   OR (first_name || ' ' || last_name) ILIKE :q3
                   OR (:digits <> '' AND regexp_replace(COALESCE(phone,''), '[^0-9]', '', 'g') LIKE :phone)
                ORDER BY last_name, first_name LIMIT 30";
    } elseif ($type === 'STUDENT') {
        $sql = "SELECT id, first_name, last_name, phone FROM students
                WHERE status = 'ACTIVE' AND (first_name ILIKE :q OR last_name ILIKE :q
                   OR (first_name || ' ' || last_name) ILIKE :q OR matricule ILIKE :q)
                ORDER BY last_name, first_name LIMIT 30";
    } elseif ($type === 'STAFF') {
        $sql = "SELECT id, first_name, last_name, phone FROM staff
                WHERE status = 'ACTIVE' AND (first_name ILIKE :q OR last_name ILIKE :q
                   OR (first_name || ' ' || last_name) ILIKE :q)
                ORDER BY last_name, first_name LIMIT 30";
    } else {
        $sql = "SELECT id, first_name, last_name, phone FROM teachers
                WHERE status = 'ACTIVE' AND (first_name ILIKE :q OR last_name ILIKE :q
                   OR (first_name || ' ' || last_name) ILIKE :q)
                ORDER BY last_name, first_name LIMIT 30";
    }
    $stmt = $pdo->prepare($sql);
    $params = [':q1' => $like, ':q2' => $like, ':q3' => $like];
    if ($type === 'STUDENT') $params[':q4'] = $like;
    if ($type === 'PARENT') {
        $params[':digits'] = $digits;
        $params[':phone'] = '%' . $digits . '%';
    }
    $stmt->execute($params);
    echo json_encode([
        'success' => true,
        'recipient_type' => $type,
        'recipients' => array_map(static fn(array $row): array => [
            'id' => (string) $row['id'],
            'first_name' => (string) $row['first_name'],
            'last_name' => (string) $row['last_name'],
            'phone' => (string) ($row['phone'] ?? ''),
        ], $stmt->fetchAll()),
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
} catch (Throwable $error) {
    error_log('WhatsApp recipient search failed: ' . $error->getMessage());
    apiError(503, 'Recherche des destinataires indisponible');
}
