WITH course_stats AS (
    SELECT ic.DEPARTMENT_NAME,
           ic.COURSE_LEVEL,
           ic.course_count,
           ic.min_total_units,
           COUNT(DISTINCT CASE WHEN ccc.DESIGN_UNITS >= 3 THEN scd.COURSE END) AS courses_with_design_units_3_or_more
    FROM (
        SELECT scd.DEPARTMENT_NAME,
               scd.COURSE_LEVEL,
               COUNT(DISTINCT scd.COURSE) AS course_count,
               MIN(ccc.TOTAL_UNITS) AS min_total_units
        FROM SIS_COURSE_DESCRIPTION scd
        JOIN SIS_DEPARTMENT sd ON scd.DEPARTMENT = sd.DEPARTMENT_CODE
        JOIN CIS_COURSE_CATALOG ccc ON sd.DEPARTMENT_CODE = ccc.DEPARTMENT_CODE
        WHERE scd.IS_DEGREE_GRANTING = 'Y'
          AND ccc.TOTAL_UNITS > 6
        GROUP BY scd.DEPARTMENT_NAME, scd.COURSE_LEVEL
    ) ic
    JOIN SIS_COURSE_DESCRIPTION scd
        ON ic.DEPARTMENT_NAME = scd.DEPARTMENT_NAME
       AND ic.COURSE_LEVEL = scd.COURSE_LEVEL
    JOIN SIS_DEPARTMENT sd ON scd.DEPARTMENT = sd.DEPARTMENT_CODE
    JOIN CIS_COURSE_CATALOG ccc ON sd.DEPARTMENT_CODE = ccc.DEPARTMENT_CODE
    WHERE scd.IS_DEGREE_GRANTING = 'Y'
      AND ccc.TOTAL_UNITS > 6
    GROUP BY ic.DEPARTMENT_NAME, ic.COURSE_LEVEL, ic.course_count, ic.min_total_units
),
subject_rows AS (
    SELECT at.ACADEMIC_YEAR,
           at.ACADEMIC_YEAR_DESC,
           ccso.DEPARTMENT_NAME,
           ccso.SUBJECT_ID,
           ccso.TOTAL_UNITS
    FROM ACADEMIC_TERMS at
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
        ON at.TERM_CODE = ccso.EFFECTIVE_TERM_CODE
    WHERE at.IS_REGULAR_TERM = 'Y'
),
dept_year_stats AS (
    SELECT DEPARTMENT_NAME,
           ACADEMIC_YEAR,
           AVG(TOTAL_UNITS) AS avg_total_units,
           STDDEV(TOTAL_UNITS) AS stddev_total_units
    FROM subject_rows
    GROUP BY DEPARTMENT_NAME, ACADEMIC_YEAR
)
SELECT cs.DEPARTMENT_NAME,
       cs.COURSE_LEVEL,
       cs.course_count,
       cs.min_total_units,
       cs.courses_with_design_units_3_or_more,
       sr.ACADEMIC_YEAR,
       sr.ACADEMIC_YEAR_DESC,
       sr.SUBJECT_ID,
       sr.TOTAL_UNITS,
       dys.avg_total_units,
       dys.stddev_total_units,
       (sr.TOTAL_UNITS - dys.avg_total_units) AS deviation_from_dept_avg
FROM course_stats cs
JOIN dept_year_stats dys ON cs.DEPARTMENT_NAME = dys.DEPARTMENT_NAME
JOIN subject_rows sr
    ON sr.DEPARTMENT_NAME = dys.DEPARTMENT_NAME
   AND sr.ACADEMIC_YEAR = dys.ACADEMIC_YEAR