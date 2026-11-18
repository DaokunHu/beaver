WITH variance_cte AS (
    SELECT at.ACADEMIC_YEAR,
           at.ACADEMIC_YEAR_DESC,
           VARIANCE(td.RECORD_COUNT) AS record_count_variance
    FROM TIP_DETAIL td
    JOIN ACADEMIC_TERMS at ON td.TERM_CODE = at.TERM_CODE
    WHERE at.TERM_STATUS IN ('Current', 'Previous')
    GROUP BY at.ACADEMIC_YEAR, at.ACADEMIC_YEAR_DESC
),
geo_cte AS (
    SELECT at.ACADEMIC_YEAR,
           EXP(AVG(LN(td.RECORD_COUNT))) AS geometric_mean_record_count
    FROM TIP_DETAIL td
    JOIN ACADEMIC_TERMS at ON td.TERM_CODE = at.TERM_CODE
    WHERE td.TIP_MATERIAL_STATUS_KEY = 'RQ'
      AND td.RECORD_COUNT > 0
    GROUP BY at.ACADEMIC_YEAR
),
dept_cte AS (
    SELECT at.ACADEMIC_YEAR,
           COUNT(DISTINCT tso.OFFER_DEPT_CODE) AS unique_departments
    FROM TIP_SUBJECT_OFFERED tso
    JOIN ACADEMIC_TERMS at ON tso.TERM_CODE = at.TERM_CODE
    GROUP BY at.ACADEMIC_YEAR
)
SELECT v.ACADEMIC_YEAR,
       v.ACADEMIC_YEAR_DESC,
       v.record_count_variance,
       g.geometric_mean_record_count,
       d.unique_departments
FROM variance_cte v
JOIN geo_cte g ON v.ACADEMIC_YEAR = g.ACADEMIC_YEAR
JOIN dept_cte d ON v.ACADEMIC_YEAR = d.ACADEMIC_YEAR
ORDER BY v.record_count_variance DESC