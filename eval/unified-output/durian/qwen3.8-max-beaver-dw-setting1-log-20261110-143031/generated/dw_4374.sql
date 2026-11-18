WITH branch1 AS (
    SELECT
        scd.DEPARTMENT_NAME,
        ccso.ACADEMIC_YEAR,
        ata.ACADEMIC_YEAR_DESC,
        COUNT(*) AS subject_count,
        AVG(ccso.TOTAL_UNITS) AS avg_total_units,
        MAX(ccso.TOTAL_UNITS) - MIN(ccso.TOTAL_UNITS) AS total_units_range,
        VARIANCE(ccso.TOTAL_UNITS) AS total_units_variance,
        NULL AS coefficient_of_variation,
        '2022 Degree-Granting Subjects' AS reason
    FROM SIS_SUBJECT_CODE ssc
    JOIN SIS_COURSE_DESCRIPTION scd ON ssc.COURSE_NUMBER = scd.COURSE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON ccso.SUBJECT_CODE = scd.COURSE
    JOIN ACADEMIC_TERMS_ALL ata ON ata.TERM_CODE = ccso.TERM_CODE
    WHERE ccso.ACADEMIC_YEAR = 2022
      AND scd.IS_DEGREE_GRANTING = 'Y'
    GROUP BY scd.DEPARTMENT_NAME, ccso.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
    HAVING COUNT(*) >= 5
),
branch2 AS (
    SELECT
        ccso.DEPARTMENT_NAME,
        ata.ACADEMIC_YEAR,
        ata.ACADEMIC_YEAR_DESC,
        NULL AS subject_count,
        NULL AS avg_total_units,
        NULL AS total_units_range,
        NULL AS total_units_variance,
        STDDEV(ccso.TOTAL_UNITS) / AVG(ccso.TOTAL_UNITS) AS coefficient_of_variation,
        'Library Reserve Materials' AS reason
    FROM LIBRARY_RESERVE_MATRL_DETAIL lrm
    JOIN ACADEMIC_TERMS_ALL ata ON ata.TERM_CODE = lrm.TERM_CODE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON ccso.TERM_CODE = ata.TERM_CODE
    WHERE lrm.LIBRARY_MATERIAL_STATUS_KEY = 'U'
    GROUP BY ccso.DEPARTMENT_NAME, ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
)
SELECT DEPARTMENT_NAME, ACADEMIC_YEAR, ACADEMIC_YEAR_DESC, subject_count,
       avg_total_units, total_units_range, total_units_variance,
       coefficient_of_variation, reason
FROM branch1
UNION ALL
SELECT DEPARTMENT_NAME, ACADEMIC_YEAR, ACADEMIC_YEAR_DESC, subject_count,
       avg_total_units, total_units_range, total_units_variance,
       coefficient_of_variation, reason
FROM branch2
ORDER BY DEPARTMENT_NAME