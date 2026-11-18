WITH course_stats AS (
    SELECT scd.DEPARTMENT_NAME,
           scd.COURSE_LEVEL,
           COUNT(DISTINCT scd.COURSE) AS course_count,
           MIN(ccc.TOTAL_UNITS) AS min_total_units,
           AVG(ccc.TOTAL_UNITS) AS avg_total_units
    FROM SIS_COURSE_DESCRIPTION scd
    JOIN SIS_DEPARTMENT sd ON scd.DEPARTMENT = sd.DEPARTMENT_CODE
    JOIN CIS_COURSE_CATALOG ccc ON sd.DEPARTMENT_CODE = ccc.DEPARTMENT_CODE
    WHERE scd.IS_DEGREE_GRANTING = 'Y'
      AND ccc.TOTAL_UNITS > 6
    GROUP BY scd.DEPARTMENT_NAME, scd.COURSE_LEVEL
),
subject_stats AS (
    SELECT d.DEPARTMENT_NAME,
           s.SUBJECT_CODE,
           COUNT(s.SUBJECT_CODE) AS subject_code_count,
           MIN(d.DEPT_BUDGET_CODE) AS min_dept_budget_code,
           d.DEPARTMENT_FULL_NAME
    FROM SIS_DEPARTMENT d
    JOIN SIS_SUBJECT_CODE s ON d.DEPARTMENT_CODE = s.DEPARTMENT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
    GROUP BY d.DEPARTMENT_NAME, s.SUBJECT_CODE, d.DEPARTMENT_FULL_NAME
)
SELECT cs.DEPARTMENT_NAME,
       cs.COURSE_LEVEL,
       cs.course_count,
       cs.min_total_units,
       cs.avg_total_units,
       ss.SUBJECT_CODE,
       ss.subject_code_count,
       ss.min_dept_budget_code,
       ss.DEPARTMENT_FULL_NAME
FROM course_stats cs
JOIN subject_stats ss ON cs.DEPARTMENT_NAME = ss.DEPARTMENT_NAME