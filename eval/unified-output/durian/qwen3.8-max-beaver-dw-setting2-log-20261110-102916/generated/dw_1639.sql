WITH inner_cte AS (
  SELECT aca.ACADEMIC_YEAR,
         aca.ACADEMIC_YEAR_DESC,
         sub.DEPARTMENT_NAME,
         STDDEV(sub.TOTAL_UNITS)/NULLIF(AVG(sub.TOTAL_UNITS),0) AS coefficient_of_variation
  FROM COURSE_CATALOG_SUBJECT_OFFERED sub
  JOIN ACADEMIC_TERMS_ALL aca ON sub.TERM_CODE = aca.TERM_CODE
  JOIN ACADEMIC_TERM_PARAMETER param ON aca.TERM_CODE = param.TERM_CODE
  WHERE param.IS_CURRENT_TERM = 'Y'
    AND sub.TOTAL_UNITS > 0
  GROUP BY aca.ACADEMIC_YEAR, aca.ACADEMIC_YEAR_DESC, sub.DEPARTMENT_NAME
  HAVING AVG(sub.TOTAL_UNITS) > 0
),
rollup_cte AS (
  SELECT ACADEMIC_YEAR,
         ACADEMIC_YEAR_DESC,
         DEPARTMENT_NAME,
         SUM(coefficient_of_variation) AS total_coefficient_of_variation
  FROM inner_cte
  GROUP BY ACADEMIC_YEAR, ACADEMIC_YEAR_DESC, DEPARTMENT_NAME WITH ROLLUP
  HAVING SUM(coefficient_of_variation) > 0
),
dept_stats AS (
  SELECT sd.DEPARTMENT_NAME,
         MAX(ccc.TOTAL_UNITS) - MIN(ccc.TOTAL_UNITS) AS total_units_range,
         VARIANCE(ccc.TOTAL_UNITS) AS total_units_variance,
         AVG(ccc.TOTAL_UNITS) AS avg_total_units
  FROM SIS_DEPARTMENT sd
  JOIN CIS_COURSE_CATALOG ccc ON sd.DEPARTMENT_CODE = ccc.DEPARTMENT_CODE
  WHERE sd.IS_DEGREE_GRANTING = 'Y'
    AND ccc.ACADEMIC_YEAR = 2008
    AND sd.DEPARTMENT_CODE <> '5'
  GROUP BY sd.DEPARTMENT_NAME, sd.DEPARTMENT_CODE
),
top_dept AS (
  SELECT ds.DEPARTMENT_NAME,
         ds.avg_total_units,
         ds.total_units_range,
         ds.total_units_variance
  FROM dept_stats ds
  WHERE ds.avg_total_units = (SELECT MAX(avg_total_units) FROM dept_stats)
)
SELECT r.ACADEMIC_YEAR,
       r.ACADEMIC_YEAR_DESC,
       r.DEPARTMENT_NAME,
       r.total_coefficient_of_variation,
       t.avg_total_units,
       t.total_units_range,
       t.total_units_variance
FROM rollup_cte r
LEFT JOIN top_dept t ON r.DEPARTMENT_NAME = t.DEPARTMENT_NAME
ORDER BY r.ACADEMIC_YEAR, r.DEPARTMENT_NAME