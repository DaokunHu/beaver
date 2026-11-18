WITH CurrentTermSubjects AS (
    SELECT atp.TERM_CODE,
           atp.TERM_DESCRIPTION,
           at.ACADEMIC_YEAR,
           at.ACADEMIC_YEAR_DESC,
           COUNT(ss.SUBJECT_ID) AS subject_count,
           SUM(ss.SUBJECT_ENROLLMENT_NUMBER) AS total_enrollment
    FROM ACADEMIC_TERM_PARAMETER atp
    JOIN ACADEMIC_TERMS at ON atp.TERM_CODE = at.TERM_CODE
    JOIN SUBJECT_SUMMARY ss ON at.TERM_CODE = ss.TERM_CODE
    WHERE atp.IS_CURRENT_TERM = 'Y'
    GROUP BY atp.TERM_CODE, atp.TERM_DESCRIPTION, at.ACADEMIC_YEAR, at.ACADEMIC_YEAR_DESC
),
YearDepartmentCounts AS (
    SELECT ata.ACADEMIC_YEAR,
           ss.DEPARTMENT_NAME,
           COUNT(ss.SUBJECT_ID) AS dept_subject_count,
           ROW_NUMBER() OVER (PARTITION BY ata.ACADEMIC_YEAR ORDER BY COUNT(ss.SUBJECT_ID) DESC) AS rn
    FROM ACADEMIC_TERMS_ALL ata
    JOIN SUBJECT_SUMMARY ss ON ata.TERM_CODE = ss.TERM_CODE
    GROUP BY ata.ACADEMIC_YEAR, ss.DEPARTMENT_NAME
),
YearTopDepartment AS (
    SELECT ACADEMIC_YEAR, DEPARTMENT_NAME, dept_subject_count
    FROM YearDepartmentCounts
    WHERE rn = 1
)
SELECT cts.TERM_CODE,
       cts.TERM_DESCRIPTION,
       cts.ACADEMIC_YEAR,
       cts.subject_count,
       cts.total_enrollment,
       cts.ACADEMIC_YEAR_DESC,
       ytd.DEPARTMENT_NAME,
       ytd.dept_subject_count
FROM CurrentTermSubjects cts
JOIN YearTopDepartment ytd ON cts.ACADEMIC_YEAR = ytd.ACADEMIC_YEAR
ORDER BY cts.TERM_CODE