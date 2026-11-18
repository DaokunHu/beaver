WITH course_stats AS (
  SELECT scd.DEPARTMENT_NAME, scd.COURSE_LEVEL,
         COUNT(DISTINCT scd.COURSE) AS course_count,
         MIN(ccc.TOTAL_UNITS) AS min_total_units
  FROM SIS_COURSE_DESCRIPTION scd
  JOIN SIS_DEPARTMENT sd ON scd.DEPARTMENT = sd.DEPARTMENT_CODE
  JOIN CIS_COURSE_CATALOG ccc ON sd.DEPARTMENT_CODE = ccc.DEPARTMENT_CODE
  WHERE scd.IS_DEGREE_GRANTING = 'Y' AND ccc.TOTAL_UNITS > 6
  GROUP BY scd.DEPARTMENT_NAME, scd.COURSE_LEVEL
),
course_stats_avg AS (
  SELECT cs.DEPARTMENT_NAME, cs.COURSE_LEVEL, cs.course_count, cs.min_total_units,
         AVG(ccc.TOTAL_UNITS) AS avg_total_units
  FROM course_stats cs
  JOIN SIS_DEPARTMENT sd ON cs.DEPARTMENT_NAME = sd.DEPARTMENT_NAME
  JOIN CIS_COURSE_CATALOG ccc ON sd.DEPARTMENT_CODE = ccc.DEPARTMENT_CODE
  GROUP BY cs.DEPARTMENT_NAME, cs.COURSE_LEVEL, cs.course_count, cs.min_total_units
),
subject_stats AS (
  SELECT d.DEPARTMENT_NAME, s.SUBJECT_CODE,
         COUNT(s.SUBJECT_CODE) AS subject_code_count,
         MIN(d.DEPT_BUDGET_CODE) AS min_dept_budget_code
  FROM SIS_DEPARTMENT d
  JOIN SIS_SUBJECT_CODE s ON d.DEPARTMENT_CODE = s.DEPARTMENT_CODE
  WHERE d.IS_DEGREE_GRANTING = 'Y'
  GROUP BY d.DEPARTMENT_NAME, s.SUBJECT_CODE
),
subject_stats_full AS (
  SELECT ss.DEPARTMENT_NAME, ss.SUBJECT_CODE, ss.subject_code_count,
         ss.min_dept_budget_code, d.DEPARTMENT_FULL_NAME
  FROM subject_stats ss
  JOIN SIS_DEPARTMENT d ON ss.DEPARTMENT_NAME = d.DEPARTMENT_NAME
)
SELECT csa.DEPARTMENT_NAME, csa.COURSE_LEVEL, csa.course_count, csa.min_total_units,
       csa.avg_total_units, ssf.SUBJECT_CODE, ssf.subject_code_count,
       ssf.min_dept_budget_code, ssf.DEPARTMENT_FULL_NAME
FROM course_stats_avg csa
JOIN subject_stats_full ssf ON csa.DEPARTMENT_NAME = ssf.DEPARTMENT_NAME