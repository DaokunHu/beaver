WITH current_term_units AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           ccso.DEPARTMENT_NAME,
           ccso.TOTAL_UNITS
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN ACADEMIC_TERMS_ALL ata ON ccso.TERM_CODE = ata.TERM_CODE
    WHERE ata.IS_CURRENT_TERM = 'Y'
),
dept_cv AS (
    SELECT ACADEMIC_YEAR,
           ACADEMIC_YEAR_DESC,
           DEPARTMENT_NAME,
           STDDEV(TOTAL_UNITS) / AVG(TOTAL_UNITS) AS coefficient_of_variation_total_units
    FROM current_term_units
    GROUP BY ACADEMIC_YEAR, ACADEMIC_YEAR_DESC, DEPARTMENT_NAME
),
grand_cv AS (
    SELECT ACADEMIC_YEAR,
           ACADEMIC_YEAR_DESC,
           NULL AS DEPARTMENT_NAME,
           STDDEV(TOTAL_UNITS) / AVG(TOTAL_UNITS) AS coefficient_of_variation_total_units
    FROM current_term_units
    GROUP BY ACADEMIC_YEAR, ACADEMIC_YEAR_DESC
),
dept_2008_stats AS (
    SELECT ccso.DEPARTMENT_NAME,
           AVG(ccso.TOTAL_UNITS) AS avg_total_units,
           MAX(ccso.TOTAL_UNITS) - MIN(ccso.TOTAL_UNITS) AS total_units_range,
           VARIANCE(ccso.TOTAL_UNITS) AS total_units_variance
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN SIS_DEPARTMENT sd ON ccso.DEPARTMENT_CODE = sd.DEPARTMENT_CODE
    WHERE ccso.ACADEMIC_YEAR = 2008
      AND sd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_NAME <> 'Chemistry'
    GROUP BY ccso.DEPARTMENT_NAME
    ORDER BY avg_total_units DESC
    LIMIT 1
)
SELECT d.ACADEMIC_YEAR,
       d.ACADEMIC_YEAR_DESC,
       d.DEPARTMENT_NAME,
       d.coefficient_of_variation_total_units,
       t.avg_total_units,
       t.total_units_range,
       t.total_units_variance
FROM dept_cv d
LEFT JOIN dept_2008_stats t ON d.DEPARTMENT_NAME = t.DEPARTMENT_NAME
UNION ALL
SELECT g.ACADEMIC_YEAR,
       g.ACADEMIC_YEAR_DESC,
       g.DEPARTMENT_NAME,
       g.coefficient_of_variation_total_units,
       NULL,
       NULL,
       NULL
FROM grand_cv g
ORDER BY ACADEMIC_YEAR, DEPARTMENT_NAME