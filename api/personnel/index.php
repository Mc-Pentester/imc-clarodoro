<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'];

function staffApiResponse(array $data, int $status = 200): never
{
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function normalizeStaffName(string $value): string
{
    $value = trim($value);
    if ($value === '' || mb_strlen($value) > 150) {
        apiError(400, 'Nom invalide');
    }
    return $value;
}

function normalizeStaffRole(string $role): string
{
    $allowed = ['PDG', 'Directeur', 'Enseignant', 'Secrétaire', 'Surveillant', 'Autre'];
    if (!in_array($role, $allowed, true)) {
        apiError(400, 'Fonction invalide');
    }
    return $role;
}

function requireStaffRoleAssignment(array $actor, string $targetRole): void
{
    if ($targetRole === 'PDG' || $targetRole === 'Directeur') {
        if ($actor['role_name'] !== 'PDG') {
            apiError(403, 'Seul le PDG peut attribuer ce rôle');
        }
    }
}

function getRoleId(PDO $pdo, string $roleName): string
{
    $stmt = $pdo->prepare('SELECT id FROM roles WHERE name = :name LIMIT 1');
    $stmt->execute([':name' => $roleName]);
    $id = $stmt->fetchColumn();
    if (!$id) {
        apiError(500, 'Rôle RBAC introuvable');
    }
    return (string) $id;
}

function writeStaffAudit(PDO $pdo, string $actorUserId, ?string $staffId, string $action, array $details): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO staff_audit_log (actor_user_id, staff_id, action, details)
         VALUES (:actor, :staff, :action, CAST(:details AS jsonb))'
    );
    $stmt->execute([
        ':actor' => $actorUserId,
        ':staff' => $staffId,
        ':action' => $action,
        ':details' => json_encode($details, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
    ]);
}

if ($method === 'GET') {
    $user = requirePermission($pdo, 'personnel.read');

    $stmt = $pdo->query(
        'SELECT
            s.id,
            s.first_name,
            s.last_name,
            s.function_name,
            s.class_name,
            s.phone,
            s.email,
            s.status,
            s.user_id,
            u.username,
            u.status AS user_status,
            r.name AS role_name,
            s.created_at,
            s.updated_at
         FROM staff s
         LEFT JOIN users u ON u.id = s.user_id
         LEFT JOIN roles r ON r.id = u.role_id
         ORDER BY s.last_name ASC, s.first_name ASC, s.created_at ASC'
    );

    staffApiResponse([
        'success' => true,
        'user' => $user,
        'staff' => $stmt->fetchAll(),
    ]);
}

if (!in_array($method, ['POST'], true)) {
    header('Allow: GET, POST');
    apiError(405, 'Méthode non autorisée');
}

$actor = requireAuthenticatedUser($pdo);
requireCsrfToken();
$data = readJsonBody();

$action = isset($data['action']) && is_string($data['action'])
    ? trim($data['action'])
    : '';

if ($action === '') {
    apiError(400, 'Action requise');
}

if ($action === 'create') {
    requirePermission($pdo, 'personnel.create');

    $fullName = normalizeStaffName((string) ($data['name'] ?? ''));
    $parts = preg_split('/\s+/', $fullName, 2);
    $firstName = $parts[0] ?? '';
    $lastName = $parts[1] ?? $firstName;
    $roleName = normalizeStaffRole((string) ($data['role'] ?? ''));
    $username = trim((string) ($data['username'] ?? ''));
    $password = (string) ($data['password'] ?? '');
    $className = trim((string) ($data['class_name'] ?? ''));

    if ($username === '' || mb_strlen($username) > 100) {
        apiError(400, 'Identifiant invalide');
    }
    if (mb_strlen($password) < 8) {
        apiError(400, 'Le mot de passe doit contenir au moins 8 caractères');
    }
    requireStaffRoleAssignment($actor, $roleName);

    try {
        $pdo->beginTransaction();

        $roleId = getRoleId($pdo, $roleName);

        $userStmt = $pdo->prepare(
            'INSERT INTO users (username, password_hash, role_id, status)
             VALUES (:username, :password_hash, :role_id, 'ACTIVE')
             RETURNING id'
        );
        $userStmt->execute([
            ':username' => $username,
            ':password_hash' => password_hash($password, PASSWORD_DEFAULT),
            ':role_id' => $roleId,
        ]);
        $userId = (string) $userStmt->fetchColumn();

        $staffStmt = $pdo->prepare(
            'INSERT INTO staff
                (user_id, first_name, last_name, function_name, class_name, status)
             VALUES
                (:user_id, :first_name, :last_name, :function_name, :class_name, 'ACTIVE')
             RETURNING id'
        );
        $staffStmt->execute([
            ':user_id' => $userId,
            ':first_name' => $firstName,
            ':last_name' => $lastName,
            ':function_name' => $roleName,
            ':class_name' => $className !== '' ? $className : null,
        ]);
        $staffId = (string) $staffStmt->fetchColumn();

        writeStaffAudit($pdo, (string) $actor['id'], $staffId, 'CREATE', [
            'username' => $username,
            'role' => $roleName,
        ]);

        $pdo->commit();

        staffApiResponse([
            'success' => true,
            'staffId' => $staffId,
            'userId' => $userId,
        ], 201);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        if ($e instanceof PDOException && $e->getCode() === '23505') {
            apiError(409, 'Cet identifiant existe déjà');
        }
        throw $e;
    }
}

