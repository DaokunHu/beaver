WITH variance_cte AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           VARIANCE(td.RECORD_COUNT) AS record_count_variance
    FROM TIP_DETAIL td
    JOIN ACADEMIC_TERMS_ALL ata ON td.TERM_CODE = ata.TERM_CODE
    JOIN ACADEMIC_TERM_PARAMETER atp ON ata.TERM_CODE = atp.TERM_CODE
    WHERE atp.TERM_PARAMETER IN ('SIS_CURRENT_TERM', 'SIS_PREVIOUS_TERM')
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
),
geo_cte AS (
    SELECT ata.ACADEMIC_YEAR,
           EXP(AVG(LN(td.RECORD_COUNT))) AS geometric_mean_record_count
    FROM TIP_DETAIL td
    JOIN ACADEMIC_TERMS_ALL ata ON td.TERM_CODE = ata.TERM_CODE
    WHERE td.TIP_MATERIAL_STATUS_KEY = 'RQ'
      AND td.RECORD_COUNT > 0
    GROUP BY ata.ACADEMIC_YEAR
),
dept_cte AS (
    SELECT ata.ACADEMIC_YEAR,
           COUNT(DISTINCT ccso.DEPARTMENT_CODE) AS unique_department_count
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN ACADEMIC_TERMS_ALL ata ON ccso.TERM_CODE = ata.TERM_CODE
    GROUP BY ata.ACADEMIC_YEAR
)
SELECT v.ACADEMIC_YEAR,
       v.ACADEMIC_YEAR_DESC,
       v.record_count_variance,
       g.geometric_mean_record_count,
       d.unique_department_count
FROM variance_cte v
JOIN geo_cte g ON v.ACADEMIC_YEAR = g.ACADEMIC_YEAR
JOIN dept_cte d ON v.ACADEMIC_YEAR = d.ACADEMIC_YEAR
ORDER BY v.record_count_variance DESC