WITH dept_enrollment_stats AS (
    SELECT sd.DEPARTMENT_NAME,
           AVG(tso.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
           VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrollment_variance
    FROM TIP_SUBJECT_OFFERED tso
    JOIN SIS_DEPARTMENT sd ON tso.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    JOIN SIS_COURSE_DESCRIPTION scd ON sd.DEPARTMENT_CODE = scd.DEPARTMENT
    WHERE tso.NUM_ENROLLED_STUDENTS > 0
      AND scd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_CODE <> '17'
    GROUP BY sd.DEPARTMENT_NAME, sd.DEPARTMENT_CODE
),
chem_bio_year_stats AS (
    SELECT ata.ACADEMIC_YEAR,
           COUNT(tso.SUBJECT_ID) AS subject_count,
           MIN(ata.TERM_START_DATE) AS min_term_start_date
    FROM TIP_SUBJECT_OFFERED tso
    JOIN ACADEMIC_TERMS_ALL ata ON tso.TERM_CODE = ata.TERM_CODE
    JOIN ACADEMIC_TERM_PARAMETER atp ON ata.TERM_CODE = atp.TERM_CODE
    WHERE tso.OFFER_DEPT_NAME IN ('Chemistry', 'Biology')
      AND tso.NUM_ENROLLED_STUDENTS > 0
    GROUP BY ata.ACADEMIC_YEAR
)
SELECT d.DEPARTMENT_NAME,
       d.avg_enrollment,
       d.enrollment_variance,
       c.ACADEMIC_YEAR,
       c.subject_count,
       c.min_term_start_date
FROM dept_enrollment_stats d
CROSS JOIN chem_bio_year_stats c
ORDER BY d.DEPARTMENT_NAME, c.ACADEMIC_YEAR