WITH Branch1 AS (
    SELECT
        scd.DEPARTMENT_NAME AS DEPARTMENT_NAME,
        AVG(sos.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
        VARIANCE(sos.NUM_ENROLLED_STUDENTS) AS enrollment_variance,
        NULL AS coefficient_of_variation,
        COUNT(sos.SUBJECT_ID) AS total_subjects_offered,
        'Avg/Var' AS reason
    FROM SIS_COURSE_DESCRIPTION scd
    JOIN SUBJECT_OFFERED_SUMMARY sos
        ON scd.COURSE = sos.COURSE_NUMBER
    WHERE scd.IS_DEGREE_GRANTING = 'Y'
      AND scd.DEPARTMENT_NAME <> 'Political Science'
    GROUP BY scd.DEPARTMENT_NAME
),
Branch2 AS (
    SELECT
        sd.DEPARTMENT_NAME AS DEPARTMENT_NAME,
        NULL AS avg_enrollment,
        NULL AS enrollment_variance,
        STDDEV(sos.NUM_ENROLLED_STUDENTS) / NULLIF(AVG(sos.NUM_ENROLLED_STUDENTS), 0) AS coefficient_of_variation,
        COUNT(sos.SUBJECT_ID) AS total_subjects_offered,
        'CoeffVar' AS reason
    FROM SIS_DEPARTMENT sd
    JOIN SUBJECT_OFFERED_SUMMARY sos
        ON sd.DEPARTMENT_CODE = sos.OFFER_DEPT_CODE
    WHERE sd.DEPARTMENT_NAME <> 'Chemistry'
    GROUP BY sd.DEPARTMENT_NAME
)
SELECT DEPARTMENT_NAME, avg_enrollment, enrollment_variance, coefficient_of_variation, total_subjects_offered, reason
FROM Branch1
UNION ALL
SELECT DEPARTMENT_NAME, avg_enrollment, enrollment_variance, coefficient_of_variation, total_subjects_offered, reason
FROM Branch2
ORDER BY DEPARTMENT_NAME, reason;