from pathlib import Path

def read(path):
    return Path(path).read_text(encoding="utf-8")

def require(condition, message):
    if not condition:
        raise SystemExit(f"WINDOWS INSTALLER SAFETY: FAIL: {message}")

configure = read("installer/Configure-Windows-Services.ps1")
launcher = read("installer/Start-Clarodaro-Server.ps1")
cleanup = read("installer/Remove-Windows-Services.ps1")
iss = read("installer/IMC-Clarodoro.iss")
router = read("router.php")
env_loader = read("config/env.php")
pdg_setup = read("installer/Initialize-PDG-Account.ps1")
workflow = read(".github/workflows/windows-installer.yml")

require("IMC-Clarodaro-PostgreSQL" in configure, "dedicated PostgreSQL service name missing")
require("NETWORK SERVICE" in configure and "LOCAL SERVICE" in configure and "S-1-5-20" in configure and "S-1-5-19" in configure,
        "restricted, separate Windows service identities missing")
require("IMC-Clarodaro-PHP-Server" in configure, "PHP startup task name missing")
require("55432" in configure and "8080" in configure, "dedicated ports/default HTTP port missing")
require("Test-PortAvailable" in configure, "port conflict protection missing")
require("PathName" in configure and "Aucun service tiers" in configure,
        "service ownership checks missing")
require("initial-provisioning-incomplete.marker" in configure,
        "incomplete first-install marker missing")
require("database\\migrate.php" in configure and "'--status'" in configure and "'--apply'" in configure,
        "new-database migration flow missing")
fresh_flow, existing_flow = configure.split("elseif ($service)", 1)
require("bootstrap-auth.php" not in configure and "schema.sql" in fresh_flow and "schema.sql" not in existing_flow,
        "fresh-only schema initialization guard missing")
require("CREATE TABLE schema_migrations" in fresh_flow,
        "fresh database migration baseline missing")
require("managedLocalDatabase" in configure and "PG_VERSION" in existing_flow and "Réenregistrement du service" in existing_flow and "pg_ctl register" in existing_flow,
        "reinstall must restore the preserved cluster without initdb or schema replay")
require("hasProtectedConfig" in configure and "hasLegacyConfig" in configure,
        "existing configuration preservation guards missing")
require("Set-PrivateAcl $legacyEnvironmentFile" in configure and "icacls.exe $AppRoot /reset" in configure and "Permissions: users-modify" not in iss,
        "installed code and legacy database secrets must not be writable by all local users")
require("0.0.0.0:$HttpPort" in launcher, "PHP startup launcher is not configurable")
require("IMC_CLARODARO_ENV_FILE" in launcher and "router.php" in launcher,
        "PHP server does not load protected environment or router")
require("Unregister-ScheduledTask" in cleanup and "sc.exe delete" in cleanup and "NETWORK SERVICE" in cleanup and "LOCAL SERVICE" in cleanup,
        "owned task/service cleanup missing")
require("PostgreSQL\\data" in cleanup and "Remove-Item" not in cleanup,
        "uninstall must preserve ProgramData database and config")
require("runtime" in router and "installer" in router and "database" in router and "router.php" in router and "strncasecmp" in router,
        "HTTP router must deny direct access to runtimes, secrets and internal directories")
require("Initialize-PDG-Account.ps1" in iss and "createpdg" in iss and "skipifsilent" in iss,
        "optional first-PDG setup task missing")
require("LOWER(u.username)" in pdg_setup and "r.name" in pdg_setup and "bootstrap-auth.php" in pdg_setup,
        "first-PDG script must check existing account before bootstrap")
require("Read-Host" in pdg_setup and "IMC_BOOTSTRAP_PASSWORD" in pdg_setup,
        "first-PDG script must prompt securely and pass password only to CLI")
require("Prepare-Upgrade.ps1" in iss and "CurStepChanged" in iss,
        "pre-upgrade service shutdown hook missing")
require("Remove-Windows-Services.ps1" in iss and "CurUninstallStepChanged" in iss,
        "uninstall cleanup hook missing")
require("Configure-Windows-Services.ps1" in iss and "AfterInstall: ConfigureAfterFiles" in iss and "procedure ConfigureAfterFiles" in iss,
        "post-file-copy service provisioning hook missing")
require("Remove-Windows-Services.ps1" in iss and "Start-Clarodaro-Server.ps1" in iss,
        "installer does not package service scripts")
require("IMC_CLARODARO_ENV_FILE" in env_loader,
        "protected ProgramData environment path is not supported")
require("Prepare-Bundled-Runtimes.ps1" in workflow,
        "runtime payload preparation missing")
require("1.1.0" in workflow, "installer artifact version mismatch")
require("Smoke test clean install" in workflow and "Réinstallation sans désinstallation" in workflow,
        "Windows clean-install and in-place-reinstall smoke test missing")
require("installer_upgrade_sentinel" in workflow and "PG_VERSION" in workflow and "Reinstall after a full uninstall" in workflow,
        "Windows smoke test does not verify PostgreSQL data preservation")

print("WINDOWS INSTALLER DATA AND SERVICE SAFETY: PASS")
