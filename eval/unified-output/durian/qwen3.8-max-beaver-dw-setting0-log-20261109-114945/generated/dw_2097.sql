WITH dept_avg AS (
    SELECT d.DEPARTMENT_NAME,
           AVG(s.NUM_ENROLLED_STUDENTS) AS avg_enrolled_students_per_subject
    FROM SIS_DEPARTMENT d
    JOIN SUBJECT_OFFERED_SUMMARY s
        ON d.DEPARTMENT_CODE = s.OFFER_DEPT_CODE
    WHERE s.TERM_CODE = '2022FA'
      AND d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_NAME <> 'Electrical Eng & Computer Sci'
    GROUP BY d.DEPARTMENT_NAME
)
SELECT da.DEPARTMENT_NAME,
       da.avg_enrolled_students_per_subject
FROM dept_avg da
WHERE da.avg_enrolled_students_per_subject > (
    SELECT AVG(avg_enrolled_students_per_subject) FROM dept_avg
)