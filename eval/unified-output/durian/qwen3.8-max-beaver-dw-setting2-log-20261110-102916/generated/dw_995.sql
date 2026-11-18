WITH dept_stats AS (
    SELECT sd.DEPARTMENT_NAME,
           AVG(tso.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
           VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrollment_variance
    FROM TIP_SUBJECT_OFFERED tso
    JOIN SIS_DEPARTMENT sd ON tso.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    JOIN SIS_COURSE_DESCRIPTION scd ON sd.DEPARTMENT_CODE = scd.DEPARTMENT
    WHERE tso.NUM_ENROLLED_STUDENTS > 0
      AND scd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_CODE <> '17'
    GROUP BY sd.DEPARTMENT_NAME
),
dept_year_stats AS (
    SELECT tso.OFFER_DEPT_NAME AS department,
           ata.ACADEMIC_YEAR AS academic_year,
           COUNT(DISTINCT tso.SUBJECT_ID) AS subject_count,
           MIN(ata.TERM_START_DATE) AS min_term_start_date
    FROM TIP_SUBJECT_OFFERED tso
    JOIN ACADEMIC_TERMS_ALL ata ON tso.TERM_CODE = ata.TERM_CODE
    WHERE tso.NUM_ENROLLED_STUDENTS > 0
      AND tso.OFFER_DEPT_NAME IN ('Chemistry', 'Biology')
    GROUP BY tso.OFFER_DEPT_NAME, ata.ACADEMIC_YEAR
)
SELECT d.DEPARTMENT_NAME,
       d.avg_enrollment,
       d.enrollment_variance,
       y.academic_year,
       y.subject_count,
       y.min_term_start_date
FROM dept_stats d
JOIN dept_year_stats y ON d.DEPARTMENT_NAME = y.department
ORDER BY d.enrollment_variance DESC, y.department, y.academic_year