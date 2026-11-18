WITH CurrentTermCV AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           ccso.DEPARTMENT_NAME,
           STDDEV(ccso.TOTAL_UNITS) / NULLIF(AVG(ccso.TOTAL_UNITS), 0) AS total_coefficient_of_variation
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN ACADEMIC_TERMS_ALL ata ON ata.TERM_CODE = ccso.TERM_CODE
    JOIN ACADEMIC_TERM_PARAMETER atp ON atp.TERM_CODE = ata.TERM_CODE
    WHERE atp.IS_CURRENT_TERM = 'Y'
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC, ccso.DEPARTMENT_NAME
),
GrandTotalCV AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           STDDEV(ccso.TOTAL_UNITS) / NULLIF(AVG(ccso.TOTAL_UNITS), 0) AS total_coefficient_of_variation
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN ACADEMIC_TERMS_ALL ata ON ata.TERM_CODE = ccso.TERM_CODE
    JOIN ACADEMIC_TERM_PARAMETER atp ON atp.TERM_CODE = ata.TERM_CODE
    WHERE atp.IS_CURRENT_TERM = 'Y'
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
),
TopDept2008 AS (
    SELECT sd.DEPARTMENT_NAME,
           AVG(ccc.TOTAL_UNITS) AS avg_total_units,
           MAX(ccc.TOTAL_UNITS) - MIN(ccc.TOTAL_UNITS) AS total_units_range,
           VARIANCE(ccc.TOTAL_UNITS) AS total_units_variance
    FROM CIS_COURSE_CATALOG ccc
    JOIN SIS_DEPARTMENT sd ON ccc.DEPARTMENT_CODE = sd.DEPARTMENT_CODE
    WHERE ccc.ACADEMIC_YEAR = '2008'
      AND sd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_CODE <> '5'
    GROUP BY sd.DEPARTMENT_NAME
    ORDER BY avg_total_units DESC
    LIMIT 1
)
SELECT c.ACADEMIC_YEAR,
       c.ACADEMIC_YEAR_DESC,
       c.DEPARTMENT_NAME,
       c.total_coefficient_of_variation,
       t.avg_total_units,
       t.total_units_range,
       t.total_units_variance
FROM CurrentTermCV c
LEFT JOIN TopDept2008 t ON c.DEPARTMENT_NAME = t.DEPARTMENT_NAME
UNION ALL
SELECT g.ACADEMIC_YEAR,
       g.ACADEMIC_YEAR_DESC,
       NULL,
       g.total_coefficient_of_variation,
       NULL,
       NULL,
       NULL
FROM GrandTotalCV g
ORDER BY ACADEMIC_YEAR, DEPARTMENT_NAME