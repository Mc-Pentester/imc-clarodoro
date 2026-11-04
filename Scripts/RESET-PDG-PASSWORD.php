<?php

declare(strict_types=1);

/**
 * Réinitialisation ciblée du mot de passe du compte PDG.
 *
 * Sur Windows (installation Clarodaro), lancer depuis n'importe quel dossier :
 *   powershell -NoProfile -ExecutionPolicy Bypass -File
 *     "C:\\Program Files\\IMC-Clarodaro\\Scripts\\RESET-PDG-PASSWORD.ps1"
 *
 * Le lanceur PowerShell utilise le PHP embarqué dans runtime\\php et charge
 * la configuration protégée de ProgramData. Aucun PATH PHP n'est nécessaire.
 *
 * Exécuter uniquement en CLI sur le serveur/local autorisé.
 * Ce script ne crée aucun compte et ne modifie ni rôles, ni permissions,
 * ni données métier. Le mot de passe n'est jamais affiché.
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require_once __DIR__ . '/../config/database.php';

$password = getenv('IMC_PDG_NEW_PASSWORD');

if (!is_string($password) || strlen($password) < 12) {
    fwrite(STDERR, "ERREUR: définissez IMC_PDG_NEW_PASSWORD (12 caractères minimum) dans la session CLI.\n");
    exit(1);
}

$hash = password_hash($password, PASSWORD_DEFAULT);
putenv('IMC_PDG_NEW_PASSWORD');

if (!is_string($hash) || $hash === '') {
    fwrite(STDERR, "ERREUR: impossible de générer le hash du mot de passe.\n");
    exit(1);
}

$pdo = getDatabaseConnection();
$pdo->beginTransaction();

try {
    $stmt = $pdo->prepare(
        "UPDATE users
         SET password_hash = :password_hash,
             updated_at = NOW()
         WHERE LOWER(username) = 'pdg'
           AND role_id = (
               SELECT id FROM roles WHERE UPPER(name) = 'PDG'
           )"
    );
    $stmt->execute([':password_hash' => $hash]);

    if ($stmt->rowCount() !== 1) {
        throw new RuntimeException(
            'Le compte PDG attendu est absent ou ambigu. Aucune modification validée.'
        );
    }

    $pdo->commit();
    echo "PASS: mot de passe du compte PDG réinitialisé. Le compte et les données sont conservés.\n";
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    fwrite(STDERR, "ÉCHEC: " . $e->getMessage() . "\n");
    exit(1);
}
