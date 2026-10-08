<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'];

function f02cAttendanceUuid(string $name): string
{
    $value = $_GET[$name] ?? '';
    if (!is_string($value) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)) {
        apiError(400, $name . ' UUID invalide');
    }
    return $value;
}

function f02cAttendanceScope(array $user, string $alias = 'e'): array
{
    if (in_array($user['role_name'], ['PDG', 'Directeur'], true)) {
        return ['', []];
    }

    return [
        ' INNER JOIN teacher_class_subjects scope_tcs
             ON scope_tcs.class_id = ' . $alias . '.class_id
            AND scope_tcs.status = \'ACTIVE\'
          INNER JOIN user_teachers scope_ut
             ON scope_ut.teacher_id = scope_tcs.teacher_id
            AND scope_ut.user_id = :scope_user_id',
        [':scope_user_id' => $user['id']],
    ];
}

if ($method === 'GET') {
    $user = requirePermission($pdo, 'presences.read');
    $conditions = [];
    $params = [];

    [$scopeSql, $scopeParams] = f02cAttendanceScope($user);
    $params += $scopeParams;

    if (isset($_GET['school_year_id'])) {
        $id = f02cAttendanceUuid('school_year_id');
        $conditions[] = 'e.school_year_id = :school_year_id';
        $params[':school_year_id'] = $id;
    }
    if (isset($_GET['enrollment_id'])) {
        $id = f02cAttendanceUuid('enrollment_id');
        $conditions[] = 'a.enrollment_id = :enrollment_id';
        $params[':enrollment_id'] = $id;
    }
    if (isset($_GET['attendance_date'])) {
        $date = $_GET['attendance_date'];
        if (!is_string($date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
            apiError(400, 'attendance_date invalide');
        }
        $conditions[] = 'a.attendance_date = :attendance_date';
        $params[':attendance_date'] = $date;
    }

    $where = $conditions ? ' WHERE ' . implode(' AND ', $conditions) : '';

    $stmt = $pdo->prepare(
        'SELECT
            a.id,
            a.enrollment_id,
            e.student_id,
            e.class_id,
            e.school_year_id,
            a.attendance_date,
            a.status,
            a.comment,
            a.created_at,
            a.updated_at
         FROM attendance a
         INNER JOIN enrollments e ON e.id = a.enrollment_id
         ' . $scopeSql . $where . '
         ORDER BY a.attendance_date DESC, a.id DESC'
    );
    $stmt->execute($params);
    $attendance = $stmt->fetchAll();

    $enrollmentStmt = $pdo->prepare(
        'SELECT
            e.id AS enrollment_id,
            e.student_id,
            e.class_id,
            e.school_year_id,
            s.last_name,
            s.first_name,
            s.sex,
            c.code AS class_code,
            c.name AS class_name,
            sy.label AS school_year_label
         FROM enrollments e
         INNER JOIN students s ON s.id = e.student_id
         INNER JOIN classes c ON c.id = e.class_id
         INNER JOIN school_years sy ON sy.id = e.school_year_id
         ' . $scopeSql . '
         WHERE e.status = 'ACTIVE'
           AND s.status = 'ACTIVE'
           AND c.status = 'ACTIVE'
         ORDER BY sy.start_date DESC, c.name ASC, s.last_name ASC, s.first_name ASC'
    );
    $enrollmentStmt->execute($scopeParams);
    $enrollments = $enrollmentStmt->fetchAll();

    echo json_encode([
        'success' => true,
        'attendance' => $attendance,
        'enrollments' => $enrollments,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if (!in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'], true)) {
    header('Allow: GET, POST, PUT, PATCH, DELETE');
    apiError(405, 'Méthode HTTP non autorisée');
}

$user = requirePermission($pdo, $method === 'POST' ? 'presences.create' : 'presences.update');

if ($method === 'DELETE') {
    requireCsrfToken();

    $id = f02cAttendanceUuid('id');
    $enrollmentId = f02cAttendanceUuid('enrollment_id');

    [$scopeSql, $scopeParams] = f02cAttendanceScope($user);
    $check = $pdo->prepare(
        'SELECT a.id
         FROM attendance a
         INNER JOIN enrollments e ON e.id = a.enrollment_id
         ' . $scopeSql . '
         WHERE a.id = :id
           AND a.enrollment_id = :enrollment_id
           AND e.status = 'ACTIVE'
         LIMIT 1'
    );
    $check->execute([
        ':id' => $id,
        ':enrollment_id' => $enrollmentId,
    ] + $scopeParams);

    if (!$check->fetch()) {
        apiError(404, 'Présence introuvable ou hors périmètre');
    }

    $stmt = $pdo->prepare(
        'DELETE FROM attendance
         WHERE id = :id
           AND enrollment_id = :enrollment_id'
    );
    $stmt->execute([
        ':id' => $id,
        ':enrollment_id' => $enrollmentId,
    ]);

    echo json_encode([
        'success' => true,
        'deleted' => true,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}
requireCsrfToken();
$data = readJsonBody();

foreach (array_keys($data) as $field) {
    if (!in_array($field, ['enrollment_id', 'attendance_date', 'status', 'comment'], true)) {
        apiError(422, 'Champ inconnu: ' . $field);
    }
}
foreach (['id', 'student_id', 'class_id', 'school_year_id', 'created_at', 'updated_at'] as $field) {
    if (array_key_exists($field, $data)) {
        apiError(422, 'Le champ ' . $field . ' est calculé par le serveur');
    }
}

$enrollmentId = $data['enrollment_id'] ?? '';
$date = $data['attendance_date'] ?? date('Y-m-d');
$status = $data['status'] ?? '';
$comment = $data['comment'] ?? null;

if (!is_string($enrollmentId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $enrollmentId)) {
    apiError(422, 'enrollment_id UUID invalide');
}
if (!is_string($date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
    apiError(422, 'attendance_date invalide');
}
if (!is_string($status) || !in_array($status, ['PRESENT', 'ABSENT', 'LATE', 'EXCUSED'], true)) {
    apiError(422, 'status invalide');
}
if ($comment !== null && !is_string($comment)) {
    apiError(422, 'comment invalide');
}

[$scopeSql, $scopeParams] = f02cAttendanceScope($user);
$check = $pdo->prepare(
    'SELECT e.id
     FROM enrollments e
     ' . $scopeSql . '
     WHERE e.id = :enrollment_id
       AND e.status = \'ACTIVE\'
     LIMIT 1'
);
$check->execute([':enrollment_id' => $enrollmentId] + $scopeParams);

if (!$check->fetch()) {
    apiError(404, 'Inscription hors périmètre');
}

try {
    if ($method === 'POST') {
        $stmt = $pdo->prepare(
            'INSERT INTO attendance (
                enrollment_id, attendance_date, status, comment
             )
             VALUES (:enrollment_id, :attendance_date, :status, :comment)
             RETURNING id, enrollment_id, attendance_date,
                       status, comment, created_at, updated_at'
        );
        $stmt->execute([
            ':enrollment_id' => $enrollmentId,
            ':attendance_date' => $date,
            ':status' => $status,
            ':comment' => $comment,
        ]);
        http_response_code(201);
    } else {
        $id = f02cAttendanceUuid('id');
        $stmt = $pdo->prepare(
            'UPDATE attendance a
             SET status = :status,
                 comment = :comment,
                 updated_at = NOW()
             WHERE a.id = :id
               AND a.enrollment_id = :enrollment_id
             RETURNING a.id, a.enrollment_id, a.attendance_date,
                       a.status, a.comment, a.created_at, a.updated_at'
        );
        $stmt->execute([
            ':id' => $id,
            ':enrollment_id' => $enrollmentId,
            ':status' => $status,
            ':comment' => $comment,
        ]);
    }

    $row = $stmt->fetch();
    if (!$row) {
        apiError(404, 'Présence introuvable ou hors périmètre');
    }

    echo json_encode([
        'success' => true,
        'attendance' => $row,
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    if (str_contains($e->getMessage(), 'attendance_unique')) {
        apiError(409, 'Une présence existe déjà pour cette inscription et cette date');
    }
    apiError(500, 'Erreur interne du serveur');
}
