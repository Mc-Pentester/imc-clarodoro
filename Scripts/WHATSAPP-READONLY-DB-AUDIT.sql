-- IMC-Clarodoro — audit WhatsApp PostgreSQL en lecture seule
-- À exécuter sur la base cible imc_clarodoro avec un compte de lecture.
-- Ce script ne contient aucun INSERT, UPDATE, DELETE, DDL ni migration.
-- Il n'affiche aucun nom, numéro de téléphone, résultat scolaire ou montant individuel.
-- Exécution recommandée :
--   psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f Scripts/WHATSAPP-READONLY-DB-AUDIT.sql
-- Ou dans pgAdmin, ouvrir ce fichier et exécuter l'ensemble.

BEGIN TRANSACTION READ ONLY;

SELECT
    current_database() AS database_name,
    current_user AS database_user,
    current_setting('transaction_read_only') AS transaction_read_only,
    current_setting('server_version') AS postgres_version;

-- 1. Présence des tables et colonnes utiles (catalogue réel, pas le schema.sql versionné).
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    a.attname AS column_name,
    format_type(a.atttypid, a.atttypmod) AS data_type,
    a.attnotnull AS not_null
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
WHERE c.relkind IN ('r', 'p')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND (
    (c.relname = 'students' AND a.attname IN ('id', 'matricule', 'status', 'phone'))
    OR (c.relname = 'parents' AND a.attname IN ('id', 'phone', 'email'))
    OR (c.relname = 'student_parents' AND a.attname IN ('student_id', 'parent_id', 'is_primary', 'relationship_type'))
    OR (c.relname = 'enrollments' AND a.attname IN ('id', 'student_id', 'status', 'school_year_id'))
    OR (c.relname = 'grades' AND a.attname IN ('id', 'enrollment_id'))
    OR (c.relname = 'result_carnets' AND a.attname IN ('id', 'enrollment_id'))
    OR (c.relname = 'attendance' AND a.attname IN ('id', 'enrollment_id', 'attendance_date', 'status'))
    OR (c.relname = 'invoices' AND a.attname IN ('id', 'student_id', 'amount', 'status'))
    OR (c.relname = 'payments' AND a.attname IN ('id', 'invoice_id', 'amount'))
  )
ORDER BY n.nspname, c.relname, a.attnum;

-- 2. Contraintes de clés étrangères réellement présentes sur les tables pertinentes.
SELECT
    ns.nspname AS schema_name,
    src.relname AS source_table,
    con.conname AS constraint_name,
    pg_catalog.pg_get_constraintdef(con.oid, true) AS definition
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class src ON src.oid = con.conrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid = src.relnamespace
WHERE con.contype = 'f'
  AND src.relname IN (
    'student_parents', 'enrollments', 'grades', 'result_carnets',
    'attendance', 'invoices', 'payments'
  )
  AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY ns.nspname, src.relname, con.conname;

-- 3. Totaux de qualité des contacts : agrégats uniquement, sans données personnelles.
-- Si une table/colonne attendue est absente, noter l'erreur et comparer avec la section 1.
SELECT 'students' AS table_name,
       count(*) AS total_rows,
       count(*) FILTER (WHERE phone IS NULL OR btrim(phone) = '') AS missing_or_blank_phone
FROM public.students
UNION ALL
SELECT 'parents',
       count(*),
       count(*) FILTER (WHERE phone IS NULL OR btrim(phone) = '')
FROM public.parents;

-- 4. Relations parent-élève et anomalies d'association, agrégats uniquement.
SELECT
    count(*) AS total_links,
    count(DISTINCT student_id) AS students_with_at_least_one_link,
    count(DISTINCT parent_id) AS parents_linked_to_students,
    count(*) FILTER (WHERE is_primary) AS links_marked_primary
FROM public.student_parents;

SELECT
    count(*) FILTER (WHERE link_count = 0) AS students_without_parent_link,
    count(*) FILTER (WHERE link_count > 1) AS students_with_multiple_parent_links
FROM (
    SELECT s.id, count(sp.parent_id) AS link_count
    FROM public.students s
    LEFT JOIN public.student_parents sp ON sp.student_id = s.id
    GROUP BY s.id
) AS links_per_student;

-- 5. Chaîne financière : facture -> élève et paiement -> facture.
-- Totaux et statuts uniquement; aucun montant individuel n'est affiché.
SELECT 'invoices' AS table_name, count(*) AS total_rows FROM public.invoices
UNION ALL
SELECT 'payments', count(*) FROM public.payments;

-- 6. Résumé de la disponibilité des données liées aux notifications.
SELECT 'enrollments' AS table_name, count(*) AS total_rows FROM public.enrollments
UNION ALL
SELECT 'grades', count(*) FROM public.grades
UNION ALL
SELECT 'result_carnets', count(*) FROM public.result_carnets
UNION ALL
SELECT 'attendance', count(*) FROM public.attendance;

ROLLBACK;
