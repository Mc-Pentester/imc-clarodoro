<?php
/**
 * IMC-Clarodoro - Database Health Check Endpoint
 * ARCH-01-PHP - Foundation
 * 
 * Test uniquement la possibilité de connexion à PostgreSQL.
 * Aucune authentification requise.
 * Aucune donnée métier.
 * Aucune écriture.
 */

require_once __DIR__ . '/../config/database.php';

header('Content-Type: application/json; charset=utf-8');

try {
    $pdo = getDatabaseConnection();
    
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
