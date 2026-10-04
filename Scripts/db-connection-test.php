<?php

echo "DB_HOST=" . getenv('DB_HOST') . PHP_EOL;
echo "DB_PORT=" . getenv('DB_PORT') . PHP_EOL;
echo "DB_NAME=" . getenv('DB_NAME') . PHP_EOL;
echo "DB_USER=" . getenv('DB_USER') . PHP_EOL;
echo "DB_PASSWORD défini=" . ((getenv('DB_PASSWORD') !== false && getenv('DB_PASSWORD') !== '') ? 'YES' : 'NO') . PHP_EOL;

try {
    $pdo = new PDO(
        'pgsql:host=' . getenv('DB_HOST') .
        ';port=' . getenv('DB_PORT') .
        ';dbname=' . getenv('DB_NAME'),
        getenv('DB_USER'),
        getenv('DB_PASSWORD'),
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        ]
    );

    echo "PDO PostgreSQL OK" . PHP_EOL;
} catch (Throwable $e) {
    echo "PDO PostgreSQL FAILED" . PHP_EOL;
    echo get_class($e) . ': ' . $e->getMessage() . PHP_EOL;
}
