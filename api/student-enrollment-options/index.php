<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');
$pdo = getDatabaseConnection();
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    header('Allow: GET');
    apiError(405, 'Méthode HTTP non autorisée');
}
requirePermission($pdo, 'eleves.create');
$classesStmt = $pdo->query("SELECT id, code, name FROM classes WHERE status = 'ACTIVE' ORDER BY name, code, id");
$yearsStmt = $pdo->query("SELECT id, label, start_date, end_date, status FROM school_years WHERE status = 'ACTIVE' ORDER BY start_date DESC, id DESC");
echo json_encode(['success' => true, 'classes' => $classesStmt->fetchAll(), 'schoolYears' => $yearsStmt->fetchAll()], JSON_UNESCAPED_UNICODE);