if ($action === 'update') {
    requirePermission($pdo, 'personnel.update');

    $staffId = trim((string) ($data['staff_id'] ?? ''));
    $fullName = normalizeStaffName((string) ($data['name'] ?? ''));
    $parts = preg_split('/\s+/', $fullName, 2);
    $firstName = $parts[0] ?? '';
    $lastName = $parts[1] ?? $firstName;
    $roleName = normalizeStaffRole((string) ($data['role'] ?? ''));
    $username = trim((string) ($data['username'] ?? ''));
    $password = (string) ($data['password'] ?? '');
    $className = trim((string) ($data['class_name'] ?? ''));

    if ($staffId === '' || $username === '') {
        apiError(400, 'Personnel et identifiant requis');
    }

    requireStaffRoleAssignment($actor, $roleName);

    try {
        $pdo->beginTransaction();

        $staffStmt = $pdo->prepare(
            'SELECT s.id, s.user_id, u.username, u.role_id
             FROM staff s
             LEFT JOIN users u ON u.id = s.user_id
             WHERE s.id = :id
             FOR UPDATE'
        );
        $staffStmt->execute([':id' => $staffId]);
        $staff = $staffStmt->fetch();

        if (!$staff) {
            $pdo->rollBack();
            apiError(404, 'Personnel introuvable');
        }

        if (!$staff['user_id']) {
            $pdo->rollBack();
            apiError(409, 'Personnel sans compte serveur');
        }

        if ((string) $staff['user_id'] === (string) $actor['id'] && $roleName !== $actor['role_name']) {
            $pdo->rollBack();
            apiError(403, 'Impossible de modifier son propre rôle');
        }

        $roleId = getRoleId($pdo, $roleName);

        $userUpdate = $pdo->prepare(
            'UPDATE users
             SET username = :username,
                 role_id = :role_id,
                 password_hash = CASE
                     WHEN :password <> '' THEN :password_hash
                     ELSE password_hash
                 END,
                 updated_at = NOW()
             WHERE id = :id'
        );
        $userUpdate->execute([
            ':username' => $username,
            ':role_id' => $roleId,
            ':password' => $password,
            ':password_hash' => $password !== '' ? password_hash($password, PASSWORD_DEFAULT) : '',
            ':id' => $staff['user_id'],
        ]);

        $staffUpdate = $pdo->prepare(
            'UPDATE staff
             SET first_name = :first_name,
                 last_name = :last_name,
                 function_name = :function_name,
                 class_name = :class_name,
                 updated_at = NOW()
             WHERE id = :id'
        );
        $staffUpdate->execute([
            ':first_name' => $firstName,
            ':last_name' => $lastName,
            ':function_name' => $roleName,
            ':class_name' => $className !== '' ? $className : null,
            ':id' => $staffId,
        ]);

        writeStaffAudit($pdo, (string) $actor['id'], $staffId, 'UPDATE', [
            'username' => $username,
            'role' => $roleName,
            'password_changed' => $password !== '',
        ]);

        $pdo->commit();

        staffApiResponse(['success' => true]);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        if ($e instanceof PDOException && $e->getCode() === '23505') {
            apiError(409, 'Cet identifiant existe déjà');
        }
        throw $e;
    }
}

if ($action === 'delete') {
    requirePermission($pdo, 'personnel.delete');

    $staffId = trim((string) ($data['staff_id'] ?? ''));
    if ($staffId === '') {
        apiError(400, 'Personnel requis');
    }

    try {
        $pdo->beginTransaction();

        $stmt = $pdo->prepare(
            'SELECT s.id, s.user_id
             FROM staff s
             WHERE s.id = :id
             FOR UPDATE'
        );
        $stmt->execute([':id' => $staffId]);
        $staff = $stmt->fetch();

        if (!$staff) {
            $pdo->rollBack();
            apiError(404, 'Personnel introuvable');
        }

        if ((string) ($staff['user_id'] ?? '') === (string) $actor['id']) {
            $pdo->rollBack();
            apiError(403, 'Impossible d’archiver son propre compte');
        }

        $pdo->prepare(
            'UPDATE staff
             SET status = 'ARCHIVED', updated_at = NOW()
             WHERE id = :id'
        )->execute([':id' => $staffId]);

        if ($staff['user_id']) {
            $pdo->prepare(
                'UPDATE users
                 SET status = 'INACTIVE', updated_at = NOW()
                 WHERE id = :id'
            )->execute([':id' => $staff['user_id']]);
        }

        writeStaffAudit($pdo, (string) $actor['id'], $staffId, 'ARCHIVE', []);

        $pdo->commit();

        staffApiResponse(['success' => true]);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}

apiError(400, 'Action inconnue');
