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
$classId = trim((string) ($_GET['class_id'] ?? ''));
$schoolYearId = trim((string) ($_GET['school_year_id'] ?? ''));
$purpose = $_GET['purpose'] ?? '';

if ($classId === '' && $schoolYearId === '') {
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

if (!preg_match($uuidPattern, $classId) || !preg_match($uuidPattern, $schoolYearId)) {
    apiError(422, 'Sélectionnez une classe et une année scolaire valides.');
}
if (!is_string($purpose) || !in_array($purpose, ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'], true)) {
    apiError(422, 'Finalité WhatsApp invalide.');
}

try {
    $classCheck = $pdo->prepare(
        "SELECT 1 FROM classes WHERE id = :class_id AND status = 'ACTIVE'"
    );
    $classCheck->execute([':class_id' => $classId]);
    if (!$classCheck->fetchColumn()) {
        apiError(404, 'Classe active introuvable.');
    }

    $yearCheck = $pdo->prepare(
        "SELECT 1 FROM school_years WHERE id = :school_year_id AND status = 'ACTIVE'"
    );
    $yearCheck->execute([':school_year_id' => $schoolYearId]);
    if (!$yearCheck->fetchColumn()) {
        apiError(404, 'Année scolaire active introuvable.');
    }

    // One row per parent/consent, even when several siblings are enrolled
    // in the same class. Only an active, purpose-specific opt-in is eligible.
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
            count(DISTINCT s.id)::integer AS student_count
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
         WHERE e.class_id = :class_id
           AND e.school_year_id = :school_year_id
           AND e.status = 'ACTIVE'
         GROUP BY p.id, p.first_name, p.last_name, c.id, c.phone_e164
         ORDER BY p.last_name, p.first_name, p.id"
    );
    $stmt->execute([
        ':purpose' => $purpose,
        ':class_id' => $classId,
        ':school_year_id' => $schoolYearId,
    ]);

    $parents = array_map(static function (array $row): array {
        return [
            'parent_id' => (string) $row['parent_id'],
            'first_name' => (string) $row['first_name'],
            'last_name' => (string) $row['last_name'],
            'phone_e164' => (string) $row['phone_e164'],
            'student_names' => (string) ($row['student_names'] ?? ''),
            'student_count' => (int) $row['student_count'],
        ];
    }, $stmt->fetchAll());

    echo json_encode([
        'success' => true,
        'class_id' => $classId,
        'school_year_id' => $schoolYearId,
        'purpose' => $purpose,
        'parents' => $parents,
        'count' => count($parents),
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
} catch (Throwable $e) {
    error_log('WhatsApp class recipients lookup failed: ' . $e->getMessage());
    apiError(503, 'Impossible de charger les parents autorisés de cette classe.');
}
