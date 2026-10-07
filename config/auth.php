<?php

require_once __DIR__ . '/../middleware/security_headers.php';
sendApiSecurityHeaders();
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

function authTimeoutSeconds(string $envName, int $default): int
{
    $value = getenv($envName);

    if ($value === false || $value === '' || !ctype_digit((string) $value)) {
        return $default;
    }

    return max(1, (int) $value);
}

function expireAuthSession(string $message = 'Session expirée'): never
{
    $_SESSION = [];

    if (ini_get('session.use_cookies')) {
        $params = session_get_cookie_params();

        setcookie(session_name(), '', [
            'expires' => time() - 42000,
            'path' => $params['path'],
            'secure' => $params['secure'],
            'httponly' => $params['httponly'],
            'samesite' => $params['samesite'] ?? 'Lax',
        ]);
    }

    session_destroy();
    apiError(401, $message);
}

function enforceAuthSessionLifetime(): void
{
    $now = time();
    $idleTimeout = authTimeoutSeconds('AUTH_IDLE_TIMEOUT_SECONDS', 900);
    $absoluteTimeout = authTimeoutSeconds('AUTH_ABSOLUTE_TIMEOUT_SECONDS', 28800);

    $authenticatedAt = isset($_SESSION['authenticated_at'])
        ? (int) $_SESSION['authenticated_at']
        : 0;

    $lastActivityAt = isset($_SESSION['last_activity_at'])
        ? (int) $_SESSION['last_activity_at']
        : $authenticatedAt;

    if (
        $authenticatedAt <= 0 ||
        $lastActivityAt <= 0 ||
        ($now - $authenticatedAt) >= $absoluteTimeout ||
        ($now - $lastActivityAt) >= $idleTimeout
    ) {
        expireAuthSession();
    }

    $_SESSION['last_activity_at'] = $now;
}

function requireAuthenticatedUser(PDO $pdo): array
{
    configureAuthSession();
    enforceAuthSessionLifetime();

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