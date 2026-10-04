<?php
declare(strict_types=1);

require_once __DIR__ . '/database.php';

function configureAuthSession(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }

    ini_set('session.use_only_cookies', '1');
    ini_set('session.use_strict_mode', '1');
    ini_set('session.use_trans_sid', '0');

    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
        'httponly' => true,
        'samesite' => 'Lax',
    ]);

    session_name('IMC_SESSION');
    session_start();
}

function apiError(int $status, string $message): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');

    echo json_encode([
        'success' => false,
        'error' => $message,
    ], JSON_UNESCAPED_UNICODE);

    exit;
}

function readJsonBody(): array
{
    $raw = file_get_contents('php://input');

    if ($raw === false || trim($raw) === '') {
        apiError(400, 'Corps JSON requis');
    }

    try {
        $data = json_decode(
            $raw,
            true,
            512,
            JSON_THROW_ON_ERROR
        );
    } catch (JsonException) {
        apiError(400, 'JSON invalide');
    }

    if (!is_array($data)) {
        apiError(400, 'Corps JSON invalide');
    }

    return $data;
}

function requireAuthenticatedUser(PDO $pdo): array
{
    configureAuthSession();

    if (empty($_SESSION['user_id'])) {
        apiError(401, 'Authentification requise');
    }

    $stmt = $pdo->prepare(
        'SELECT
            u.id,
            u.username,
            u.role_id,
            u.status,
            r.name AS role_name
         FROM users u
         INNER JOIN roles r
            ON r.id = u.role_id
         WHERE u.id = :user_id
         LIMIT 1'
    );

    $stmt->execute([
        ':user_id' => $_SESSION['user_id'],
    ]);

    $user = $stmt->fetch();

    if (!$user) {
        session_destroy();
        apiError(401, 'Authentification requise');
    }

    if ($user['status'] !== 'ACTIVE') {
        session_destroy();
        apiError(403, 'Compte non actif');
    }

    $_SESSION['user_id'] = $user['id'];
    $_SESSION['username'] = $user['username'];
    $_SESSION['role_id'] = $user['role_id'];
    $_SESSION['role_name'] = $user['role_name'];

    return [
        'id' => $user['id'],
        'username' => $user['username'],
        'role_id' => $user['role_id'],
        'role_name' => $user['role_name'],
    ];
}

function requirePermission(PDO $pdo, string $permissionName): array
{
    $user = requireAuthenticatedUser($pdo);

    $stmt = $pdo->prepare(
        'SELECT 1
         FROM role_permissions rp
         INNER JOIN permissions p
             ON p.id = rp.permission_id
         WHERE rp.role_id = :role_id
           AND p.name = :permission
         LIMIT 1'
    );

    $stmt->execute([
        ':role_id' => $user['role_id'],
        ':permission' => $permissionName,
    ]);

    if (!$stmt->fetchColumn()) {
        apiError(403, 'Permission insuffisante');
    }

    return $user;
}