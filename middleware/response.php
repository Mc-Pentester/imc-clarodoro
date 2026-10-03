<?php
/**
 * IMC-Clarodoro - Response Helper
 * ARCH-01-PHP - Foundation
 * 
 * Helper pour les réponses JSON.
 * Aucune logique d'authentification.
 * Aucune logique RBAC.
 */

/**
 * Envoie une réponse JSON
 * 
 * @param mixed $data Données à encoder
 * @param int $statusCode Code HTTP
 * @return void
 */
function jsonResponse($data, $statusCode = 200) {
    http_response_code($statusCode);
    header('Content-Type: application/json; charset=utf-8');
    
    echo json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    exit;
}
