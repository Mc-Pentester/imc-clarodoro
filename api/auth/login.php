<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode non autorisée');
}

configureAuthSession();

$data = readJsonBody();

$username = isset($data['username']) && is_string($data['username'])
    ? trim($data['username'])
    : '';

$password = isset($data['password']) && is_string($data['password'])
    ? $data['password']
    : '';

if ($username === '' || $password === '') {
    apiError(400, 'Identifiant et mot de passe requis');
}

$pdo = getDatabaseConnection();

$stmt = $pdo->prepare(
    'SELECT
        u.id,
        u.username,
        u.password_hash,
        u.role_id,
        u.status,
        r.name AS role_name
     FROM users u
     INNER JOIN roles r
        ON r.id = u.role_id
     WHERE u.username = :username
     LIMIT 1'
);

$stmt->execute([
    ':username' => $username,
]);

$user = $stmt->fetch();

if (!$user || !password_verify($password, $user['password_hash'])) {
    apiError(401, 'Identifiant ou mot de passe incorrect');
}

if ($user['status'] !== 'ACTIVE') {
    apiError(403, 'Compte non actif');
}

session_regenerate_id(true);

$_SESSION['user_id'] = $user['id'];
$_SESSION['username'] = $user['username'];
$_SESSION['role_id'] = $user['role_id'];
$_SESSION['role_name'] = $user['role_name'];
$_SESSION['authenticated_at'] = time();

echo json_encode([
    'success' => true,
    'user' => [
        'id' => $user['id'],
        'username' => $user['username'],
        'role' => $user['role_name'],
    ],
], JSON_UNESCAPED_UNICODE);