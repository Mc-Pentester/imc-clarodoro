#!/usr/bin/env bash
set -euo pipefail
php -l api/parents/index.php
php -l private-pages/parents.php
php -l private-pages/index.php
php -l private-pages/PDG.php
php -l private-pages/personnel.php
grep -q "'parents.html'.*parents.php.*parents.read" secure-page.php
grep -Fq "'/parents.html' => 'parents.html'" router.php
grep -q "parents.read" database/migrations/20261117130000_independent_parent_directory.sql
grep -q "student_parents" api/parents/index.php
grep -q "parent_preserved" api/parents/index.php
grep -q "ON CONFLICT(student_id,parent_id)" api/parents/index.php
grep -q "action:'link'" private-pages/parents.php
grep -q "parents" private-pages/index.php
grep -q 'parentpereExistant' private-pages/index.php
grep -q 'parent_id' api/students/index.php
grep -q 'chargerParentsDisponibles' private-pages/index.php
echo "PARENTS MODULE STATIC CONTRACT: PASS"
