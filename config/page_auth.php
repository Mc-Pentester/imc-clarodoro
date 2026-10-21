<?php
declare(strict_types=1);

/**
 * Autorisation des pages HTML sensibles.
 * Les décisions reposent sur la session PHP et le RBAC PostgreSQL existants.
 */
require_once __DIR__ . '/database.php';
require_once __DIR__ . '/auth.php';

function imcPageAccess(PDO $pdo, string $permission, ?string $requiredRole = null): array
{
    configureAuthSession();

    $now = time();
    $idleTimeout = authTimeoutSeconds('AUTH_IDLE_TIMEOUT_SECONDS', 900);
    $absoluteTimeout = authTimeoutSeconds('AUTH_ABSOLUTE_TIMEOUT_SECONDS', 28800);
    $authenticatedAt = isset($_SESSION['authenticated_at']) ? (int) $_SESSION['authenticated_at'] : 0;
    $lastActivityAt = isset($_SESSION['last_activity_at']) ? (int) $_SESSION['last_activity_at'] : $authenticatedAt;

    if (
        empty($_SESSION['user_id']) ||
        $authenticatedAt <= 0 ||
        $lastActivityAt <= 0 ||
        ($now - $authenticatedAt) >= $absoluteTimeout ||
        ($now - $lastActivityAt) >= $idleTimeout
    ) {
        $_SESSION = [];
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_destroy();
        }
        return ['allowed' => false, 'status' => 401, 'user' => null];
    }

    $stmt = $pdo->prepare(
        'SELECT u.id, u.status, r.name AS role_name, u.role_id
         FROM users u
         INNER JOIN roles r ON r.id = u.role_id
         WHERE u.id = :user_id
         LIMIT 1'
    );
    $stmt->execute([':user_id' => $_SESSION['user_id']]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user || $user['status'] !== 'ACTIVE') {
        $_SESSION = [];
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_destroy();
        }
        return ['allowed' => false, 'status' => 401, 'user' => null];
    }

    if ($requiredRole !== null && strcasecmp((string) $user['role_name'], $requiredRole) !== 0) {
        return ['allowed' => false, 'status' => 403, 'user' => $user];
    }

    $permissionStmt = $pdo->prepare(
        'SELECT 1
         FROM role_permissions rp
         INNER JOIN permissions p ON p.id = rp.permission_id
         WHERE rp.role_id = :role_id AND p.name = :permission
         LIMIT 1'
    );
    $permissionStmt->execute([
        ':role_id' => $user['role_id'],
        ':permission' => $permission,
    ]);

    if (!$permissionStmt->fetchColumn()) {
        return ['allowed' => false, 'status' => 403, 'user' => $user];
    }

    $_SESSION['last_activity_at'] = $now;
    return ['allowed' => true, 'status' => 200, 'user' => $user];
}

function imcRequirePageAccess(string $permission, ?string $requiredRole = null): void
{
    $pdo = getDatabaseConnection();
    $access = imcPageAccess($pdo, $permission, $requiredRole);
    if ($access['allowed']) {
        return;
    }

    http_response_code((int) $access['status']);
    header('Content-Type: text/plain; charset=utf-8');
    header('Cache-Control: no-store, private');
    echo $access['status'] === 401 ? 'Authentification requise.' : 'Permission insuffisante.';
    exit;
}
