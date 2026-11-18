WITH dept_material_stats AS (
    SELECT
        t0.OFFER_DEPT_NAME,
        AVG(t0.NUM_ENROLLED_STUDENTS) AS avg_enrolled_students,
        STDDEV(t0.NUM_ENROLLED_STUDENTS) AS stddev_enrolled_students
    FROM TIP_SUBJECT_OFFERED t0
    JOIN TIP_DETAIL t1 ON t0.SUBJECT_ID = t1.SUBJECT_ID
    WHERE t1.TIP_MATERIAL_STATUS_KEY != 'NM'
    GROUP BY t0.OFFER_DEPT_NAME
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
    WHERE t1.SCHOOL_NAME = 'Engineering' AND t1.TOTAL_UNITS = 1
)
SELECT
    d.OFFER_DEPT_NAME,
    d.avg_enrolled_students,
    d.stddev_enrolled_students,
    e.SUBJECT_ID,
    e.SUBJECT_TITLE,
    e.DEPARTMENT_NAME,
    e.ACADEMIC_YEAR,
    e.subject_rank,
    e.TERM_DESCRIPTION
FROM dept_material_stats d
JOIN eng_subjects e ON d.OFFER_DEPT_NAME = e.DEPARTMENT_NAME
ORDER BY d.stddev_enrolled_students DESC, e.ACADEMIC_YEAR, e.subject_rank