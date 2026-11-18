WITH current_terms AS (
    SELECT p.TERM_CODE,
           p.TERM_DESCRIPTION,
           t.ACADEMIC_YEAR,
           t.ACADEMIC_YEAR_DESC
    FROM ACADEMIC_TERM_PARAMETER p
    JOIN ACADEMIC_TERMS t ON p.TERM_CODE = t.TERM_CODE
    WHERE p.IS_CURRENT_TERM = 'Y'
),
term_stats AS (
    SELECT s.TERM_CODE,
           COUNT(s.SUBJECT_ID) AS subject_count,
           SUM(s.SUBJECT_ENROLLMENT_NUMBER) AS total_enrollment
    FROM SUBJECT_SUMMARY s
    GROUP BY s.TERM_CODE
),
dept_year_stats AS (
    SELECT ta.ACADEMIC_YEAR,
           s.DEPARTMENT_NAME,
           COUNT(s.SUBJECT_ID) AS dept_subject_count,
           ROW_NUMBER() OVER (PARTITION BY ta.ACADEMIC_YEAR ORDER BY COUNT(s.SUBJECT_ID) DESC) AS rn
    FROM SUBJECT_SUMMARY s
    JOIN ACADEMIC_TERMS_ALL ta ON s.TERM_CODE = ta.TERM_CODE
    GROUP BY ta.ACADEMIC_YEAR, s.DEPARTMENT_NAME
)
SELECT ct.TERM_CODE,
       ct.TERM_DESCRIPTION,
       ct.ACADEMIC_YEAR,
       ts.subject_count,
       ts.total_enrollment,
       ct.ACADEMIC_YEAR_DESC,
       d.DEPARTMENT_NAME,
       d.dept_subject_count
FROM current_terms ct
JOIN term_stats ts ON ct.TERM_CODE = ts.TERM_CODE
JOIN dept_year_stats d ON ct.ACADEMIC_YEAR = d.ACADEMIC_YEAR AND d.rn = 1
ORDER BY ct.TERM_CODE;