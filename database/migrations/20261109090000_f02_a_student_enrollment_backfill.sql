-- Backfill legacy student profiles into the normalized enrollment relation.
-- Only exact class/year labels that resolve unambiguously to active reference rows
-- are migrated. Unmatched or ambiguous records are deliberately left untouched.
WITH matching_rows AS (
    SELECT
        s.id AS student_id,
        c.id AS class_id,
        sy.id AS school_year_id,
        COUNT(DISTINCT c.id) OVER (PARTITION BY s.id, sy.id) AS matching_class_count,
        s.created_at::date AS enrollment_date
    FROM students s
    INNER JOIN classes c
        ON LOWER(TRIM(c.name)) = LOWER(TRIM(s.profile_data->>'classe'))
       AND c.status = 'ACTIVE'
    INNER JOIN school_years sy
        ON LOWER(TRIM(sy.label)) = LOWER(TRIM(s.profile_data->>'anneeScolaire'))
       AND sy.status = 'ACTIVE'
    WHERE s.status = 'ACTIVE'
      AND NULLIF(TRIM(s.profile_data->>'classe'), '') IS NOT NULL
      AND NULLIF(TRIM(s.profile_data->>'anneeScolaire'), '') IS NOT NULL
),
unambiguous_matches AS (
    SELECT
        student_id,
        MIN(class_id::text)::uuid AS class_id,
        school_year_id,
        MIN(enrollment_date) AS enrollment_date
    FROM matching_rows
    WHERE matching_class_count = 1
    GROUP BY student_id, school_year_id
)
INSERT INTO enrollments (
    student_id,
    class_id,
    school_year_id,
    status,
    enrollment_date
)
SELECT
    m.student_id,
    m.class_id,
    m.school_year_id,
    'ACTIVE',
    m.enrollment_date
FROM unambiguous_matches m
WHERE NOT EXISTS (
    SELECT 1
    FROM enrollments existing
    WHERE existing.student_id = m.student_id
      AND existing.school_year_id = m.school_year_id
      AND existing.status = 'ACTIVE'
)
ON CONFLICT DO NOTHING;
