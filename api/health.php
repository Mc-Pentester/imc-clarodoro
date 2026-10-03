<?php
/**
 * IMC-Clarodoro - Health Check Endpoint
 * ARCH-01-PHP - Foundation
 * 
 * Permet de vérifier que PHP fonctionne.
 * Aucune authentification requise.
 * Aucune donnée métier.
 */

header('Content-Type: application/json; charset=utf-8');

echo json_encode([
    'success' => true,
    'service' => 'IMC-Clarodoro API',
    'status' => 'ok'
], JSON_PRETTY_PRINT);
