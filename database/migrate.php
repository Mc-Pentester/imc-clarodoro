<?php
declare(strict_types=1);

/**
 * IMC-Clarodoro - PostgreSQL migration runner.
 *
 * Usage:
 *   php database/migrate.php --status
 *   php database/migrate.php --apply
 *
 * The runner is intentionally explicit: database changes only occur with
 * --apply. Applied migrations are tracked by filename and SHA-256 checksum.
 */

require_once dirname(__DIR__) . '/config/database.php';

const MIGRATION_TABLE = 'schema_migrations';

function usage(): void
{
    fwrite(STDOUT, "Usage: php database/migrate.php --status|--apply" . PHP_EOL);
}

function migrationFiles(): array
{
    $directory = __DIR__ . DIRECTORY_SEPARATOR . 'migrations';
    $files = glob($directory . DIRECTORY_SEPARATOR . '*.sql');

    if ($files === false) {
        throw new RuntimeException('Impossible de lire database/migrations.');
    }

    sort($files, SORT_STRING);

    return $files;
}

function historyTableExists(PDO $pdo): bool
{
    $stmt = $pdo->query(
        "SELECT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_name = '" . MIGRATION_TABLE . "'
        )"
    );

    return (bool) $stmt->fetchColumn();
}

function ensureHistoryTable(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS ' . MIGRATION_TABLE . ' (
            filename VARCHAR(255) PRIMARY KEY,
            checksum CHAR(64) NOT NULL,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )'
    );
}

function appliedMigrations(PDO $pdo): array
{
    if (!historyTableExists($pdo)) {
        return [];
    }

    $rows = $pdo->query(
        'SELECT filename, checksum
         FROM ' . MIGRATION_TABLE . '
         ORDER BY filename'
    )->fetchAll();

    $result = [];

    foreach ($rows as $row) {
        $result[(string) $row['filename']] = (string) $row['checksum'];
    }

    return $result;
}

function printStatus(PDO $pdo, array $files): void
{
    $applied = appliedMigrations($pdo);

    fwrite(STDOUT, "Database : " . (string) $pdo->query('SELECT current_database()')->fetchColumn() . PHP_EOL);
    fwrite(STDOUT, "Migration history : " . (historyTableExists($pdo) ? 'PRESENT' : 'MISSING') . PHP_EOL);
    fwrite(STDOUT, PHP_EOL);

    foreach ($files as $file) {
        $filename = basename($file);
        $checksum = hash_file('sha256', $file);

        if ($checksum === false) {
            throw new RuntimeException('Impossible de calculer le checksum de ' . $filename);
        }

        if (!array_key_exists($filename, $applied)) {
            fwrite(STDOUT, "PENDING  " . $filename . PHP_EOL);
            continue;
        }

        if (!hash_equals($applied[$filename], $checksum)) {
            fwrite(STDOUT, "DRIFT    " . $filename . " (checksum différent)" . PHP_EOL);
            continue;
        }

        fwrite(STDOUT, "APPLIED  " . $filename . PHP_EOL);
    }
}

function applyMigrations(PDO $pdo, array $files): void
{
    ensureHistoryTable($pdo);
    $applied = appliedMigrations($pdo);

    foreach ($files as $file) {
        $filename = basename($file);
        $checksum = hash_file('sha256', $file);

        if ($checksum === false) {
            throw new RuntimeException('Impossible de calculer le checksum de ' . $filename);
        }

        if (array_key_exists($filename, $applied)) {
            if (!hash_equals($applied[$filename], $checksum)) {
                throw new RuntimeException(
                    'Migration déjà appliquée mais modifiée : ' . $filename
                );
            }

            fwrite(STDOUT, "SKIP     " . $filename . PHP_EOL);
            continue;
        }

        $sql = file_get_contents($file);

        if ($sql === false || trim($sql) === '') {
            throw new RuntimeException('Migration vide ou illisible : ' . $filename);
        }

        fwrite(STDOUT, "APPLY    " . $filename . PHP_EOL);

        try {
            $pdo->exec($sql);

            $stmt = $pdo->prepare(
                'INSERT INTO ' . MIGRATION_TABLE . ' (filename, checksum)
                 VALUES (:filename, :checksum)
                 ON CONFLICT (filename) DO NOTHING'
            );

            $stmt->execute([
                ':filename' => $filename,
                ':checksum' => $checksum,
            ]);
        } catch (Throwable $e) {
            throw new RuntimeException(
                'Migration échouée : ' . $filename . ' — ' . $e->getMessage(),
                0,
                $e
            );
        }
    }

    fwrite(STDOUT, PHP_EOL . "MIGRATIONS : PASS" . PHP_EOL);
}

$options = $argv;
array_shift($options);

if (count($options) !== 1 || !in_array($options[0], ['--status', '--apply'], true)) {
    usage();
    exit(2);
}

try {
    $pdo = getDatabaseConnection();
    $files = migrationFiles();

    if ($options[0] === '--status') {
        printStatus($pdo, $files);
        exit(0);
    }

    applyMigrations($pdo, $files);
} catch (Throwable $e) {
    fwrite(STDERR, "MIGRATIONS : FAIL" . PHP_EOL);
    fwrite(STDERR, $e->getMessage() . PHP_EOL);
    exit(1);
}
