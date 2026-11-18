WITH inner_cte AS (
    SELECT s.SCHOOL_NAME,
           c.DEPARTMENT_NAME,
           VARIANCE(c.CIP_PROGRAM_CODE) AS cip_code_variance
    FROM SIS_SUBJECT_CODE s
    JOIN SIS_COURSE_DESCRIPTION c ON s.SUBJECT_CODE = c.COURSE
    WHERE c.IS_DEGREE_GRANTING = 'Y'
      AND c.DEPARTMENT_NAME IS NOT NULL
      AND c.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY s.SCHOOL_NAME, c.DEPARTMENT_NAME
),
rollup_cte AS (
    SELECT SCHOOL_NAME, DEPARTMENT_NAME, cip_code_variance
    FROM inner_cte
    UNION ALL
    SELECT s.SCHOOL_NAME,
           NULL AS DEPARTMENT_NAME,
           VARIANCE(c.CIP_PROGRAM_CODE) AS cip_code_variance
    FROM SIS_SUBJECT_CODE s
    JOIN SIS_COURSE_DESCRIPTION c ON s.SUBJECT_CODE = c.COURSE
    WHERE c.IS_DEGREE_GRANTING = 'Y'
      AND c.DEPARTMENT_NAME IS NOT NULL
    GROUP BY s.SCHOOL_NAME
),
geo_cte AS (
    SELECT sd.SCHOOL_NAME,
           EXP(AVG(LOG(ccso.TOTAL_UNITS))) AS geometric_mean_total_units
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN SIS_DEPARTMENT sd ON ccso.DEPARTMENT_CODE = sd.DEPARTMENT_CODE
    WHERE ccso.TOTAL_UNITS > 0
      AND ccso.IS_OFFERED_THIS_YEAR = 'Y'
      AND sd.IS_DEGREE_GRANTING = 'Y'
      AND ccso.DEPARTMENT_CODE <> '15'
    GROUP BY sd.SCHOOL_NAME
)
SELECT r.SCHOOL_NAME,
       r.DEPARTMENT_NAME,
       r.cip_code_variance,
       g.geometric_mean_total_units,
       s.avg_geometric_mean,
       CASE
           WHEN g.geometric_mean_total_units > s.avg_geometric_mean * 1.05 THEN 'ABOVE_AVERAGE'
           WHEN g.geometric_mean_total_units < s.avg_geometric_mean * 0.95 THEN 'BELOW_AVERAGE'
           ELSE 'AVERAGE'
       END AS comparison_to_average
FROM rollup_cte r
LEFT JOIN geo_cte g ON r.SCHOOL_NAME = g.SCHOOL_NAME
CROSS JOIN (SELECT AVG(geometric_mean_total_units) AS avg_geometric_mean FROM geo_cte) s
ORDER BY r.SCHOOL_NAME, r.DEPARTMENT_NAME