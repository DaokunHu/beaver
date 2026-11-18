WITH units_stats AS (
    SELECT
        ata.ACADEMIC_YEAR,
        ccso.DEPARTMENT_NAME,
        VARIANCE(ss.TOTAL_UNITS) AS total_units_variance,
        STDDEV(ss.TOTAL_UNITS) AS total_units_stddev
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN ACADEMIC_TERMS_ALL ata ON ccso.TERM_CODE = ata.TERM_CODE
    JOIN SUBJECT_SUMMARY ss ON ata.TERM_CODE = ss.TERM_CODE
    WHERE ata.IS_CURRENT_TERM = 'Y'
      AND ss.TOTAL_UNITS > 0
      AND ccso.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY ata.ACADEMIC_YEAR, ccso.DEPARTMENT_NAME
),
clearing_stats AS (
    SELECT
        AVG(sad.CLEARING_COST_COLLECTOR) AS avg_clearing_cost_collector,
        STDDEV(sad.CLEARING_COST_COLLECTOR) AS stddev_clearing_cost_collector
    FROM SIS_DEPARTMENT sd
    JOIN SIS_ADMIN_DEPARTMENT sad ON sd.DEPARTMENT_CODE = sad.SIS_ADMIN_DEPARTMENT_CODE
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_CODE <> '17'
)
SELECT
    us.ACADEMIC_YEAR,
    us.DEPARTMENT_NAME,
    us.total_units_variance,
    us.total_units_stddev,
    cs.avg_clearing_cost_collector,
    cs.stddev_clearing_cost_collector
FROM units_stats us
CROSS JOIN clearing_stats cs