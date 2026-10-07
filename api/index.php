<?php

require_once __DIR__ . '/../middleware/security_headers.php';
sendApiSecurityHeaders();
/**
 * IMC-Clarodoro - API Index Endpoint
 * ARCH-01-PHP - Foundation
 * 
 * Point d'entrée informatif de l'API.
 * Aucune authentification requise.
 * Aucune donnée métier.
 */

header('Content-Type: application/json; charset=utf-8');

echo json_encode([
    'success' => true,
    'application' => 'IMC-Clarodoro',
    'api' => 'v1',
    'status' => 'ready'
], JSON_PRETTY_PRINT);
