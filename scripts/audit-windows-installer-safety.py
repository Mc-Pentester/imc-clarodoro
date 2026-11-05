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
setup_page = read("setup-page.php")
setup_api = read("api/auth/initial-setup.php")
secure_page = read("secure-page.php")
workflow = read(".github/workflows/windows-installer.yml")

require("IMC-Clarodaro-PostgreSQL" in configure, "dedicated PostgreSQL service name missing")
require("NETWORK SERVICE" in configure and "LOCAL SERVICE" in configure and "S-1-5-20" in configure and "S-1-5-19" in configure,
        "restricted, separate Windows service identities missing")
require("IMC-Clarodaro-PHP-Server" in configure, "PHP startup task name missing")
require("55432" in configure and "18080" in configure, "dedicated ports/default HTTP port missing")
require("Test-PortAvailable" in configure, "port conflict protection missing")
require("WindowsIdentity]::GetCurrent().User.Value" in configure and "$dataRoot /grant $dataRootInstallerAce" in configure
        and "$dataDirectory /inheritance:r /grant:r" in configure and "$dataDirectory /remove:g $installerAce" in configure,
        "initdb must receive temporary access as the installer identity, then remove it before service startup")
require("listen_addresses = '127.0.0.1'" in configure,
        "PostgreSQL must remain local-only; LAN clients connect through the PHP application")
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
require("managedLocalDatabase" in configure and "PG_VERSION" in existing_flow and "Réenregistrement du service" in existing_flow and "$pgCtl register" in existing_flow,
        "reinstall must restore the preserved cluster without initdb or schema replay")
require("hasProtectedConfig" in configure and "hasLegacyConfig" in configure,
        "existing configuration preservation guards missing")
require("Set-PrivateAcl $legacyEnvironmentFile" in configure and "icacls.exe $AppRoot /reset" in configure and "Permissions: users-modify" not in iss,
        "installed code and legacy database secrets must not be writable by all local users")
require("127.0.0.1" in launcher and "0.0.0.0" not in launcher and "HttpBindAddress" in launcher,
        "PHP integrated server must bind to localhost only by default")
require("IMC_CLARODARO_ENV_FILE" in launcher and "router.php" in launcher,
        "PHP server does not load protected environment or router")
require("[int]$HttpPort = 18080" in cleanup and "-LocalPort $HttpPort" in cleanup,
        "uninstall must monitor the configured HTTP port (18080 by default)")
require("-HttpPort 18080" in iss, "Inno Setup must pass the configured HTTP port to uninstall cleanup")
require("New-NetFirewallRule" not in configure and "Remove-NetFirewallRule" in configure,
        "installer must not expose the built-in PHP server through an inbound firewall rule")
require("Unregister-ScheduledTask" in cleanup and "sc.exe delete" in cleanup and "NETWORK SERVICE" in cleanup and "LOCAL SERVICE" in cleanup,
        "owned task/service cleanup missing")
require("PostgreSQL\\data" in cleanup and "Remove-Item" not in cleanup,
        "uninstall must preserve ProgramData database and config")
require("runtime" in router and "installer" in router and "database" in router and "router.php" in router and "strncasecmp" in router,
        "HTTP router must deny direct access to runtimes, secrets and internal directories")
require("Initialize-PDG-Account.ps1" not in iss and "IMC_BOOTSTRAP_PASSWORD" not in iss
        and "Initialize-PDG-Account.ps1" not in workflow and "IMC_BOOTSTRAP_PASSWORD" not in workflow,
        "installer and CI must never create the PDG account automatically")
require("require __DIR__ . '/setup-page.php'" in secure_page and "existingPdg === false" in secure_page,
        "all protected pages must be gated until first-run PDG setup is complete")
require("Create my account" not in setup_page and "Créer mon compte PDG" in setup_page
        and "generateCsrfToken" in setup_page and "/api/auth/initial-setup.php" in setup_page,
        "browser first-run setup page or CSRF protection missing")
require("requireCsrfToken" in setup_api and "proc_open" in setup_api
        and "IMC_BOOTSTRAP_PASSWORD" in setup_api and "password_hash" not in setup_api,
        "one-time HTTP setup must validate CSRF and delegate account creation to the guarded CLI bootstrap")
require("pdgCountBeforeSetup" in workflow and "setupSession" in workflow
        and "api/auth/initial-setup.php" in workflow,
        "Windows smoke test must prove no PDG is created during install and create it through post-install HTTP")
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
require("installer_upgrade_sentinel" in workflow and "PG_VERSION" in workflow and "Reinstall after a full uninstall" in workflow
        and "pdgHashBeforeUpgrade" in workflow and "pdgHashAfterUpgrade" in workflow,
        "Windows smoke test does not verify PostgreSQL data preservation")
require("/eleves.html" in workflow and "JavaScript brut" in workflow,
        "Windows HTTP smoke test is missing the eleves.html raw-JavaScript regression check")

print("WINDOWS INSTALLER DATA AND SERVICE SAFETY: PASS")
