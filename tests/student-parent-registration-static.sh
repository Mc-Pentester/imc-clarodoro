#!/usr/bin/env bash
set -euo pipefail
php -l api/students/index.php
php -l private-pages/index.php
grep -Fq 'function normalizeStudentParents' api/students/index.php
grep -Fq 'function saveStudentParents' api/students/index.php
grep -Fq 'INSERT INTO parents' api/students/index.php
grep -Fq 'INSERT INTO student_parents' api/students/index.php
grep -Fq "student['parents']" api/students/index.php
grep -Fq 'id="parentperePrenom"' private-pages/index.php
grep -Fq 'id="parentmerePrenom"' private-pages/index.php
grep -Fq 'id="parenttuteurPrenom"' private-pages/index.php
grep -Fq 'chargerParentsFormulaire(student.parents || [])' private-pages/index.php
grep -Fq 'collecterParentsFormulaire()' private-pages/index.php
grep -Fq 'id="dossierParents"' private-pages/index.php
grep -Fq 'ADD COLUMN IF NOT EXISTS ninu' database/migrations/20261116193000_student_parent_registration.sql
grep -Fq 'parents_ninu_unique' database/migrations/20261116193000_student_parent_registration.sql
echo 'PASS: student-parent registration contract'

grep -Fq 'parentsHorsFormulaire' private-pages/index.php
grep -Fq 'count($raw) > 100' api/students/index.php

# Le gestionnaire doit être attaché avant les appels réseau asynchrones.
FORM_BIND_LINE="$(grep -n 'studentForm.addEventListener("submit", enregistrerEleve)' private-pages/index.php | cut -d: -f1)"
OPTIONS_LINE="$(grep -n 'await chargerOptionsInscription()' private-pages/index.php | cut -d: -f1)"
test -n "$FORM_BIND_LINE" && test -n "$OPTIONS_LINE"
test "$FORM_BIND_LINE" -lt "$OPTIONS_LINE"
grep -Fq 'payload.parents = Array.isArray(eleve.parents) ? eleve.parents : []' private-pages/index.php
echo 'PASS: student save binding and parent payload preserved'
