<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    header('Allow: GET');
    apiError(405, 'Méthode non autorisée');
}

$pdo = getDatabaseConnection();
$user = requirePermission($pdo, 'eleves.create');

echo json_encode([
    'success' => true,
    'authorized' => true,
    'permission' => 'eleves.create',
    'user' => [
        'id' => $user['id'],
        'username' => $user['username'],
        'role' => $user['role_name'],
    ],
], JSON_UNESCAPED_UNICODE);
