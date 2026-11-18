WITH school_geo AS (
    SELECT sd.SCHOOL_NAME,
           EXP(AVG(LN(ccso.TOTAL_UNITS))) AS geometric_mean_total_units
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN SIS_DEPARTMENT sd ON ccso.DEPARTMENT_CODE = sd.DEPARTMENT_CODE
    WHERE ccso.TOTAL_UNITS > 0
      AND ccso.IS_OFFERED_THIS_YEAR = 'Y'
      AND sd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_NAME <> 'Management'
    GROUP BY sd.SCHOOL_NAME
),
overall_stats AS (
    SELECT AVG(geometric_mean_total_units) AS overall_avg_geometric_mean
    FROM school_geo
),
cip_stats AS (
    SELECT VARIANCE(CIP_PROGRAM_CODE) AS cip_program_code_variance
    FROM SIS_COURSE_DESCRIPTION
    WHERE IS_DEGREE_GRANTING = 'Y'
      AND DEPARTMENT_NAME IS NOT NULL
      AND DEPARTMENT = '18'
),
school_dept_combos AS (
    SELECT SCHOOL_NAME, DEPARTMENT_NAME
    FROM SIS_DEPARTMENT
    GROUP BY SCHOOL_NAME, DEPARTMENT_NAME
    UNION ALL
    SELECT SCHOOL_NAME, NULL AS DEPARTMENT_NAME
    FROM SIS_DEPARTMENT
    GROUP BY SCHOOL_NAME
)
SELECT c.SCHOOL_NAME,
       c.DEPARTMENT_NAME,
       cs.cip_program_code_variance,
       sg.geometric_mean_total_units,
       os.overall_avg_geometric_mean,
       CASE
           WHEN sg.geometric_mean_total_units > os.overall_avg_geometric_mean * 1.05 THEN 'ABOVE_AVERAGE'
           WHEN sg.geometric_mean_total_units < os.overall_avg_geometric_mean * 0.95 THEN 'BELOW_AVERAGE'
           ELSE 'AVERAGE'
       END AS geometric_mean_category
FROM school_dept_combos c
LEFT JOIN school_geo sg ON c.SCHOOL_NAME = sg.SCHOOL_NAME
CROSS JOIN overall_stats os
CROSS JOIN cip_stats cs
ORDER BY c.SCHOOL_NAME, c.DEPARTMENT_NAME;