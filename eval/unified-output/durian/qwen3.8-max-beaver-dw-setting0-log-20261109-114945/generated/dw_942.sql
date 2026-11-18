WITH unit_stats AS (
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
ccc_stats AS (
    SELECT
        d.DEPARTMENT_NAME,
        AVG(a.CLEARING_COST_COLLECTOR) AS avg_clearing_cost_collector,
        STDDEV(a.CLEARING_COST_COLLECTOR) AS stddev_clearing_cost_collector
    FROM SIS_DEPARTMENT d
    JOIN SIS_ADMIN_DEPARTMENT a ON d.DEPARTMENT_CODE = a.SIS_ADMIN_DEPARTMENT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_NAME <> 'Political Science'
    GROUP BY d.DEPARTMENT_NAME
)
SELECT
    u.ACADEMIC_YEAR,
    u.DEPARTMENT_NAME,
    u.total_units_variance,
    u.total_units_stddev,
    c.avg_clearing_cost_collector,
    c.stddev_clearing_cost_collector
FROM unit_stats u
JOIN ccc_stats c ON u.DEPARTMENT_NAME = c.DEPARTMENT_NAME
ORDER BY u.ACADEMIC_YEAR, u.DEPARTMENT_NAME;