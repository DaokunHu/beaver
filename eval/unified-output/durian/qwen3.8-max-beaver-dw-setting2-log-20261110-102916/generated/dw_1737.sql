WITH DepartmentStats AS (
  SELECT t1.DEPARTMENT_NAME,
         COUNT(DISTINCT t1.SUBJECT_ID) AS total_subjects,
         AVG(t1.TOTAL_UNITS) AS avg_total_units
  FROM ACADEMIC_TERMS t0
  JOIN SUBJECT_SUMMARY t1 ON t0.TERM_CODE = t1.TERM_CODE
  WHERE t0.TERM_CODE = '2019FA'
  GROUP BY t1.DEPARTMENT_NAME
),
highest_avg_enrollment AS (
  WITH inner_cte AS (
    SELECT s.DEPARTMENT_NAME, l.TERM_CODE, AVG(l.NUM_ENROLLED_STUDENTS) AS avg_enrollment_per_term
    FROM SIS_SUBJECT_CODE s
    JOIN LIBRARY_SUBJECT_OFFERED l ON s.COURSE_NUMBER = l.COURSE_NUMBER
    WHERE l.NUM_ENROLLED_STUDENTS > 0
      AND s.DEPARTMENT_NAME IS NOT NULL
      AND s.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY s.DEPARTMENT_NAME, l.TERM_CODE
  )
  SELECT DEPARTMENT_NAME, MAX(avg_enrollment_per_term) AS highest_avg_enrollment_per_term
  FROM inner_cte
  GROUP BY DEPARTMENT_NAME
)
SELECT ds.DEPARTMENT_NAME, ds.total_subjects, ds.avg_total_units, hae.highest_avg_enrollment_per_term
FROM DepartmentStats ds
LEFT JOIN highest_avg_enrollment hae ON ds.DEPARTMENT_NAME = hae.DEPARTMENT_NAME
UNION ALL
SELECT NULL AS DEPARTMENT_NAME, SUM(ds.total_subjects) AS total_subjects, AVG(ds.avg_total_units) AS avg_total_units, NULL AS highest_avg_enrollment_per_term
FROM DepartmentStats ds
ORDER BY DEPARTMENT_NAME