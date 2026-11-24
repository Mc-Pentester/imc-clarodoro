<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    apiError(405, 'Méthode HTTP non autorisée');
}

$pdo = getDatabaseConnection();
requirePermission($pdo, 'whatsapp.message.send');

$uuidPattern = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';
$classIdsRaw = trim((string) ($_GET['class_ids'] ?? ''));
$legacyClassId = trim((string) ($_GET['class_id'] ?? ''));
$schoolYearId = trim((string) ($_GET['school_year_id'] ?? ''));
$purpose = $_GET['purpose'] ?? '';

if ($classIdsRaw === '' && $legacyClassId === '' && $schoolYearId === '') {
    $classes = $pdo->query(
        "SELECT id, code, name
         FROM classes
         WHERE status = 'ACTIVE'
         ORDER BY name, code, id"
    )->fetchAll();
    $schoolYears = $pdo->query(
        "SELECT id, label, start_date, end_date
         FROM school_years
         WHERE status = 'ACTIVE'
         ORDER BY start_date DESC, id DESC"
    )->fetchAll();

    echo json_encode([
        'success' => true,
        'classes' => $classes,
        'school_years' => $schoolYears,
        'parents' => [],
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    exit;
}

$classIds = $classIdsRaw !== ''
    ? array_values(array_unique(array_filter(array_map('trim', explode(',', $classIdsRaw)), static fn(string $id): bool => $id !== '')))
    : ($legacyClassId !== '' ? [$legacyClassId] : []);

if ($classIds === [] || count($classIds) > 20 || !preg_match($uuidPattern, $schoolYearId)) {
    apiError(422, 'Sélectionnez une à vingt classes et une année scolaire valides.');
}
foreach ($classIds as $classId) {
    if (!preg_match($uuidPattern, $classId)) {
        apiError(422, 'Identifiant de classe invalide.');
    }
}
if (!is_string($purpose) || !in_array($purpose, ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'], true)) {
    apiError(422, 'Finalité WhatsApp invalide.');
}

try {
    $classArray = '{' . implode(',', $classIds) . '}';
    $classCheck = $pdo->prepare(
        "SELECT id, name, code
         FROM classes
         WHERE id = ANY(CAST(:class_ids AS uuid[]))
           AND status = 'ACTIVE'
         ORDER BY name, code, id"
    );
    $classCheck->execute([':class_ids' => $classArray]);
    $classes = $classCheck->fetchAll(PDO::FETCH_ASSOC);
    if (count($classes) !== count($classIds)) {
        apiError(404, 'Une ou plusieurs classes sont introuvables ou inactives.');
    }

    $yearCheck = $pdo->prepare(
        "SELECT 1 FROM school_years WHERE id = :school_year_id AND status = 'ACTIVE'"
    );
    $yearCheck->execute([':school_year_id' => $schoolYearId]);
    if (!$yearCheck->fetchColumn()) {
        apiError(404, 'Année scolaire active introuvable.');
    }

    // One row per parent/consent across every selected class. A parent with
    // siblings in multiple selected classes is returned once.
    $stmt = $pdo->prepare(
        "SELECT
            p.id AS parent_id,
            p.first_name,
            p.last_name,
            c.phone_e164,
            string_agg(
                DISTINCT concat_ws(' ', s.first_name, s.last_name),
                ', ' ORDER BY concat_ws(' ', s.first_name, s.last_name)
            ) AS student_names,
            count(DISTINCT s.id)::integer AS student_count,
            string_agg(
                DISTINCT cl.name,
                ', ' ORDER BY cl.name
            ) AS class_names
         FROM enrollments e
         INNER JOIN students s ON s.id = e.student_id
         INNER JOIN classes cl ON cl.id = e.class_id AND cl.status = 'ACTIVE'
         INNER JOIN school_years sy ON sy.id = e.school_year_id AND sy.status = 'ACTIVE'
         INNER JOIN student_parents sp ON sp.student_id = s.id
         INNER JOIN parents p ON p.id = sp.parent_id
         INNER JOIN whatsapp_consents c
           ON c.parent_id = p.id
          AND c.purpose = :purpose
          AND c.status = 'OPTED_IN'
          AND left(c.phone_e164, 1) = '+'
          AND length(c.phone_e164) BETWEEN 9 AND 16
          AND substring(c.phone_e164 FROM 2) !~ '[^0-9]'
         WHERE e.class_id = ANY(CAST(:class_ids AS uuid[]))
           AND e.school_year_id = :school_year_id
           AND e.status = 'ACTIVE'
         GROUP BY p.id, p.first_name, p.last_name, c.id, c.phone_e164
         ORDER BY p.last_name, p.first_name, p.id"
    );
    $stmt->execute([
        ':purpose' => $purpose,
        ':class_ids' => $classArray,
        ':school_year_id' => $schoolYearId,
    ]);

    $totalStmt = $pdo->prepare(
        "SELECT count(DISTINCT sp.parent_id)
         FROM enrollments e
         INNER JOIN student_parents sp ON sp.student_id = e.student_id
         WHERE e.class_id = ANY(CAST(:class_ids AS uuid[]))
           AND e.school_year_id = :school_year_id
           AND e.status = 'ACTIVE'"
    );
    $totalStmt->execute([
        ':class_ids' => $classArray,
        ':school_year_id' => $schoolYearId,
    ]);
    $totalParentCount = (int) $totalStmt->fetchColumn();

    $parents = array_map(static function (array $row): array {
        return [
            'parent_id' => (string) $row['parent_id'],
            'first_name' => (string) $row['first_name'],
            'last_name' => (string) $row['last_name'],
            'phone_e164' => (string) $row['phone_e164'],
            'student_names' => (string) ($row['student_names'] ?? ''),
            'student_count' => (int) $row['student_count'],
            'class_names' => (string) ($row['class_names'] ?? ''),
        ];
    }, $stmt->fetchAll());

    echo json_encode([
        'success' => true,
        'class_ids' => $classIds,
        'classes' => $classes,
        'school_year_id' => $schoolYearId,
        'purpose' => $purpose,
        'parents' => $parents,
        'count' => count($parents),
        'total_linked_parents' => $totalParentCount,
        'excluded_without_active_consent' => max(0, $totalParentCount - count($parents)),
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
} catch (Throwable $e) {
    error_log('WhatsApp class recipients lookup failed: ' . $e->getMessage());
    apiError(503, 'Impossible de charger les parents autorisés des classes sélectionnées.');
}
