<?php

declare(strict_types=1);

/*
 * P0-A.1 — Bootstrap d'administration.
 * Exécution strictement CLI : ce script ne doit jamais être utilisable
 * comme endpoint HTTP, même s'il se trouve accidentellement dans le
 * document root.
 */
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require_once __DIR__ . '/config/database.php';

$pdo = getDatabaseConnection();
$pdo->beginTransaction();

try {
    /*
     * Verrou transactionnel : empêche deux exécutions concurrentes du
     * bootstrap de passer simultanément le contrôle de première création.
     */
    $pdo->query("SELECT pg_advisory_xact_lock(hashtext('imc-clarodaro-bootstrap-auth-v1'))");

    // Valider le secret avant toute écriture dans les tables RBAC.
    $password = getenv('IMC_BOOTSTRAP_PASSWORD');

    $passwordCharacterCount = is_string($password)
        ? preg_match_all('/./us', $password, $passwordCharacters)
        : false;

    if (
        !is_string($password) ||
        $password === '' ||
        strlen($password) > 1024 ||
        $passwordCharacterCount === false ||
        $passwordCharacterCount < 12 ||
        preg_match('/[\x00-\x1F\x7F]/u', $password) === 1
    ) {
        throw new RuntimeException(
            'IMC_BOOTSTRAP_PASSWORD doit contenir au moins 12 caractères Unicode valides.'
        );
    }

    /*
     * Ce script est réservé à l'initialisation. Dès qu'un compte "pdg"
     * existe ou qu'un utilisateur possède le rôle PDG, on s'arrête sans
     * modifier utilisateurs, rôles, permissions ni associations.
     */
    $existingPdgStmt = $pdo->query(
        "SELECT 1
         FROM users u
         LEFT JOIN roles r ON r.id = u.role_id
         WHERE LOWER(u.username) = 'pdg'
            OR r.name = 'PDG'
         LIMIT 1"
    );

    if ($existingPdgStmt->fetchColumn() !== false) {
        throw new RuntimeException(
            'Initialisation refusée : un compte PDG existe déjà. '
            . 'Aucun compte, rôle ou droit existant n’a été modifié. '
            . 'Utilisez la procédure de récupération PDG si nécessaire.'
        );
    }
    $roles = [
        'PDG',
        'Directeur',
        'Enseignant',
        'Secrétaire',
        'Surveillant',
        'Autre',
    ];

    $roleStmt = $pdo->prepare(
        'INSERT INTO roles (name)
         VALUES (:name)
         ON CONFLICT (name) DO NOTHING'
    );

    foreach ($roles as $role) {
        $roleStmt->execute([':name' => $role]);
    }

    $permissions = [
        'personnel.read',
        'personnel.create',
        'personnel.update',
        'personnel.delete',
        'eleves.read',
        'eleves.create',
        'eleves.update',
        'eleves.delete',
        'annees.read',
        'annees.create',
        'annees.update',
        'annees.delete',
        'matieres.read',
        'matieres.create',
        'matieres.update',
        'matieres.delete',
        'resultats.read',
        'resultats.create',
        'resultats.update',
        'finances.read',
        'finances.create',
        'finances.update',
        'finances.delete',
        'vacances.read',
        'vacances.create',
        'vacances.update',
        'vacances.delete',
        'badge.read',
        'badge.create',
        'badge.print',
        'paies.read',
        'paies.create',
        'paies.update',
        'depenses.read',
        'depenses.create',
        'depenses.delete',
        'presences.read',
        'presences.create',
        'presences.update',
        'whatsapp.message.send',
        'whatsapp.consent.read',
        'vault.update',
    ];

    $permissionStmt = $pdo->prepare(
        'INSERT INTO permissions (name, description)
         VALUES (:name, :description)
         ON CONFLICT (name) DO NOTHING'
    );

    foreach ($permissions as $permission) {
        $permissionStmt->execute([
            ':name' => $permission,
            ':description' => $permission,
        ]);
    }

    $matrix = [
        'PDG' => $permissions,

        'Directeur' => [
            'personnel.read',
            'eleves.read',
            'eleves.create',
            'eleves.update',
            'annees.read',
            'matieres.read',
            'resultats.read',
            'resultats.create',
            'resultats.update',
            'finances.read',
            'vacances.read',
            'badge.read',
            'badge.print',
            'presences.read',
            'presences.create',
            'presences.update',
        ],

        'Enseignant' => [
            'eleves.read',
            'annees.read',
            'matieres.read',
            'resultats.read',
            'resultats.create',
            'resultats.update',
            'vacances.read',
            'presences.read',
            'presences.create',
            'presences.update',
        ],

        'Secrétaire' => [
            'personnel.read',
            'eleves.read',
            'eleves.create',
            'eleves.update',
            'annees.read',
            'matieres.read',
            'finances.read',
            'vacances.read',
            'badge.read',
            'badge.print',
        ],

        'Surveillant' => [
            'eleves.read',
            'annees.read',
            'matieres.read',
            'vacances.read',
            'presences.create',
        ],

        'Autre' => [
            'annees.read',
            'matieres.read',
            'vacances.read',
        ],
    ];

    $rolePermissionStmt = $pdo->prepare(
        'INSERT INTO role_permissions (role_id, permission_id)
         SELECT r.id, p.id
         FROM roles r
         CROSS JOIN permissions p
         WHERE r.name = :role
           AND p.name = :permission
         ON CONFLICT (role_id, permission_id) DO NOTHING'
    );

    foreach ($matrix as $role => $rolePermissions) {
        foreach ($rolePermissions as $permission) {
            $rolePermissionStmt->execute([
                ':role' => $role,
                ':permission' => $permission,
            ]);
        }
    }

    $passwordHash = password_hash($password, PASSWORD_DEFAULT);

    if ($passwordHash === false) {
        throw new RuntimeException('Échec du hash du mot de passe.');
    }

    $userStmt = $pdo->prepare(
        'INSERT INTO users
            (username, email, password_hash, role_id, status)
         SELECT
            :username,
            NULL,
            :password_hash,
            r.id,
            :status
         FROM roles r
         WHERE r.name = :role'
    );

    $userStmt->execute([
        ':username' => 'pdg',
        ':password_hash' => $passwordHash,
        ':status' => 'ACTIVE',
        ':role' => 'PDG',
    ]);

    if ($userStmt->rowCount() !== 1) {
        throw new RuntimeException(
            'Création du compte PDG impossible : rôle PDG absent ou conflit utilisateur.'
        );
    }

    $pdo->commit();

    putenv('IMC_BOOTSTRAP_PASSWORD');

    echo PHP_EOL;
    echo "==============================================\n";
    echo " P0-A.1 BOOTSTRAP : PASS\n";
    echo "==============================================\n";
    echo "Roles             : " .
        $pdo->query('SELECT COUNT(*) FROM roles')->fetchColumn() . "\n";
    echo "Permissions       : " .
        $pdo->query('SELECT COUNT(*) FROM permissions')->fetchColumn() . "\n";
    echo "Role permissions  : " .
        $pdo->query('SELECT COUNT(*) FROM role_permissions')->fetchColumn() . "\n";
    echo "Users             : " .
        $pdo->query('SELECT COUNT(*) FROM users')->fetchColumn() . "\n";
    echo "Utilisateur       : pdg\n";
    echo "Statut            : ACTIVE\n";
    echo "Role              : PDG\n";
    echo "==============================================\n";

} catch (Throwable $e) {

    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }

    putenv('IMC_BOOTSTRAP_PASSWORD');

    fwrite(STDERR, "BOOTSTRAP ECHEC: " . $e->getMessage() . PHP_EOL);
    exit(1);
}
