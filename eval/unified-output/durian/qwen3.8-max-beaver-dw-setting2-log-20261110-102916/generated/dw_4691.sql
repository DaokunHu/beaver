WITH DeptEnrollmentStats AS (
    SELECT tso.OFFER_DEPT_NAME,
           AVG(tso.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
           STDDEV(tso.NUM_ENROLLED_STUDENTS) AS enrollment_stddev
    FROM TIP_SUBJECT_OFFERED tso
    JOIN TIP_DETAIL td ON tso.SUBJECT_ID = td.SUBJECT_ID
    WHERE td.TIP_MATERIAL_STATUS_KEY <> 'NM'
    GROUP BY tso.OFFER_DEPT_NAME
),
EngineeringSubjects AS (
    SELECT t1.SUBJECT_ID,
           t1.SUBJECT_TITLE,
           t1.DEPARTMENT_NAME,
           t2.ACADEMIC_YEAR,
           RANK() OVER (PARTITION BY t2.ACADEMIC_YEAR ORDER BY t1.SUBJECT_ID) AS window_column,
           t2.TERM_DESCRIPTION,
           t1.TERM_CODE
    FROM SUBJECT_SUMMARY t1
    INNER JOIN ACADEMIC_TERMS_ALL t0 ON t0.TERM_CODE = t1.TERM_CODE
    INNER JOIN ACADEMIC_TERMS t2 ON t1.TERM_CODE = t2.TERM_CODE
    WHERE t1.SCHOOL_NAME = 'Engineering' AND t1.TOTAL_UNITS = 1
)
SELECT des.OFFER_DEPT_NAME,
       des.avg_enrollment,
       des.enrollment_stddev,
       es.SUBJECT_ID,
       es.SUBJECT_TITLE,
       es.DEPARTMENT_NAME,
       es.ACADEMIC_YEAR,
       es.window_column,
       es.TERM_DESCRIPTION
FROM DeptEnrollmentStats des
JOIN EngineeringSubjects es ON des.OFFER_DEPT_NAME = es.DEPARTMENT_NAME
ORDER BY des.enrollment_stddev DESC, es.ACADEMIC_YEAR, es.window_column;