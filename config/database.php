<?php
/**
 * IMC-Clarodoro - Database Configuration
 * ARCH-01-PHP - Foundation
 * 
 * Ce fichier configure la connexion PDO PostgreSQL.
 * Aucune donnée sensible en dur.
 * La configuration provient des variables d'environnement.
 */

function getDatabaseConnection() {
    // Récupération des variables d'environnement avec valeurs par défaut
    $host = getenv('DB_HOST') ?: '127.0.0.1';
    $port = getenv('DB_PORT') ?: '5432';
    $dbname = getenv('DB_NAME') ?: 'imc_clarodoro';
    $user = getenv('DB_USER') ?: 'postgres';
    $password = getenv('DB_PASSWORD') ?: '';

    // Construction du DSN PostgreSQL
    $dsn = "pgsql:host={$host};port={$port};dbname={$dbname}";

    try {
        $pdo = new PDO($dsn, $user, $password, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);

        // Configuration UTF-8
        $pdo->exec("SET NAMES 'UTF8'");

        return $pdo;
    } catch (PDOException $e) {
        // Ne jamais exposer le mot de passe ou les détails internes
        throw new RuntimeException(
            'Impossible de se connecter à la base de données',
            0,
            $e
        );
    }
}
