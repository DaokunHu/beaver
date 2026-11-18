WITH UnitsBase AS (
    SELECT sd.SCHOOL_NAME, sd.DEPARTMENT_NAME, c.TOTAL_UNITS
    FROM SIS_DEPARTMENT sd
    JOIN COURSE_CATALOG_SUBJECT_OFFERED c ON sd.DEPARTMENT_CODE = c.DEPARTMENT_CODE
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND c.ACADEMIC_YEAR = 2022
      AND sd.DEPARTMENT_CODE <> '18'
),
DeptStats AS (
    SELECT SCHOOL_NAME,
           DEPARTMENT_NAME,
           AVG(TOTAL_UNITS) AS avg_total_units,
           MAX(TOTAL_UNITS) - MIN(TOTAL_UNITS) AS total_units_range,
           VARIANCE(TOTAL_UNITS) AS total_units_variance
    FROM UnitsBase
    GROUP BY SCHOOL_NAME, DEPARTMENT_NAME
),
SchoolRollup AS (
    SELECT SCHOOL_NAME,
           NULL AS DEPARTMENT_NAME,
           AVG(TOTAL_UNITS) AS avg_total_units,
           MAX(TOTAL_UNITS) - MIN(TOTAL_UNITS) AS total_units_range,
           VARIANCE(TOTAL_UNITS) AS total_units_variance
    FROM UnitsBase
    GROUP BY SCHOOL_NAME
),
UnitsStats AS (
    SELECT SCHOOL_NAME, DEPARTMENT_NAME, avg_total_units, total_units_range, total_units_variance,
           NULL AS total_enrollment, NULL AS most_popular_course, NULL AS course_enrollment,
           'UnitsStats' AS reason
    FROM (SELECT * FROM DeptStats UNION ALL SELECT * FROM SchoolRollup) u
),
EngEnrollment AS (
    SELECT s.DEPARTMENT_NAME, SUM(t.NUM_ENROLLED_STUDENTS) AS total_enrollment
    FROM SIS_DEPARTMENT s
    JOIN TIP_SUBJECT_OFFERED t ON s.DEPARTMENT_CODE = t.OFFER_DEPT_CODE
    JOIN STUDENT_DEPARTMENT d ON t.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
    WHERE s.SCHOOL_NAME = 'Engineering'
      AND s.IS_DEGREE_GRANTING = 'Y'
      AND s.DEPARTMENT_NAME <> 'Management'
    GROUP BY s.DEPARTMENT_NAME
    HAVING SUM(t.NUM_ENROLLED_STUDENTS) > 50
),
TopCourse AS (
    SELECT OFFER_DEPT_NAME, SUBJECT_TITLE, NUM_ENROLLED_STUDENTS,
           ROW_NUMBER() OVER (PARTITION BY OFFER_DEPT_NAME ORDER BY NUM_ENROLLED_STUDENTS DESC) AS rn
    FROM TIP_SUBJECT_OFFERED
),
EnrollmentStats AS (
    SELECT NULL AS SCHOOL_NAME,
           e.DEPARTMENT_NAME,
           NULL AS avg_total_units,
           NULL AS total_units_range,
           NULL AS total_units_variance,
           e.total_enrollment,
           tc.SUBJECT_TITLE AS most_popular_course,
           tc.NUM_ENROLLED_STUDENTS AS course_enrollment,
           'EnrollmentStats' AS reason
    FROM EngEnrollment e
    LEFT JOIN TopCourse tc ON e.DEPARTMENT_NAME = tc.OFFER_DEPT_NAME AND tc.rn = 1
)
SELECT SCHOOL_NAME, DEPARTMENT_NAME, avg_total_units, total_units_range, total_units_variance,
       total_enrollment, most_popular_course, course_enrollment, reason
FROM UnitsStats
UNION ALL
SELECT SCHOOL_NAME, DEPARTMENT_NAME, avg_total_units, total_units_range, total_units_variance,
       total_enrollment, most_popular_course, course_enrollment, reason
FROM EnrollmentStats
ORDER BY SCHOOL_NAME, DEPARTMENT_NAME;