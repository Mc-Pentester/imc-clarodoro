<?php
declare(strict_types=1);

/**
 * IMC-Clarodoro - Local environment loader.
 *
 * IMC_CLARODARO_ENV_FILE may point to the protected ProgramData configuration
 * used by the Windows installer. Without it, the legacy project-root .env
 * remains the fallback for existing installations and development.
 */

function loadLocalEnvironment(): void
{
    static $loaded = false;

    if ($loaded) {
        return;
    }

    $loaded = true;
    $configuredPath = getenv('IMC_CLARODARO_ENV_FILE');
    $envFile = is_string($configuredPath) && trim($configuredPath) !== ''
        ? trim($configuredPath)
        : dirname(__DIR__) . DIRECTORY_SEPARATOR . '.env';

    if (!is_file($envFile) || !is_readable($envFile)) {
        return;
    }

    $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

    if ($lines === false) {
        return;
    }

    foreach ($lines as $line) {
        $line = trim($line);

        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }

        if (str_starts_with($line, 'export ')) {
            $line = trim(substr($line, 7));
        }

        $separator = strpos($line, '=');

        if ($separator === false) {
            continue;
        }

        $name = trim(substr($line, 0, $separator));
        $value = trim(substr($line, $separator + 1));

        if ($name === '' || !preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $name)) {
            continue;
        }

        // Explicit process variables take precedence over the file.
        if (getenv($name) !== false) {
            continue;
        }

        if (
            strlen($value) >= 2 &&
            (($value[0] === '"' && $value[strlen($value) - 1] === '"') ||
             ($value[0] === "'" && $value[strlen($value) - 1] === "'"))
        ) {
            $value = substr($value, 1, -1);
        }

        putenv($name . '=' . $value);
        $_ENV[$name] = $value;
        $_SERVER[$name] = $value;
    }
}

loadLocalEnvironment();
