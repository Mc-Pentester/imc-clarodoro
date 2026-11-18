from pathlib import Path
import re

bootstrap = Path("bootstrap-auth.php").read_text(encoding="utf-8")
recovery = Path("Scripts/RESET-PDG-PASSWORD.php").read_text(encoding="utf-8")
http_recovery = Path("api/auth/reset-pdg-password.php").read_text(encoding="utf-8")

def require(condition, message):
    if not condition:
        raise SystemExit(f"BOOTSTRAP SAFETY: FAIL: {message}")

lock = bootstrap.find("pg_advisory_xact_lock")
guard = bootstrap.find("existingPdgStmt")
first_write = min(
    pos for pos in (
        bootstrap.find("INSERT INTO roles"),
        bootstrap.find("INSERT INTO permissions"),
        bootstrap.find("INSERT INTO role_permissions"),
        bootstrap.find("INSERT INTO users"),
    ) if pos >= 0
)
require(lock >= 0 and lock < guard, "transaction advisory lock must precede the PDG guard")
require(guard >= 0 and guard < first_write, "existing-PDG guard must precede every database write")
require("LOWER(u.username) = 'pdg'" in bootstrap and "r.name = 'PDG'" in bootstrap,
        "guard must detect both the pdg username and existing PDG role")
require("strlen($password) < 12" in bootstrap, "bootstrap password minimum must be checked")
require("$userStmt->rowCount() !== 1" in bootstrap, "creation must require exactly one inserted account")
require(not re.search(r"ON\s+CONFLICT[\s\S]{0,160}?DO\s+UPDATE", bootstrap, re.I),
        "bootstrap must not update existing rows on conflict")
require("ON CONFLICT (username)" not in bootstrap, "user upsert must not return")
require("UPDATE users" in recovery and "password_hash = :password_hash" in recovery,
        "PDG recovery script must retain its targeted password update")
require("IMC_PDG_NEW_PASSWORD" in recovery, "PDG recovery environment variable changed")
require("http_response_code(410)" in http_recovery, "HTTP recovery endpoint behavior changed")

print("BOOTSTRAP FIRST-RUN SAFETY: PASS")
