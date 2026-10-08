<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'];

function f02dUuid(string $name): string {
    $value = $_GET[$name] ?? '';
    if (!is_string($value) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)) {
        apiError(400, $name . ' UUID invalide');
    }
    return $value;
}

function f02dScope(array $user): array {
    if (in_array($user['role_name'], ['PDG', 'Directeur'], true)) {
        return ['', []];
    }
    return [
        ' INNER JOIN teacher_class_subjects tcs
             ON tcs.class_id = e.class_id
            AND tcs.status = :scope_assignment_status
          INNER JOIN user_teachers ut
             ON ut.teacher_id = tcs.teacher_id
            AND ut.user_id = :scope_user_id',
        [
            ':scope_assignment_status' => 'ACTIVE',
            ':scope_user_id' => $user['id'],
        ],
    ];
}

if ($method === 'GET') {
    $user = requirePermission($pdo, 'resultats.read');
    $enrollmentId = f02dUuid('enrollment_id');
    [$scopeSql, $scopeParams] = f02dScope($user);

    $stmt = $pdo->prepare(
        'SELECT
            rc.enrollment_id,
            rc.proprete,
            rc.conduite,
            rc.tenue_materiels,
            rc.retard,
            rc.absence,
            rc.classe_promotion,
            rc.classe_refait,
            rc.eleve_remis,
            rc.observation1,
            rc.observation2,
            rc.observation3,
            rc.created_at,
            rc.updated_at
         FROM result_carnets rc
         INNER JOIN enrollments e ON e.id = rc.enrollment_id
         ' . $scopeSql . '
         WHERE rc.enrollment_id = :enrollment_id
           AND e.status = \'ACTIVE\'
         LIMIT 1'
    );
    $stmt->execute([':enrollment_id' => $enrollmentId] + $scopeParams);
    $carnet = $stmt->fetch();

    echo json_encode([
        'success' => true,
        'carnet' => $carnet ?: null,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if (!in_array($method, ['PUT', 'PATCH'], true)) {
    header('Allow: GET, PUT, PATCH');
    apiError(405, 'Méthode HTTP non autorisée');
}

$user = requirePermission($pdo, 'resultats.update');
requireCsrfToken();
$data = readJsonBody();

$enrollmentId = $data['enrollment_id'] ?? '';
if (!is_string($enrollmentId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $enrollmentId)) {
    apiError(422, 'enrollment_id UUID invalide');
}

$allowed = [
    'enrollment_id','proprete','conduite','tenue_materiels','retard','absence',
    'classe_promotion','classe_refait','eleve_remis','observation1','observation2','observation3'
];
foreach (array_keys($data) as $field) {
    if (!in_array($field, $allowed, true)) {
        apiError(422, 'Champ inconnu: ' . $field);
    }
}

[$scopeSql, $scopeParams] = f02dScope($user);
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

$fields = [
    'proprete' => $data['proprete'] ?? null,
    'conduite' => $data['conduite'] ?? null,
    'tenue_materiels' => $data['tenue_materiels'] ?? null,
    'retard' => $data['retard'] ?? null,
    'absence' => $data['absence'] ?? null,
    'classe_promotion' => $data['classe_promotion'] ?? null,
    'classe_refait' => $data['classe_refait'] ?? null,
    'eleve_remis' => $data['eleve_remis'] ?? null,
    'observation1' => $data['observation1'] ?? null,
    'observation2' => $data['observation2'] ?? null,
    'observation3' => $data['observation3'] ?? null,
];

foreach ($fields as $key => $value) {
    if ($value !== null && !is_string($value)) {
        apiError(422, $key . ' doit être une chaîne ou null');
    }
    if (is_string($value) && strlen($value) > 5000) {
        apiError(422, $key . ' trop long');
    }
}

$stmt = $pdo->prepare(
    'INSERT INTO result_carnets (
        enrollment_id, proprete, conduite, tenue_materiels, retard, absence,
        classe_promotion, classe_refait, eleve_remis,
        observation1, observation2, observation3
     )
     VALUES (
        :enrollment_id, :proprete, :conduite, :tenue_materiels, :retard, :absence,
        :classe_promotion, :classe_refait, :eleve_remis,
        :observation1, :observation2, :observation3
     )
     ON CONFLICT (enrollment_id)
     DO UPDATE SET
        proprete = EXCLUDED.proprete,
        conduite = EXCLUDED.conduite,
        tenue_materiels = EXCLUDED.tenue_materiels,
        retard = EXCLUDED.retard,
        absence = EXCLUDED.absence,
        classe_promotion = EXCLUDED.classe_promotion,
        classe_refait = EXCLUDED.classe_refait,
        eleve_remis = EXCLUDED.eleve_remis,
        observation1 = EXCLUDED.observation1,
        observation2 = EXCLUDED.observation2,
        observation3 = EXCLUDED.observation3,
        updated_at = NOW()
     RETURNING *'
);
$stmt->execute([
    ':enrollment_id' => $enrollmentId,
    ':proprete' => $fields['proprete'],
    ':conduite' => $fields['conduite'],
    ':tenue_materiels' => $fields['tenue_materiels'],
    ':retard' => $fields['retard'],
    ':absence' => $fields['absence'],
    ':classe_promotion' => $fields['classe_promotion'],
    ':classe_refait' => $fields['classe_refait'],
    ':eleve_remis' => $fields['eleve_remis'],
    ':observation1' => $fields['observation1'],
    ':observation2' => $fields['observation2'],
    ':observation3' => $fields['observation3'],
]);

echo json_encode([
    'success' => true,
    'carnet' => $stmt->fetch(),
], JSON_UNESCAPED_UNICODE);
