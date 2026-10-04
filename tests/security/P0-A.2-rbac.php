<?php
declare(strict_types=1);

$tests = [];
$allPassed = true;

echo "P0-A.2 RBAC STATIC TEST" . PHP_EOL;
echo "=======================" . PHP_EOL . PHP_EOL;

// Test A: requireAuthenticatedUser signature
$authContent = file_get_contents(__DIR__ . '/../../config/auth.php');
$tests['requireAuthenticatedUser(PDO $pdo)'] = str_contains($authContent, 'function requireAuthenticatedUser(PDO $pdo)');

// Test B: requirePermission calls requireAuthenticatedUser($pdo)
$tests['requirePermission calls requireAuthenticatedUser($pdo)'] = str_contains($authContent, '$user = requireAuthenticatedUser($pdo);');

// Test C: requireAuthenticatedUser contains DB lookup with users, roles, status
$tests['DB-backed user lookup (users, roles, status)'] = str_contains($authContent, 'FROM users u')
    && str_contains($authContent, 'INNER JOIN roles r')
    && str_contains($authContent, "'ACTIVE'");

// Test D: requirePermission uses role_permissions and permissions
$tests['role_permissions lookup'] = str_contains($authContent, 'FROM role_permissions rp')
    && str_contains($authContent, 'INNER JOIN permissions p');

// Test E: 401 for no session
$tests['401 for missing session'] = str_contains($authContent, "apiError(401, 'Authentification requise')");

// Test F: 403 for insufficient permission
$tests['403 for insufficient permission'] = str_contains($authContent, "apiError(403, 'Permission insuffisante')");

// Test G: permission-test.php uses eleves.read
$permissionTestContent = file_get_contents(__DIR__ . '/../../api/auth/permission-test.php');
$tests['permission-test.php uses eleves.read'] = str_contains($permissionTestContent, "requirePermission(\$pdo, 'eleves.read')");

// Test H: permission-denied-test.php uses eleves.create
$permissionDeniedTestContent = file_get_contents(__DIR__ . '/../../api/auth/permission-denied-test.php');
$tests['permission-denied-test.php uses eleves.create'] = str_contains($permissionDeniedTestContent, "requirePermission(\$pdo, 'eleves.create')");

// Display results
foreach ($tests as $name => $passed) {
    $status = $passed ? 'PASS' : 'FAIL';
    echo "{$name} : {$status}" . PHP_EOL;
    if (!$passed) {
        $allPassed = false;
    }
}

echo PHP_EOL;
echo "RESULT : " . ($allPassed ? 'PASS' : 'FAIL') . PHP_EOL;

exit($allPassed ? 0 : 1);
