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
$user = requireAuthenticatedUser($pdo);

echo json_encode([
    'success' => true,
    'user' => [
        'id' => $user['id'],
        'username' => $user['username'],
        'role' => $user['role_name'],
    ],
    'csrfToken' => generateCsrfToken(),
], JSON_UNESCAPED_UNICODE);