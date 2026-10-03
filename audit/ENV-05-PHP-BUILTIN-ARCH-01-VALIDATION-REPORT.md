# ENV-05 - PHP BUILT-IN SERVER - ARCH-01 VALIDATION

## Summary
HTTP validation of IMC-Clarodoro application with PHP built-in server.

## Verdict
NO-GO

## Environment
- Project: C:\IMC-Clarodoro-securise-client\IMC-Clarodoro
- PHP: C:\PHP\8.2\php.exe
- Validation URL: http://127.0.0.1:8090
- Apache: not modified
- PostgreSQL: not modified
- Database: no creation/modification

## Statistics
- PASS: 20
- WARNING: 0
- BLOCKED: 1

## Results
| Test | Status | Details |
|---|---|---|
| Project IMC-Clarodoro present | PASS | C:\IMC-Clarodoro-securise-client\IMC-Clarodoro |
| PHP CLI available | PASS | PHP 8.2.34 (cli) (built: Sep 22 2026 09:01:25) (ZTS Visual C++ 2019 x64) |
| File /api/health.php | PASS | C:\IMC-Clarodoro-securise-client\IMC-Clarodoro\api\health.php |
| File /api/index.php | PASS | C:\IMC-Clarodoro-securise-client\IMC-Clarodoro\api\index.php |
| File /api/health-db.php | PASS | C:\IMC-Clarodoro-securise-client\IMC-Clarodoro\api\health-db.php |
| Port TCP 8090 available | PASS | Port 8090 is free. |
| Start PHP Built-in Server | PASS | PID=8772, listening on http://127.0.0.1:8090 |
| PHP server accessible | PASS | http://127.0.0.1:8090 responds at TCP level. |
| HTTP /api/health.php | BLOCKED | No HTTP response. Error: The operation has timed out. |
| HTTP /api/index.php | PASS | HTTP 200, Content-Type=application/json; charset=utf-8, ms |
| HTTP /api/health-db.php | PASS | HTTP 200, Content-Type=application/json; charset=utf-8, ms |
| PHP errors visible /api/health.php | PASS | No obvious PHP error signature detected. |
| PHP errors visible /api/index.php | PASS | No obvious PHP error signature detected. |
| PHP errors visible /api/health-db.php | PASS | No obvious PHP error signature detected. |
| Secret exposure /api/health.php | PASS | No obvious secret pattern detected. |
| Secret exposure /api/index.php | PASS | No obvious secret pattern detected. |
| Secret exposure /api/health-db.php | PASS | No obvious secret pattern detected. |
| PostgreSQL modified by ENV-05 | PASS | No PostgreSQL command executed by this intervention. |
| Apache modified by ENV-05 | PASS | No Apache configuration modified by this intervention. |
| Stop PHP server ENV-05 | PASS | PID 8772 stopped. |
| Port 8090 freed after ENV-05 | PASS | Port 8090 is free. |

## HTTP Responses

### /api/health.php

- URL: http://127.0.0.1:8090/api/health.php
- HTTP: 
- Content-Type: 
- Time: 15021.82 ms

`	ext

``n
### /api/index.php

- URL: http://127.0.0.1:8090/api/index.php
- HTTP: 200
- Content-Type: application/json; charset=utf-8
- Time: 6132.74 ms

`	ext
{
    "success": true,
    "application": "IMC-Clarodoro",
    "api": "v1",
    "status": "ready"
}
``n
### /api/health-db.php

- URL: http://127.0.0.1:8090/api/health-db.php
- HTTP: 200
- Content-Type: application/json; charset=utf-8
- Time: 705.89 ms

`	ext
{
    "success": false,
    "service": "IMC-Clarodoro API",
    "database": "unavailable"
}
``n
## Conclusion

ARCH-01 validation via PHP built-in server is not conclusive. Detailed results must be analyzed before any environment modification.

## Security / Non-destructiveness

- No Apache modification.
- No PostgreSQL modification.
- No database creation.
- No schema changes.
- No application file changes.
- No package installation.
- No external PHP process stopped.

