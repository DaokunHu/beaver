WITH highest_avg_enrollment AS (
  WITH inner_cte AS (
    SELECT s.DEPARTMENT_NAME,
           l.TERM_CODE,
           AVG(l.NUM_ENROLLED_STUDENTS) AS avg_enrollment_per_term
    FROM SIS_SUBJECT_CODE s
    JOIN LIBRARY_SUBJECT_OFFERED l ON s.COURSE_NUMBER = l.COURSE_NUMBER
    WHERE l.NUM_ENROLLED_STUDENTS > 0
      AND s.DEPARTMENT_NAME IS NOT NULL
      AND s.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY s.DEPARTMENT_NAME, l.TERM_CODE
  )
  SELECT DEPARTMENT_NAME,
         MAX(avg_enrollment_per_term) AS highest_avg_enrollment_per_term
  FROM inner_cte
  GROUP BY DEPARTMENT_NAME
),
dept_stats AS (
  SELECT CASE WHEN GROUPING(t1.DEPARTMENT_NAME) = 1 THEN NULL ELSE t1.DEPARTMENT_NAME END AS DEPARTMENT_NAME,
         COUNT(*) AS total_subjects,
         AVG(t1.TOTAL_UNITS) AS avg_total_units
  FROM ACADEMIC_TERMS t0
  JOIN COURSE_CATALOG_SUBJECT_OFFERED t1 ON t0.TERM_CODE = t1.EFFECTIVE_TERM_CODE
  WHERE t0.TERM_CODE = '2019FA'
  GROUP BY t1.DEPARTMENT_NAME WITH ROLLUP
)
SELECT d.DEPARTMENT_NAME,
       d.total_subjects,
       d.avg_total_units,
       h.highest_avg_enrollment_per_term
FROM dept_stats d
LEFT JOIN highest_avg_enrollment h ON d.DEPARTMENT_NAME = h.DEPARTMENT_NAME
ORDER BY d.DEPARTMENT_NAME