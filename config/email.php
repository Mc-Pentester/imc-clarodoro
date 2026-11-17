<?php
declare(strict_types=1);

require_once __DIR__ . '/env.php';

/** Send a UTF-8 text email through the school's configured SMTP relay. */
function imcSendSmtpEmail(string $to, string $subject, string $body): void
{
    $host = trim((string) (getenv('SMTP_HOST') ?: ''));
    $portRaw = getenv('SMTP_PORT') ?: '587';
    $username = (string) (getenv('SMTP_USERNAME') ?: '');
    $password = (string) (getenv('SMTP_PASSWORD') ?: '');
    $security = strtolower(trim((string) (getenv('SMTP_SECURITY') ?: 'tls')));
    $from = trim((string) (getenv('SMTP_FROM_EMAIL') ?: ''));
    $fromName = str_replace(["\\r", "\\n"], '', trim((string) (getenv('SMTP_FROM_NAME') ?: 'Clarodaro')));

    if ($host === '' || !ctype_digit((string) $portRaw) || $from === '' ||
        !filter_var($from, FILTER_VALIDATE_EMAIL) || !filter_var($to, FILTER_VALIDATE_EMAIL) ||
        !in_array($security, ['tls', 'ssl'], true)) {
        throw new RuntimeException('Configuration SMTP incomplète ou invalide. TLS ou SSL est obligatoire.');
    }
    if (($username === '') !== ($password === '')) {
        throw new RuntimeException('Les identifiants SMTP doivent être fournis ensemble.');
    }

    $port = (int) $portRaw;
    if ($port < 1 || $port > 65535) {
        throw new RuntimeException('Port SMTP invalide.');
    }

    // SMTP is always encrypted: STARTTLS or implicit TLS.
    $remote = ($security === 'ssl' ? 'ssl://' : 'tcp://') . $host . ':' . $port;
    $socket = @stream_socket_client($remote, $errno, $error, 10, STREAM_CLIENT_CONNECT);
    if (!is_resource($socket)) {
        throw new RuntimeException('Connexion au serveur SMTP impossible.');
    }
    stream_set_timeout($socket, 10);

    $read = static function (array $expected) use ($socket): string {
        $response = '';
        do {
            $line = fgets($socket, 515);
            if ($line === false) {
                throw new RuntimeException('Réponse SMTP interrompue.');
            }
            $response .= $line;
        } while (isset($line[3]) && $line[3] === '-');
        $code = (int) substr($line, 0, 3);
        if (!in_array($code, $expected, true)) {
            throw new RuntimeException('Le serveur SMTP a refusé une étape de livraison.');
        }
        return $response;
    };
    $write = static function (string $command) use ($socket): void {
        if (fwrite($socket, $command . "\r\n") === false) {
            throw new RuntimeException('Écriture SMTP impossible.');
        }
    };

    try {
        $read([220]);
        $write('EHLO clarodaro.local');
        $read([250]);
        if ($security === 'tls') {
            $write('STARTTLS');
            $read([220]);
            if (!stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
                throw new RuntimeException('Négociation TLS SMTP impossible.');
            }
            $write('EHLO clarodaro.local');
            $read([250]);
        }
        if ($username !== '') {
            $write('AUTH LOGIN');
            $read([334]);
            $write(base64_encode($username));
            $read([334]);
            $write(base64_encode($password));
            $read([235]);
        }
        $write('MAIL FROM:<' . $from . '>');
        $read([250]);
        $write('RCPT TO:<' . $to . '>');
        $read([250, 251]);
        $write('DATA');
        $read([354]);

        $encodedSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
        $safeName = '=?UTF-8?B?' . base64_encode($fromName) . '?=';
        $headers = [
            'Date: ' . date(DATE_RFC2822),
            'From: ' . $safeName . ' <' . $from . '>',
            'To: <' . $to . '>',
            'Subject: ' . $encodedSubject,
            'MIME-Version: 1.0',
            'Content-Type: text/plain; charset=UTF-8',
            'Content-Transfer-Encoding: 8bit',
        ];
        $message = implode("\r\n", $headers) . "\r\n\r\n" . str_replace(["\r\n", "\r"], "\n", $body);
        $message = preg_replace('/\n\./', "\n..", $message) ?? $message;
        $message = str_replace("\n", "\r\n", $message);
        $write($message . "\r\n.");
        $read([250]);
        $write('QUIT');
        $read([221]);
    } finally {
        fclose($socket);
    }
}
