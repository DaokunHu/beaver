WITH TermParams AS (
    SELECT t0.TERM_PARAMETER,
           t0.TERM_CODE,
           t1.ACADEMIC_YEAR,
           t2.DEPARTMENT_NAME,
           SUM(t1.ACADEMIC_YEAR) OVER (PARTITION BY t2.DEPARTMENT_NAME ORDER BY t1.ACADEMIC_YEAR) AS running_sum_academic_year
    FROM ACADEMIC_TERM_PARAMETER t0
    JOIN ACADEMIC_TERMS t1 ON t0.TERM_CODE = t1.TERM_CODE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED t2 ON t1.TERM_CODE = t2.EFFECTIVE_TERM_CODE
    WHERE t0.TERM_INDICATOR = 'C'
),
DeptSubjectCounts AS (
    SELECT DEPARTMENT_NAME
    FROM TermParams
    GROUP BY DEPARTMENT_NAME
    HAVING COUNT(*) >= 3
),
DeptStats AS (
    SELECT d.DEPARTMENT_NAME,
           AVG(s.TOTAL_UNITS) AS avg_total_units,
           STDDEV(s.TOTAL_UNITS) AS stddev_total_units
    FROM SIS_DEPARTMENT d
    JOIN SUBJECT_OFFERED_SUMMARY s ON d.DEPARTMENT_CODE = s.OFFER_DEPT_CODE
    WHERE s.TOTAL_UNITS > 0
      AND s.NUM_ENROLLED_STUDENTS >= 1
    GROUP BY d.DEPARTMENT_NAME
)
SELECT tp.TERM_PARAMETER,
       tp.TERM_CODE,
       tp.ACADEMIC_YEAR,
       tp.DEPARTMENT_NAME,
       tp.running_sum_academic_year,
       ds.avg_total_units,
       ds.stddev_total_units,
       CASE
           WHEN ds.stddev_total_units > ds.avg_total_units * 1.2 THEN 'HIGH_VARIANCE'
           WHEN ds.stddev_total_units < ds.avg_total_units * 0.8 THEN 'LOW_VARIANCE'
           ELSE 'AVERAGE_VARIANCE'
       END AS variance_category
FROM TermParams tp
JOIN DeptSubjectCounts dc ON tp.DEPARTMENT_NAME = dc.DEPARTMENT_NAME
JOIN DeptStats ds ON tp.DEPARTMENT_NAME = ds.DEPARTMENT_NAME
ORDER BY tp.DEPARTMENT_NAME, tp.ACADEMIC_YEAR