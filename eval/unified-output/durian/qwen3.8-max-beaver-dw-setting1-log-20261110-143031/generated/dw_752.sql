WITH GradEnrollStats AS (
    SELECT
        sd.DEPARTMENT_NAME,
        MAX(tso.NUM_ENROLLED_STUDENTS) - MIN(tso.NUM_ENROLLED_STUDENTS) AS enrolled_students_range,
        VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrolled_students_variance
    FROM TIP_SUBJECT_OFFERED tso
    JOIN SIS_DEPARTMENT sd
        ON tso.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    JOIN SIS_COURSE_DESCRIPTION scd
        ON sd.DEPARTMENT_CODE = scd.DEPARTMENT
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND scd.COURSE_LEVEL = 'G'
      AND sd.DEPARTMENT_NAME NOT IN ('Biology', 'Chemistry')
    GROUP BY sd.DEPARTMENT_NAME
),
TotalUnitsStats AS (
    SELECT
        sd.DEPARTMENT_NAME,
        MAX(sos.TOTAL_UNITS) - MIN(sos.TOTAL_UNITS) AS total_units_range,
        VARIANCE(sos.TOTAL_UNITS) AS total_units_variance,
        STDDEV(sos.TOTAL_UNITS) AS total_units_stddev
    FROM SUBJECT_OFFERED_SUMMARY sos
    JOIN SIS_DEPARTMENT sd
        ON sos.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    JOIN SIS_SUBJECT_CODE ssc
        ON sd.DEPARTMENT_CODE = ssc.DEPARTMENT_CODE
    JOIN SIS_COURSE_DESCRIPTION scd
        ON sd.DEPARTMENT_CODE = scd.DEPARTMENT
       AND scd.COURSE = ssc.SUBJECT_CODE
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND scd.COURSE_LEVEL = 'G'
      AND sos.TOTAL_UNITS > 0
      AND sd.DEPARTMENT_NAME NOT IN ('Biology', 'Chemistry')
    GROUP BY sd.DEPARTMENT_NAME
)
SELECT
    g.DEPARTMENT_NAME,
    g.enrolled_students_range,
    g.enrolled_students_variance,
    t.total_units_range,
    t.total_units_variance,
    t.total_units_stddev
FROM GradEnrollStats g
JOIN TotalUnitsStats t
    ON g.DEPARTMENT_NAME = t.DEPARTMENT_NAME
ORDER BY g.DEPARTMENT_NAME;