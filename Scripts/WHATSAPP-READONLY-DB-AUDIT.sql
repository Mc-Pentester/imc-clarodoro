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

-- 3. Agrégats conditionnels : chaque contrôle vérifie d'abord l'existence de sa table.
-- Les valeurs sont des agrégats; aucune donnée personnelle n'est affichée.
DO $audit$
DECLARE total_rows BIGINT; missing_rows BIGINT; links BIGINT; linked_students BIGINT;
        linked_parents BIGINT; primary_links BIGINT; without_link BIGINT; multi_link BIGINT;
        t TEXT;
BEGIN
    IF to_regclass('public.students') IS NOT NULL THEN
        EXECUTE 'SELECT count(*), count(*) FILTER (WHERE phone IS NULL OR btrim(phone) = '''') FROM public.students'
          INTO total_rows, missing_rows;
        RAISE NOTICE 'students: total=%, téléphone manquant/vide=%', total_rows, missing_rows;
    ELSE RAISE NOTICE 'SKIP: public.students absent'; END IF;

    IF to_regclass('public.parents') IS NOT NULL THEN
        EXECUTE 'SELECT count(*), count(*) FILTER (WHERE phone IS NULL OR btrim(phone) = '''') FROM public.parents'
          INTO total_rows, missing_rows;
        RAISE NOTICE 'parents: total=%, téléphone manquant/vide=%', total_rows, missing_rows;
    ELSE RAISE NOTICE 'SKIP: public.parents absent'; END IF;

    IF to_regclass('public.student_parents') IS NOT NULL THEN
        EXECUTE 'SELECT count(*), count(DISTINCT student_id), count(DISTINCT parent_id), count(*) FILTER (WHERE is_primary) FROM public.student_parents'
          INTO links, linked_students, linked_parents, primary_links;
        RAISE NOTICE 'student_parents: liens=%, élèves liés=%, parents liés=%, liens primaires=%',
          links, linked_students, linked_parents, primary_links;
        IF to_regclass('public.students') IS NOT NULL THEN
            EXECUTE 'SELECT count(*) FILTER (WHERE link_count = 0), count(*) FILTER (WHERE link_count > 1) FROM (SELECT s.id, count(sp.parent_id) AS link_count FROM public.students s LEFT JOIN public.student_parents sp ON sp.student_id = s.id GROUP BY s.id) x'
              INTO without_link, multi_link;
            RAISE NOTICE 'élèves sans lien parent=%, élèves avec plusieurs liens=%', without_link, multi_link;
        END IF;
    ELSE RAISE NOTICE 'SKIP: public.student_parents absent'; END IF;

    FOREACH t IN ARRAY ARRAY['invoices','payments','enrollments','grades','result_carnets','attendance'] LOOP
        IF to_regclass('public.' || t) IS NOT NULL THEN
            EXECUTE format('SELECT count(*) FROM public.%I', t) INTO total_rows;
            RAISE NOTICE '%: total=%', t, total_rows;
        ELSE
            RAISE NOTICE 'SKIP: public.% absent', t;
        END IF;
    END LOOP;
END
$audit$;

ROLLBACK;
