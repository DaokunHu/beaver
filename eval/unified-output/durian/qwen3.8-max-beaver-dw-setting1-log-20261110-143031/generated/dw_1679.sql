WITH school_dept_combos AS (
    SELECT ssc.SCHOOL_NAME, scd.DEPARTMENT_NAME
    FROM SIS_SUBJECT_CODE ssc
    JOIN SIS_COURSE_DESCRIPTION scd ON ssc.SUBJECT_CODE = scd.COURSE
    GROUP BY ssc.SCHOOL_NAME, scd.DEPARTMENT_NAME WITH ROLLUP
    HAVING ssc.SCHOOL_NAME IS NOT NULL
),
math_cip_variance AS (
    SELECT VARIANCE(scd.CIP_PROGRAM_CODE) AS cip_program_code_variance
    FROM SIS_COURSE_DESCRIPTION scd
    JOIN SIS_DEPARTMENT sd ON scd.DEPARTMENT = sd.DEPARTMENT_CODE
    WHERE scd.IS_DEGREE_GRANTING = 'Y'
      AND scd.DEPARTMENT_NAME IS NOT NULL
      AND scd.DEPARTMENT_NAME = 'Mathematics'
),
school_geometric_mean AS (
    SELECT sd.SCHOOL_NAME,
           EXP(AVG(LN(ccso.TOTAL_UNITS))) AS geometric_mean_total_units
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN SIS_DEPARTMENT sd ON ccso.DEPARTMENT_CODE = sd.DEPARTMENT_CODE
    WHERE ccso.TOTAL_UNITS > 0
      AND ccso.IS_OFFERED_THIS_YEAR = 'Y'
      AND sd.IS_DEGREE_GRANTING = 'Y'
      AND ccso.DEPARTMENT_CODE <> '15'
    GROUP BY sd.SCHOOL_NAME
),
overall_avg AS (
    SELECT AVG(geometric_mean_total_units) AS overall_average_geometric_mean
    FROM school_geometric_mean
)
SELECT c.SCHOOL_NAME,
       c.DEPARTMENT_NAME,
       m.cip_program_code_variance,
       g.geometric_mean_total_units,
       o.overall_average_geometric_mean,
       CASE WHEN g.geometric_mean_total_units > o.overall_average_geometric_mean * 1.05 THEN 'ABOVE_AVERAGE'
            WHEN g.geometric_mean_total_units < o.overall_average_geometric_mean * 0.95 THEN 'BELOW_AVERAGE'
            ELSE 'AVERAGE' END AS comparison_to_average
FROM school_dept_combos c
CROSS JOIN math_cip_variance m
LEFT JOIN school_geometric_mean g ON c.SCHOOL_NAME = g.SCHOOL_NAME
CROSS JOIN overall_avg o
ORDER BY c.SCHOOL_NAME, c.DEPARTMENT_NAME