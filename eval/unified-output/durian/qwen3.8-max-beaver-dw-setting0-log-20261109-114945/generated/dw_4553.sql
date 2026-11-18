WITH current_terms AS (
    SELECT t.TERM_CODE, t.TERM_DESCRIPTION, t.ACADEMIC_YEAR, t.ACADEMIC_YEAR_DESC
    FROM ACADEMIC_TERMS t
    WHERE t.IS_CURRENT_TERM = 'Y'
),
term_stats AS (
    SELECT ct.TERM_CODE,
           ct.TERM_DESCRIPTION,
           ct.ACADEMIC_YEAR,
           ct.ACADEMIC_YEAR_DESC,
           COUNT(DISTINCT s.SUBJECT_ID) AS subject_count,
           SUM(s.SUBJECT_ENROLLMENT_NUMBER) AS total_enrollment
    FROM current_terms ct
    JOIN SUBJECT_OFFERED_SUMMARY s ON ct.TERM_CODE = s.TERM_CODE
    GROUP BY ct.TERM_CODE, ct.TERM_DESCRIPTION, ct.ACADEMIC_YEAR, ct.ACADEMIC_YEAR_DESC
),
dept_year_counts AS (
    SELECT ta.ACADEMIC_YEAR,
           s.OFFER_DEPT_NAME,
           COUNT(DISTINCT s.SUBJECT_ID) AS dept_subject_count,
           ROW_NUMBER() OVER (PARTITION BY ta.ACADEMIC_YEAR
                              ORDER BY COUNT(DISTINCT s.SUBJECT_ID) DESC, s.OFFER_DEPT_NAME) AS rn
    FROM SUBJECT_OFFERED_SUMMARY s
    JOIN ACADEMIC_TERMS_ALL ta ON s.TERM_CODE = ta.TERM_CODE
    GROUP BY ta.ACADEMIC_YEAR, s.OFFER_DEPT_NAME
)
SELECT ts.TERM_CODE,
       ts.TERM_DESCRIPTION,
       ts.ACADEMIC_YEAR,
       ts.subject_count,
       ts.total_enrollment,
       ts.ACADEMIC_YEAR_DESC,
       dyc.OFFER_DEPT_NAME AS most_prominent_department,
       dyc.dept_subject_count
FROM term_stats ts
JOIN dept_year_counts dyc ON ts.ACADEMIC_YEAR = dyc.ACADEMIC_YEAR AND dyc.rn = 1
ORDER BY ts.TERM_CODE