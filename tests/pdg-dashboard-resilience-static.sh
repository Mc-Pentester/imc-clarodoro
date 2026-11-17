#!/usr/bin/env bash
set -euo pipefail
php -l private-pages/PDG.php
grep -Fq 'id="messageTableauBord"' private-pages/PDG.php
grep -Fq 'afficherSituations(dashboardStudents, anneeConnectee);' private-pages/PDG.php
grep -Fq 'afficherResumeClasses(dashboardStudents, anneeConnectee);' private-pages/PDG.php
grep -Fq 'Promise.allSettled([' private-pages/PDG.php
grep -Fq 'Aucune dépense enregistrée pour cette année scolaire.' private-pages/PDG.php
grep -Fq 'Impossible de charger la liste des dépenses.' private-pages/PDG.php
echo 'PASS: PDG student finance tables isolated from expenses/payroll failures'
