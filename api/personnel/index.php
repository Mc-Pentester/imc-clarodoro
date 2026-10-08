<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

$pdo = getDatabaseConnection();
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

function personnelJson(array $data, int $status = 200): never
{
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function personnelText(array $data, string $key, int $max = 150): string
{
    $value = trim((string) ($data[$key] ?? ''));
    if ($value === '' || mb_strlen($value) > $max) {
        apiError(400, "Champ {$key} invalide");
    }
    return $value;
}

function personnelOptionalText(array $data, string $key, int $max = 150): ?string
{
    $value = trim((string) ($data[$key] ?? ''));
    if ($value === '') {
        return null;
    }
    if (mb_strlen($value) > $max) {
        apiError(400, "Champ {$key} invalide");
    }
    return $value;
}

if ($method === 'GET') {
    requirePermission($pdo, 'personnel.read');

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
            r.name AS role_name
         FROM staff s
         LEFT JOIN users u ON u.id = s.user_id
         LEFT JOIN roles r ON r.id = u.role_id
         WHERE s.status <> \'ARCHIVED\'
         ORDER BY s.last_name, s.first_name, s.id'
    );

    personnelJson([
        'success' => true,
        'personnel' => $stmt->fetchAll(),
    ]);
}

if ($method === 'POST') {
    requirePermission($pdo, 'personnel.create');
    requireCsrfToken();

    $body = readJsonBody();
    $firstName = personnelText($body, 'first_name');
    $lastName = personnelText($body, 'last_name');
    $functionName = personnelOptionalText($body, 'function_name');
    $className = personnelOptionalText($body, 'class_name');
    $phone = personnelOptionalText($body, 'phone', 50);
    $email = personnelOptionalText($body, 'email', 255);
    $username = personnelText($body, 'username', 100);
    $password = (string) ($body['password'] ?? '');

    if (strlen($password) < 8 || strlen($password) > 255) {
        apiError(400, 'Mot de passe invalide');
    }

    $roleName = $body['role_name'] ?? 'Autre';
    if (!is_string($roleName) || trim($roleName) === '') {
        $roleName = 'Autre';
    }

    $pdo->beginTransaction();

    try {
        $roleStmt = $pdo->prepare('SELECT id FROM roles WHERE name = :name LIMIT 1');
        $roleStmt->execute([':name' => trim($roleName)]);
        $roleId = $roleStmt->fetchColumn();

        if ($roleId === false) {
            $pdo->rollBack();
            apiError(400, 'Rôle invalide');
        }

        $userStmt = $pdo->prepare(
            'INSERT INTO users (username, email, password_hash, role_id, status)
             VALUES (:username, :email, :password_hash, :role_id, \'ACTIVE\')
             RETURNING id'
        );
        $userStmt->execute([
            ':username' => $username,
            ':email' => $email,
            ':password_hash' => password_hash($password, PASSWORD_DEFAULT),
            ':role_id' => $roleId,
        ]);
        $userId = $userStmt->fetchColumn();

        $staffStmt = $pdo->prepare(
            'INSERT INTO staff
                (first_name, last_name, function_name, class_name, phone, email, status, user_id)
             VALUES
                (:first_name, :last_name, :function_name, :class_name, :phone, :email, \'ACTIVE\', :user_id)
             RETURNING id'
        );
        $staffStmt->execute([
            ':first_name' => $firstName,
            ':last_name' => $lastName,
            ':function_name' => $functionName,
            ':class_name' => $className,
            ':phone' => $phone,
            ':email' => $email,
            ':user_id' => $userId,
        ]);
        $staffId = $staffStmt->fetchColumn();

        $pdo->commit();
        personnelJson(['success' => true, 'id' => $staffId], 201);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        if ($e->getCode() === '23505') {
            apiError(409, 'Identifiant ou adresse déjà utilisé');
        }
        throw $e;
    }
}

if (in_array($method, ['PUT', 'PATCH'], true)) {
    $actor = requirePermission($pdo, 'personnel.update');
    requireCsrfToken();

    $body = readJsonBody();
    $id = trim((string) ($body['id'] ?? ''));
    if ($id === '') {
        apiError(400, 'Identifiant personnel requis');
    }

    $firstName = personnelText($body, 'first_name');
    $lastName = personnelText($body, 'last_name');
    $functionName = personnelOptionalText($body, 'function_name');
    $className = personnelOptionalText($body, 'class_name');
    $phone = personnelOptionalText($body, 'phone', 50);
    $email = personnelOptionalText($body, 'email', 255);

    $pdo->beginTransaction();

    try {
        $staffStmt = $pdo->prepare(
            'SELECT user_id
             FROM staff
             WHERE id = :id AND status <> \'ARCHIVED\'
             FOR UPDATE'
        );
        $staffStmt->execute([':id' => $id]);
        $staff = $staffStmt->fetch();

        if (!$staff) {
            $pdo->rollBack();
            apiError(404, 'Personnel introuvable');
        }

        $update = $pdo->prepare(
            'UPDATE staff
             SET first_name = :first_name,
                 last_name = :last_name,
                 function_name = :function_name,
                 class_name = :class_name,
                 phone = :phone,
                 email = :email,
                 updated_at = NOW()
             WHERE id = :id'
        );
        $update->execute([
            ':first_name' => $firstName,
            ':last_name' => $lastName,
            ':function_name' => $functionName,
            ':class_name' => $className,
            ':phone' => $phone,
            ':email' => $email,
            ':id' => $id,
        ]);

        $password = (string) ($body['password'] ?? '');
        $username = array_key_exists('username', $body)
            ? personnelText($body, 'username', 100)
            : null;

        if (($password !== '' || $username !== null) && strtolower((string) $actor['role_name']) !== 'pdg') {
            $pdo->rollBack();
            apiError(403, 'Seul le PDG peut modifier les accès');
        }

        if ($staff['user_id'] !== null && ($password !== '' || $username !== null)) {
            if ($password !== '' && (strlen($password) < 8 || strlen($password) > 255)) {
                $pdo->rollBack();
                apiError(400, 'Mot de passe invalide');
            }

            $sets = [];
            $params = [':id' => $staff['user_id']];

            if ($username !== null) {
                $sets[] = 'username = :username';
                $params[':username'] = $username;
            }
            if ($password !== '') {
                $sets[] = 'password_hash = :password_hash';
                $params[':password_hash'] = password_hash($password, PASSWORD_DEFAULT);
            }

            $userUpdate = $pdo->prepare(
                'UPDATE users SET ' . implode(', ', $sets) . ', updated_at = NOW() WHERE id = :id'
            );
            $userUpdate->execute($params);
        }

        $pdo->commit();
        personnelJson(['success' => true]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        if ($e->getCode() === '23505') {
            apiError(409, 'Identifiant ou adresse déjà utilisé');
        }
        throw $e;
    }
}

if ($method === 'DELETE') {
    requirePermission($pdo, 'personnel.delete');
    requireCsrfToken();

    $body = readJsonBody();
    $id = trim((string) ($body['id'] ?? ''));
    if ($id === '') {
        apiError(400, 'Identifiant personnel requis');
    }

    $pdo->beginTransaction();

    try {
        $stmt = $pdo->prepare(
            'SELECT user_id FROM staff WHERE id = :id AND status <> \'ARCHIVED\' FOR UPDATE'
        );
        $stmt->execute([':id' => $id]);
        $staff = $stmt->fetch();

        if (!$staff) {
            $pdo->rollBack();
            apiError(404, 'Personnel introuvable');
        }

        $archive = $pdo->prepare(
            'UPDATE staff SET status = \'ARCHIVED\', updated_at = NOW() WHERE id = :id'
        );
        $archive->execute([':id' => $id]);

        if ($staff['user_id'] !== null) {
            $disable = $pdo->prepare(
                'UPDATE users SET status = \'INACTIVE\', updated_at = NOW() WHERE id = :id'
            );
            $disable->execute([':id' => $staff['user_id']]);
        }

        $pdo->commit();
        personnelJson(['success' => true]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}

apiError(405, 'Méthode non autorisée');
