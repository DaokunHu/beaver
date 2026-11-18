WITH math_grade_stats AS (
    SELECT
        d.DEPARTMENT_NAME,
        c.GRADE_TYPE,
        COUNT(c.SUBJECT_ID) AS subject_count,
        MIN(c.TOTAL_UNITS) AS min_total_units
    FROM SIS_DEPARTMENT d
    JOIN COURSE_CATALOG_SUBJECT_OFFERED c
        ON d.DEPARTMENT_CODE = c.DEPARTMENT_CODE
    WHERE c.IS_OFFERED_THIS_YEAR = 'Y'
      AND c.GRADE_TYPE = 'L'
      AND d.DEPARTMENT_NAME = 'Mathematics'
      AND d.DEPARTMENT_CODE = '18'
    GROUP BY d.DEPARTMENT_NAME, c.GRADE_TYPE
),
top10_depts_2022 AS (
    SELECT
        d.DEPARTMENT_NAME,
        COUNT(c.SUBJECT_ID) AS subjects_offered_2022
    FROM SIS_DEPARTMENT d
    JOIN COURSE_CATALOG_SUBJECT_OFFERED c
        ON d.DEPARTMENT_CODE = c.DEPARTMENT_CODE
    WHERE c.ACADEMIC_YEAR = 2022
      AND d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_CODE <> '17'
    GROUP BY d.DEPARTMENT_NAME
    ORDER BY subjects_offered_2022 DESC
    LIMIT 10
)
SELECT
    m.DEPARTMENT_NAME,
    m.GRADE_TYPE,
    m.subject_count,
    m.min_total_units,
    t.subjects_offered_2022
FROM math_grade_stats m
LEFT JOIN top10_depts_2022 t
    ON m.DEPARTMENT_NAME = t.DEPARTMENT_NAME