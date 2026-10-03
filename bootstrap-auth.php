<?php

declare(strict_types=1);

require_once __DIR__ . '/config/database.php';

$pdo = getDatabaseConnection();
$pdo->beginTransaction();

try {
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
        'presences.create',
        'vault.update',
    ];

    $permissionStmt = $pdo->prepare(
        'INSERT INTO permissions (name, description)
         VALUES (:name, :description)
         ON CONFLICT (name)
         DO UPDATE SET
             description = EXCLUDED.description,
             updated_at = NOW()'
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
        ],

        'Enseignant' => [
            'eleves.read',
            'annees.read',
            'matieres.read',
            'resultats.read',
            'resultats.create',
            'resultats.update',
            'vacances.read',
            'presences.create',
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

    $password = getenv('IMC_BOOTSTRAP_PASSWORD');

    if (!is_string($password) || strlen($password) < 12) {
        throw new RuntimeException(
            'IMC_BOOTSTRAP_PASSWORD doit contenir au moins 12 caractères.'
        );
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
         WHERE r.name = :role
         ON CONFLICT (username)
         DO UPDATE SET
            password_hash = EXCLUDED.password_hash,
            role_id = EXCLUDED.role_id,
            status = EXCLUDED.status,
            updated_at = NOW()'
    );

    $userStmt->execute([
        ':username' => 'pdg',
        ':password_hash' => $passwordHash,
        ':status' => 'ACTIVE',
        ':role' => 'PDG',
    ]);

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
