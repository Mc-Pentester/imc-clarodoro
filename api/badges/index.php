<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $user = requirePermission($pdo, 'badge.create');
    $stmt = $pdo->prepare(
        'SELECT b.id, b.student_id, b.badge_data, b.created_at,
                s.matricule, s.last_name, s.first_name
         FROM student_badges b
         INNER JOIN students s ON s.id = b.student_id
         ORDER BY b.created_at DESC, b.id DESC
         LIMIT 200'
    );
    $stmt->execute();
    echo json_encode(['success' => true, 'badges' => $stmt->fetchAll()], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    apiError(405, 'Méthode non autorisée');
}

$user = requirePermission($pdo, 'badge.create');
requireCsrfToken();
$data = readJsonBody();

$studentId = isset($data['student_id']) && is_string($data['student_id'])
    ? trim($data['student_id'])
    : '';
if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $studentId)) {
    apiError(422, 'Identifiant élève invalide');
}

$badgeData = $data['badge_data'] ?? null;
if (!is_array($badgeData) || array_is_list($badgeData)) {
    apiError(422, 'Données du badge invalides');
}
$encoded = json_encode($badgeData, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
if (strlen($encoded) > 16384) {
    apiError(413, 'Les données du badge dépassent la taille autorisée');
}

$studentCheck = $pdo->prepare('SELECT id FROM students WHERE id = :id LIMIT 1');
$studentCheck->execute([':id' => $studentId]);
if (!$studentCheck->fetchColumn()) {
    apiError(404, 'Élève introuvable');
}

$stmt = $pdo->prepare(
    'INSERT INTO student_badges (student_id, created_by, badge_data)
     VALUES (:student_id, :created_by, CAST(:badge_data AS JSONB))
     RETURNING id, student_id, badge_data, created_at'
);
$stmt->execute([
    ':student_id' => $studentId,
    ':created_by' => $user['id'],
    ':badge_data' => $encoded,
]);
http_response_code(201);
echo json_encode(['success' => true, 'badge' => $stmt->fetch()], JSON_UNESCAPED_UNICODE);
