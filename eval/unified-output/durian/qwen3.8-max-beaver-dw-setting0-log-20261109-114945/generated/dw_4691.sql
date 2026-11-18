WITH dept_stats AS (
    SELECT
        t.OFFER_DEPT_NAME AS DEPARTMENT_NAME,
        AVG(t.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
        STDDEV(t.NUM_ENROLLED_STUDENTS) AS enrollment_stddev
    FROM TIP_SUBJECT_OFFERED t
    WHERE t.IS_NO_COURSE_MATERIAL = 'N'
    GROUP BY t.OFFER_DEPT_NAME
),
eng_subjects AS (
    SELECT
        t1.SUBJECT_ID,
        t1.SUBJECT_TITLE,
        t1.DEPARTMENT_NAME,
        t2.ACADEMIC_YEAR,
        RANK() OVER (PARTITION BY t2.ACADEMIC_YEAR ORDER BY t1.SUBJECT_ID) AS subject_rank,
        t2.TERM_DESCRIPTION
    FROM SUBJECT_SUMMARY t1
    INNER JOIN ACADEMIC_TERMS_ALL t0 ON t0.TERM_CODE = t1.TERM_CODE
    INNER JOIN ACADEMIC_TERMS t2 ON t1.TERM_CODE = t2.TERM_CODE
    WHERE t1.SCHOOL_NAME = 'Engineering'
      AND t1.TOTAL_UNITS = 1
)
SELECT
    d.DEPARTMENT_NAME,
    d.avg_enrollment,
    d.enrollment_stddev,
    e.SUBJECT_ID,
    e.SUBJECT_TITLE,
    e.DEPARTMENT_NAME,
    e.ACADEMIC_YEAR,
    e.subject_rank,
    e.TERM_DESCRIPTION
FROM dept_stats d
JOIN eng_subjects e ON d.DEPARTMENT_NAME = e.DEPARTMENT_NAME
ORDER BY d.enrollment_stddev DESC, e.ACADEMIC_YEAR, e.subject_rank