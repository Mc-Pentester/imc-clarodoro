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
