<?php
/**
 * IMC-Clarodoro - Database Health Check Endpoint
 * F-08-A - Diagnostic endpoint requires authentication.
 *
 * Test uniquement la possibilité de connexion à PostgreSQL.
 * Aucune donnée métier.
 * Aucune écriture.
 */

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

try {
    $pdo = getDatabaseConnection();
    requireAuthenticatedUser($pdo);

    // Requête minimale non destructive
    $stmt = $pdo->query('SELECT 1');
    $result = $stmt->fetch();

    if ($result) {
        echo json_encode([
            'success' => true,
            'service' => 'IMC-Clarodoro API',
            'database' => 'connected'
        ], JSON_PRETTY_PRINT);
    } else {
        echo json_encode([
            'success' => false,
            'service' => 'IMC-Clarodoro API',
            'database' => 'unavailable'
        ], JSON_PRETTY_PRINT);
    }
} catch (Exception $e) {
    // Ne jamais exposer de détails sensibles
    echo json_encode([
        'success' => false,
        'service' => 'IMC-Clarodoro API',
        'database' => 'unavailable'
    ], JSON_PRETTY_PRINT);
}
