<?php
declare(strict_types=1);

/**
 * IMC-Clarodoro - Database Configuration
 * F-08-C - Fail closed on missing/invalid database configuration.
 *
 * La configuration provient exclusivement des variables d'environnement
 * (ou du chargeur local config/env.php). Aucun secret ni fallback implicite.
 */

require_once __DIR__ . '/env.php';

function getRequiredEnvironmentVariable(string $name): string
{
    $value = getenv($name);

    if ($value === false || trim((string) $value) === '') {
        throw new RuntimeException(
            'Configuration de base de données manquante: ' . $name
        );
    }

    return (string) $value;
}

function getDatabaseConnection(): PDO
{
    $host = getRequiredEnvironmentVariable('DB_HOST');
    $port = getRequiredEnvironmentVariable('DB_PORT');
    $dbname = getRequiredEnvironmentVariable('DB_NAME');
    $user = getRequiredEnvironmentVariable('DB_USER');
    $password = getRequiredEnvironmentVariable('DB_PASSWORD');

    if (!ctype_digit($port) || (int) $port < 1 || (int) $port > 65535) {
        throw new RuntimeException(
            'Configuration de base de données invalide: DB_PORT'
        );
    }

    $dsn = "pgsql:host={$host};port={$port};dbname={$dbname}";

    try {
        $pdo = new PDO($dsn, $user, $password, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);

        $pdo->exec("SET NAMES 'UTF8'");

        return $pdo;
    } catch (PDOException $e) {
        throw new RuntimeException(
            'Impossible de se connecter à la base de données',
            0,
            $e
        );
    }
}
