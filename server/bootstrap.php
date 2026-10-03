<?php
/**
 * IMC-Clarodoro - Bootstrap
 * ARCH-01-PHP - Foundation
 * 
 * Bootstrap commun aux futures routes PHP.
 * Charge la configuration et les helpers nécessaires.
 * 
 * Ne pas initialiser de session utilisateur à cette étape.
 * Ne pas authentifier l'utilisateur.
 * Ne pas initialiser le RBAC.
 * Ne pas charger les données métier.
 */

// Définir le fuseau horaire par défaut
date_default_timezone_set('UTC');

// Charger les helpers
require_once __DIR__ . '/../middleware/response.php';
require_once __DIR__ . '/../middleware/request.php';

// Charger la configuration de base de données
require_once __DIR__ . '/../config/database.php';

// Constantes utiles
define('APP_VERSION', '1.0.0');
define('API_VERSION', 'v1');
