WITH enrolled_stats AS (
    SELECT sd.DEPARTMENT_NAME,
           MAX(tso.NUM_ENROLLED_STUDENTS) - MIN(tso.NUM_ENROLLED_STUDENTS) AS enrolled_students_range,
           VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrolled_students_variance
    FROM TIP_SUBJECT_OFFERED tso
    JOIN SIS_DEPARTMENT sd ON tso.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    JOIN SIS_COURSE_DESCRIPTION scd ON sd.DEPARTMENT_CODE = scd.DEPARTMENT
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND scd.COURSE_LEVEL = 'G'
      AND sd.DEPARTMENT_NAME NOT IN ('Biology', 'Chemistry')
    GROUP BY sd.DEPARTMENT_NAME
),
units_stats AS (
    SELECT scd.DEPARTMENT_NAME,
           MAX(sos.TOTAL_UNITS) - MIN(sos.TOTAL_UNITS) AS total_units_range,
           VARIANCE(sos.TOTAL_UNITS) AS total_units_variance,
           STDDEV(sos.TOTAL_UNITS) AS total_units_stddev
    FROM SIS_COURSE_DESCRIPTION scd
    JOIN SUBJECT_OFFERED_SUMMARY sos ON scd.COURSE = sos.COURSE_NUMBER
    WHERE sos.TOTAL_UNITS > 0
    GROUP BY scd.DEPARTMENT_NAME
)
SELECT e.DEPARTMENT_NAME,
       e.enrolled_students_range,
       e.enrolled_students_variance,
       u.total_units_range,
       u.total_units_variance,
       u.total_units_stddev
FROM enrolled_stats e
JOIN units_stats u ON e.DEPARTMENT_NAME = u.DEPARTMENT_NAME
ORDER BY e.DEPARTMENT_NAME