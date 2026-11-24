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
$studentId = trim((string) ($_GET['student_id'] ?? ''));
$purpose = $_GET['purpose'] ?? '';

if (!preg_match($uuidPattern, $studentId)) {
    apiError(422, 'Identifiant élève invalide.');
}
if (!is_string($purpose) || !in_array($purpose, ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'], true)) {
    apiError(422, 'Finalité WhatsApp invalide.');
}

try {
    $studentStmt = $pdo->prepare(
        "SELECT id, first_name, last_name, matricule
         FROM students
         WHERE id = :student_id AND status = 'ACTIVE'
         LIMIT 1"
    );
    $studentStmt->execute([':student_id' => $studentId]);
    $student = $studentStmt->fetch(PDO::FETCH_ASSOC);
    if (!$student) {
        apiError(404, 'Élève actif introuvable.');
    }

    $stmt = $pdo->prepare(
        "SELECT
            p.id AS parent_id,
            p.first_name,
            p.last_name,
            sp.relationship_type,
            sp.is_primary,
            c.phone_e164,
            c.status AS consent_status,
            CASE
                WHEN c.status = 'OPTED_IN'
                 AND c.phone_e164 ~ '^[+][1-9][0-9]{7,14}$'
                THEN TRUE ELSE FALSE
            END AS eligible
         FROM student_parents sp
         INNER JOIN parents p ON p.id = sp.parent_id
         LEFT JOIN whatsapp_consents c
           ON c.parent_id = p.id
          AND c.purpose = :purpose
         WHERE sp.student_id = :student_id
         ORDER BY sp.is_primary DESC, p.last_name, p.first_name, p.id"
    );
    $stmt->execute([':purpose' => $purpose, ':student_id' => $studentId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $parents = array_map(static function (array $row): array {
        $eligible = in_array($row['eligible'], [true, 1, '1', 't', 'true'], true);
        return [
            'parent_id' => (string) $row['parent_id'],
            'first_name' => (string) $row['first_name'],
            'last_name' => (string) $row['last_name'],
            'relationship_type' => (string) $row['relationship_type'],
            'is_primary' => in_array($row['is_primary'], [true, 1, '1', 't', 'true'], true),
            'phone_e164' => $eligible ? (string) $row['phone_e164'] : null,
            'consent_status' => (string) ($row['consent_status'] ?? 'NOT_RECORDED'),
            'eligible' => $eligible,
        ];
    }, $rows);

    $eligibleCount = count(array_filter($parents, static fn(array $parent): bool => $parent['eligible']));
    echo json_encode([
        'success' => true,
        'student' => [
            'id' => (string) $student['id'],
            'first_name' => (string) $student['first_name'],
            'last_name' => (string) $student['last_name'],
            'matricule' => (string) ($student['matricule'] ?? ''),
        ],
        'parents' => $parents,
        'total_linked_parents' => count($parents),
        'eligible_parent_count' => $eligibleCount,
        'excluded_without_active_consent' => count($parents) - $eligibleCount,
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
} catch (Throwable $e) {
    error_log('WhatsApp student recipients lookup failed: ' . $e->getMessage());
    apiError(503, 'Impossible de charger les responsables de cet élève.');
}

                THEN TRUE ELSE FALSE
            END AS eligible
         FROM student_parents sp
         INNER JOIN parents p ON p.id = sp.parent_id
         LEFT JOIN whatsapp_consents c
           ON c.parent_id = p.id
          AND c.purpose = :purpose
         WHERE sp.student_id = :student_id
         ORDER BY sp.is_primary DESC, p.last_name, p.first_name, p.id"
    );
    $stmt->execute([':purpose' => $purpose, ':student_id' => $studentId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $parents = array_map(static function (array $row): array {
        $eligible = in_array($row['eligible'], [true, 1, '1', 't', 'true'], true);
        return [
            'parent_id' => (string) $row['parent_id'],
            'first_name' => (string) $row['first_name'],
            'last_name' => (string) $row['last_name'],
            'relationship_type' => (string) $row['relationship_type'],
            'is_primary' => in_array($row['is_primary'], [true, 1, '1', 't', 'true'], true),
            'phone_e164' => $eligible ? (string) $row['phone_e164'] : null,
            'consent_status' => (string) ($row['consent_status'] ?? 'NOT_RECORDED'),
            'eligible' => $eligible,
        ];
    }, $rows);

    $eligibleCount = count(array_filter($parents, static fn(array $parent): bool => $parent['eligible']));
    echo json_encode([
        'success' => true,
        'student' => [
            'id' => (string) $student['id'],
            'first_name' => (string) $student['first_name'],
            'last_name' => (string) $student['last_name'],
            'matricule' => (string) ($student['matricule'] ?? ''),
        ],
        'parents' => $parents,
        'total_linked_parents' => count($parents),
        'eligible_parent_count' => $eligibleCount,
        'excluded_without_active_consent' => count($parents) - $eligibleCount,
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
} catch (Throwable $e) {
    error_log('WhatsApp student recipients lookup failed: ' . $e->getMessage());
    apiError(503, 'Impossible de charger les responsables de cet élève.');
}
