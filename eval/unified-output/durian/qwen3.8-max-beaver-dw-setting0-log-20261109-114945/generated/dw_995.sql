WITH dept_enrollment_stats AS (
    SELECT sd.DEPARTMENT_NAME,
           AVG(tso.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
           VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrollment_variance
    FROM SIS_DEPARTMENT sd
    JOIN TIP_SUBJECT_OFFERED tso ON sd.DEPARTMENT_CODE = tso.OFFER_DEPT_CODE
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND tso.NUM_ENROLLED_STUDENTS > 0
      AND sd.DEPARTMENT_NAME <> 'Political Science'
      AND sd.DEPARTMENT_CODE <> '17'
    GROUP BY sd.DEPARTMENT_NAME
),
chem_bio_year_stats AS (
    SELECT tso.OFFER_DEPT_NAME AS DEPARTMENT_NAME,
           t.ACADEMIC_YEAR,
           COUNT(DISTINCT tso.SUBJECT_ID) AS subject_count,
           MIN(t.TERM_START_DATE) AS min_term_start_date
    FROM TIP_SUBJECT_OFFERED tso
    JOIN ACADEMIC_TERMS_ALL t ON tso.TERM_CODE = t.TERM_CODE
    WHERE tso.OFFER_DEPT_NAME IN ('Chemistry', 'Biology')
      AND tso.NUM_ENROLLED_STUDENTS > 0
    GROUP BY tso.OFFER_DEPT_NAME, t.ACADEMIC_YEAR
)
SELECT DEPARTMENT_NAME,
       avg_enrollment,
       enrollment_variance,
       NULL AS ACADEMIC_YEAR,
       NULL AS subject_count,
       NULL AS min_term_start_date
FROM dept_enrollment_stats
UNION ALL
SELECT DEPARTMENT_NAME,
       NULL AS avg_enrollment,
       NULL AS enrollment_variance,
       ACADEMIC_YEAR,
       subject_count,
       min_term_start_date
FROM chem_bio_year_stats
ORDER BY DEPARTMENT_NAME