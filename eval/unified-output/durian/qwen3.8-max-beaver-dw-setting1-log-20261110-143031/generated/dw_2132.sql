WITH tip_subjects AS (
    SELECT
        t.SUBJECT_ID,
        t.SUBJECT_TITLE,
        t.OFFER_DEPT_CODE,
        t.OFFER_DEPT_NAME,
        t.NUM_ENROLLED_STUDENTS,
        sd.DEPARTMENT_FULL_NAME,
        sd.SCHOOL_NAME,
        MIN(t.NUM_ENROLLED_STUDENTS) OVER (PARTITION BY t.OFFER_DEPT_CODE) AS min_num_enrolled
    FROM TIP_SUBJECT_OFFERED t
    JOIN STUDENT_DEPARTMENT sd
        ON t.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    WHERE t.TERM_CODE = '2017JA'
      AND t.OFFER_DEPT_NAME = 'Chemistry'
      AND t.OFFER_DEPT_CODE = '5'
),
dept_units_variance AS (
    SELECT
        d.DEPARTMENT_CODE,
        d.DEPARTMENT_NAME,
        VARIANCE(sos.TOTAL_UNITS) AS total_units_variance
    FROM SIS_DEPARTMENT d
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
        ON ccso.DEPARTMENT_CODE = d.DEPARTMENT_CODE
    JOIN SUBJECT_OFFERED_SUMMARY sos
        ON sos.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
    WHERE ccso.ACADEMIC_YEAR = 2022
      AND d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_CODE <> '7'
    GROUP BY d.DEPARTMENT_CODE, d.DEPARTMENT_NAME
),
dept_avg_enrolled AS (
    SELECT
        d.DEPARTMENT_CODE,
        AVG(sos.NUM_ENROLLED_STUDENTS) AS avg_num_enrolled
    FROM SUBJECT_OFFERED_SUMMARY sos
    JOIN SIS_DEPARTMENT d
        ON sos.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
    WHERE sos.TERM_CODE LIKE '2022%'
      AND d.IS_DEGREE_GRANTING = 'Y'
    GROUP BY d.DEPARTMENT_CODE
)
SELECT
    ts.SUBJECT_ID,
    ts.SUBJECT_TITLE,
    ts.OFFER_DEPT_CODE,
    ts.OFFER_DEPT_NAME,
    ts.NUM_ENROLLED_STUDENTS,
    ts.DEPARTMENT_FULL_NAME,
    ts.SCHOOL_NAME,
    ts.min_num_enrolled,
    dv.DEPARTMENT_NAME,
    dv.total_units_variance,
    da.avg_num_enrolled
FROM tip_subjects ts
JOIN dept_units_variance dv
    ON ts.OFFER_DEPT_CODE = dv.DEPARTMENT_CODE
JOIN dept_avg_enrolled da
    ON ts.OFFER_DEPT_CODE = da.DEPARTMENT_CODE
ORDER BY ts.OFFER_DEPT_CODE DESC, dv.total_units_variance DESC