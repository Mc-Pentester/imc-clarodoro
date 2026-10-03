<?php
/**
 * IMC-Clarodoro - Request Helper
 * ARCH-01-PHP - Foundation
 * 
 * Helper minimal pour la gestion des requêtes.
 * Aucune logique métier.
 * Aucun mass assignment.
 */

/**
 * Récupère la méthode HTTP
 * 
 * @return string
 */
function getRequestMethod() {
    return $_SERVER['REQUEST_METHOD'] ?? 'GET';
}

/**
 * Récupère le body JSON de la requête
 * 
 * @return mixed|null Retourne null si le body est vide ou invalide
 */
function getJsonBody() {
    $contentType = $_SERVER['CONTENT_TYPE'] ?? '';
    
    // Vérifier si le Content-Type est JSON
    if (strpos($contentType, 'application/json') === false) {
        return null;
    }
    
    $rawBody = file_get_contents('php://input');
    
    // Body vide
    if (empty($rawBody)) {
        return null;
    }
    
    // Parser le JSON
    $data = json_decode($rawBody, true);
    
    // JSON invalide
    if (json_last_error() !== JSON_ERROR_NONE) {
        return null;
    }
    
    return $data;
}

/**
 * Vérifie si la requête est de type JSON
 * 
 * @return bool
 */
function isJsonRequest() {
    $contentType = $_SERVER['CONTENT_TYPE'] ?? '';
    return strpos($contentType, 'application/json') !== false;
}
