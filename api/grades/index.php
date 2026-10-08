<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'];

function f02cUuid(string $name): string
{
    $value = $_GET[$name] ?? '';
    if (!is_string($value) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)) {
        apiError(400, $name . ' UUID invalide');
    }
    return $value;
}

function f02cScope(array $user, string $alias = 'e', ?string $subjectAlias = 's'): array
{
    if (in_array($user['role_name'], ['PDG', 'Directeur'], true)) {
        return ['', []];
    }

    $subjectJoin = $subjectAlias === null
        ? ''
        : ' AND scope_tcs.subject_id = ' . $subjectAlias . '.id';

    return [
        ' INNER JOIN teacher_class_subjects scope_tcs
             ON scope_tcs.class_id = ' . $alias . '.class_id
            ' . $subjectJoin . '
            AND scope_tcs.status = :scope_assignment_status
          INNER JOIN user_teachers scope_ut
             ON scope_ut.teacher_id = scope_tcs.teacher_id
            AND scope_ut.user_id = :scope_user_id',
        [
            ':scope_assignment_status' => 'ACTIVE',
            ':scope_user_id' => $user['id'],
        ],
    ];
}

if ($method === 'GET') {
    $user = requirePermission($pdo, 'resultats.read');

    $conditions = [];
    $params = [];
    [$scopeSql, $scopeParams] = f02cScope($user);
    $params += $scopeParams;

    if (isset($_GET['school_year_id'])) {
        $id = f02cUuid('school_year_id');
        $conditions[] = 'e.school_year_id = :school_year_id';
        $params[':school_year_id'] = $id;
    }

    if (isset($_GET['enrollment_id'])) {
        $id = f02cUuid('enrollment_id');
        $conditions[] = 'g.enrollment_id = :enrollment_id';
        $params[':enrollment_id'] = $id;
    }

    if (isset($_GET['student_id'])) {
        $id = f02cUuid('student_id');
        $conditions[] = 'e.student_id = :student_id';
        $params[':student_id'] = $id;
    }

    $where = $conditions ? ' WHERE ' . implode(' AND ', $conditions) : '';

    $stmt = $pdo->prepare(
        'SELECT
            g.id,
            g.enrollment_id,
            e.student_id,
            e.class_id,
            e.school_year_id,
            g.subject_id,
            s.code AS subject_code,
            s.name AS subject_name,
            s.coefficient,
            s.max_points,
            g.assessment_number,
            g.grade,
            g.grade_date,
            g.created_at,
            g.updated_at
         FROM grades g
         INNER JOIN enrollments e ON e.id = g.enrollment_id
         INNER JOIN subjects s ON s.id = g.subject_id
         ' . $scopeSql . $where . '
         ORDER BY e.student_id, g.grade_date, s.name, g.id'
    );
    $stmt->execute($params);
    $grades = $stmt->fetchAll();

    $enrollmentConditions = ['e.status = :enrollment_status'];
    $enrollmentParams = f02cScope($user, 'e', null)[1];
    $enrollmentParams[':enrollment_status'] = 'ACTIVE';
    if (isset($_GET['school_year_id'])) {
        $enrollmentConditions[] = 'e.school_year_id = :enrollment_school_year_id';
        $enrollmentParams[':enrollment_school_year_id'] = $_GET['school_year_id'];
    }

    $enrollmentStmt = $pdo->prepare(
        'SELECT
            e.id AS enrollment_id,
            e.student_id,
            e.class_id,
            c.name AS class_name,
            e.school_year_id,
            sy.label AS school_year_label,
            s.last_name,
            s.first_name,
            s.matricule
         FROM enrollments e
         INNER JOIN students s ON s.id = e.student_id
         INNER JOIN classes c ON c.id = e.class_id
         INNER JOIN school_years sy ON sy.id = e.school_year_id
         ' . f02cScope($user, 'e', null)[0] . '
         WHERE ' . implode(' AND ', $enrollmentConditions) . '
         ORDER BY s.last_name, s.first_name, e.id'
    );
    $enrollmentStmt->execute($enrollmentParams);

    $subjectStmt = $pdo->query(
        "SELECT id, code, name, coefficient, max_points
         FROM subjects
         WHERE status = 'ACTIVE'
         ORDER BY name ASC, id ASC"
    );

    echo json_encode([
        'success' => true,
        'grades' => $grades,
        'enrollments' => $enrollmentStmt->fetchAll(),
        'subjects' => $subjectStmt->fetchAll(),
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if (!in_array($method, ['POST', 'PUT', 'PATCH'], true)) {
    header('Allow: GET, POST, PUT, PATCH');
    apiError(405, 'Méthode HTTP non autorisée');
}

$user = requirePermission($pdo, $method === 'POST' ? 'resultats.create' : 'resultats.update');
requireCsrfToken();
$data = readJsonBody();

foreach (array_keys($data) as $field) {
    if (!in_array($field, ['enrollment_id', 'subject_id', 'grade', 'grade_date', 'assessment_number'], true)) {
        apiError(422, 'Champ inconnu: ' . $field);
    }
}

foreach (['id', 'student_id', 'class_id', 'school_year_id', 'created_at', 'updated_at'] as $field) {
    if (array_key_exists($field, $data)) {
        apiError(422, 'Le champ ' . $field . ' est calculé par le serveur');
    }
}

$enrollmentId = $data['enrollment_id'] ?? '';
$subjectId = $data['subject_id'] ?? '';

if (!is_string($enrollmentId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $enrollmentId)) {
    apiError(422, 'enrollment_id UUID invalide');
}
if (!is_string($subjectId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $subjectId)) {
    apiError(422, 'subject_id UUID invalide');
}
if (!isset($data['grade']) || !is_numeric($data['grade'])) {
    apiError(422, 'grade est requis et doit être numérique');
}

$grade = (float) $data['grade'];
if (!is_finite($grade) || $grade < 0 || $grade > 100) {
    apiError(422, 'grade doit être compris entre 0 et 100');
}

$assessmentNumber = $data['assessment_number'] ?? 1;
if (!is_int($assessmentNumber) && !(is_string($assessmentNumber) && ctype_digit($assessmentNumber))) {
    apiError(422, 'assessment_number invalide');
}
$assessmentNumber = (int) $assessmentNumber;
if ($assessmentNumber < 1 || $assessmentNumber > 3) {
    apiError(422, 'assessment_number doit être compris entre 1 et 3');
}

$gradeDate = $data['grade_date'] ?? date('Y-m-d');
if (!is_string($gradeDate) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $gradeDate)) {
    apiError(422, 'grade_date invalide');
}

[$scopeSql, $scopeParams] = f02cScope($user, 'e', 's');

$check = $pdo->prepare(
    'SELECT e.id
     FROM enrollments e
     INNER JOIN subjects s
        ON s.id = :subject_id
       AND s.status = \'ACTIVE\'
     ' . $scopeSql . '
     WHERE e.id = :enrollment_id
       AND e.status = \'ACTIVE\'
     LIMIT 1'
);

$check->execute(
    [
        ':subject_id' => $subjectId,
        ':enrollment_id' => $enrollmentId,
    ] + $scopeParams
);

if (!$check->fetch()) {
    apiError(404, 'Inscription ou matière hors périmètre');
}

try {
    if ($method === 'POST') {
        $stmt = $pdo->prepare(
            'INSERT INTO grades (enrollment_id, subject_id, grade, grade_date, assessment_number)
             VALUES (:enrollment_id, :subject_id, :grade, :grade_date, :assessment_number)
             RETURNING id, enrollment_id, subject_id, assessment_number, grade, grade_date, created_at, updated_at'
        );
        $stmt->execute([
            ':enrollment_id' => $enrollmentId,
            ':subject_id' => $subjectId,
            ':grade' => $grade,
            ':grade_date' => $gradeDate,
            ':assessment_number' => $assessmentNumber,
        ]);
        http_response_code(201);
    } else {
        $id = f02cUuid('id');
        $stmt = $pdo->prepare(
            'UPDATE grades g
             SET grade = :grade,
                 grade_date = :grade_date,
                 assessment_number = :assessment_number,
                 updated_at = NOW()
             WHERE g.id = :id
               AND g.enrollment_id = :enrollment_id
               AND g.subject_id = :subject_id
             RETURNING g.id, g.enrollment_id, g.subject_id,
                       g.assessment_number, g.grade, g.grade_date, g.created_at, g.updated_at'
        );
        $stmt->execute([
            ':id' => $id,
            ':enrollment_id' => $enrollmentId,
            ':subject_id' => $subjectId,
            ':grade' => $grade,
            ':grade_date' => $gradeDate,
            ':assessment_number' => $assessmentNumber,
        ]);
    }

    $row = $stmt->fetch();
    if (!$row) {
        apiError(404, 'Résultat introuvable ou hors périmètre');
    }

    echo json_encode([
        'success' => true,
        'grade' => $row,
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    if ($e->getCode() === '23505') {
        apiError(409, 'Résultat déjà enregistré pour cette matière et ce contrôle');
    }
    apiError(500, 'Erreur interne du serveur');
}
