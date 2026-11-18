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

$purpose = $_GET['purpose'] ?? '';
$query = trim((string) ($_GET['q'] ?? ''));
if (!is_string($purpose) || !in_array($purpose, ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'], true)) {
    apiError(422, 'Finalité WhatsApp invalide');
}
if (strlen($query) < 2 || strlen($query) > 100) {
    apiError(422, 'Saisissez au moins 2 caractères pour rechercher un parent');
}

$digits = preg_replace('/\D+/', '', $query) ?? '';
$phoneSearch = '%' . $digits . '%';
$nameSearch = '%' . $query . '%';

try {
    // Only return recipients with active consent for the selected purpose.
    // Phone matching uses digits only so spaces, + and punctuation do not matter.
    $stmt = $pdo->prepare(
        "SELECT p.id, p.first_name, p.last_name, c.phone_e164,
                COALESCE(
                    string_agg(
                        DISTINCT concat_ws(' ', s.first_name, s.last_name),
                        ', ' ORDER BY concat_ws(' ', s.first_name, s.last_name)
                    ),
                    ''
                ) AS student_names
         FROM parents p
         INNER JOIN whatsapp_consents c
           ON c.parent_id = p.id
          AND c.purpose = :purpose
          AND c.status = 'OPTED_IN'
         LEFT JOIN student_parents sp ON sp.parent_id = p.id
         LEFT JOIN students s ON s.id = sp.student_id
         WHERE
           p.first_name ILIKE :first_name_search
           OR p.last_name ILIKE :last_name_search
           OR (p.first_name || ' ' || p.last_name) ILIKE :full_name_search
           OR s.first_name ILIKE :student_first_name_search
           OR s.last_name ILIKE :student_last_name_search
           OR (s.first_name || ' ' || s.last_name) ILIKE :student_full_name_search
           OR (:parent_digits <> '' AND regexp_replace(COALESCE(p.phone, ''), '[^0-9]', '', 'g') LIKE :parent_phone_search)
           OR (:consent_digits <> '' AND regexp_replace(c.phone_e164, '[^0-9]', '', 'g') LIKE :consent_phone_search)
         GROUP BY p.id, p.first_name, p.last_name, c.phone_e164
         ORDER BY p.last_name, p.first_name
         LIMIT 20"
    );
    $stmt->execute([
        ':purpose' => $purpose,
        ':first_name_search' => $nameSearch,
        ':last_name_search' => $nameSearch,
        ':full_name_search' => $nameSearch,
        ':student_first_name_search' => $nameSearch,
        ':student_last_name_search' => $nameSearch,
        ':student_full_name_search' => $nameSearch,
        ':parent_digits' => $digits,
        ':consent_digits' => $digits,
        ':parent_phone_search' => $phoneSearch,
        ':consent_phone_search' => $phoneSearch,
    ]);
    $parents = array_map(static function (array $row): array {
        return [
            'id' => (string) $row['id'],
            'first_name' => (string) $row['first_name'],
            'last_name' => (string) $row['last_name'],
            'phone_e164' => (string) $row['phone_e164'],
            'student_names' => (string) ($row['student_names'] ?? ''),
        ];
    }, $stmt->fetchAll());

    echo json_encode(['success' => true, 'parents' => $parents], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
} catch (Throwable $e) {
    error_log('WhatsApp parent search failed: ' . $e->getMessage());
    apiError(503, 'Recherche des parents temporairement indisponible');
}
