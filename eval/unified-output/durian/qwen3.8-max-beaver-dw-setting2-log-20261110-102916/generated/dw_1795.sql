WITH units_inner AS (
    SELECT SIS_COURSE_DESCRIPTION.DEPARTMENT_NAME,
           SIS_COURSE_DESCRIPTION.SCHOOL_NAME,
           COURSE_CATALOG_SUBJECT_OFFERED.TOTAL_UNITS
    FROM SIS_SUBJECT_CODE
    JOIN SIS_COURSE_DESCRIPTION
        ON SIS_SUBJECT_CODE.COURSE_NUMBER = SIS_COURSE_DESCRIPTION.COURSE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED
        ON SIS_COURSE_DESCRIPTION.COURSE = COURSE_CATALOG_SUBJECT_OFFERED.SUBJECT_CODE
    WHERE COURSE_CATALOG_SUBJECT_OFFERED.ACADEMIC_YEAR = 2022
      AND SIS_COURSE_DESCRIPTION.IS_DEGREE_GRANTING = 'Y'
      AND SIS_COURSE_DESCRIPTION.DEPARTMENT_NAME <> 'Mathematics'
      AND SIS_COURSE_DESCRIPTION.DEPARTMENT <> '18'
),
UnitsStats AS (
    SELECT SCHOOL_NAME,
           DEPARTMENT_NAME,
           AVG(TOTAL_UNITS) AS avg_total_units,
           MAX(TOTAL_UNITS) - MIN(TOTAL_UNITS) AS total_units_range,
           VARIANCE(TOTAL_UNITS) AS total_units_variance,
           NULL AS total_enrollment,
           NULL AS Most_Popular_Course,
           NULL AS Course_Enrollment,
           'UnitsStats' AS Reason
    FROM units_inner
    GROUP BY SCHOOL_NAME, DEPARTMENT_NAME WITH ROLLUP
    HAVING SCHOOL_NAME IS NOT NULL
),
enroll_inner AS (
    SELECT s.DEPARTMENT_NAME,
           s.DEPARTMENT_CODE,
           SUM(t.NUM_ENROLLED_STUDENTS) AS total_enrollment
    FROM SIS_DEPARTMENT s
    JOIN TIP_SUBJECT_OFFERED t
        ON s.DEPARTMENT_CODE = t.OFFER_DEPT_CODE
    JOIN STUDENT_DEPARTMENT d
        ON t.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
    WHERE s.SCHOOL_NAME = 'Engineering'
      AND s.IS_DEGREE_GRANTING = 'Y'
      AND s.DEPARTMENT_CODE <> '15'
    GROUP BY s.DEPARTMENT_NAME, s.DEPARTMENT_CODE
    HAVING SUM(t.NUM_ENROLLED_STUDENTS) > 50
),
EnrollmentStats AS (
    SELECT NULL AS SCHOOL_NAME,
           ic.DEPARTMENT_NAME,
           NULL AS avg_total_units,
           NULL AS total_units_range,
           NULL AS total_units_variance,
           ic.total_enrollment,
           t.SUBJECT_TITLE AS Most_Popular_Course,
           t.NUM_ENROLLED_STUDENTS AS Course_Enrollment,
           'EnrollmentStats' AS Reason
    FROM enroll_inner ic
    JOIN TIP_SUBJECT_OFFERED t
        ON ic.DEPARTMENT_CODE = t.OFFER_DEPT_CODE
    WHERE t.NUM_ENROLLED_STUDENTS = (
        SELECT MAX(t2.NUM_ENROLLED_STUDENTS)
        FROM TIP_SUBJECT_OFFERED t2
        WHERE t2.OFFER_DEPT_CODE = ic.DEPARTMENT_CODE
    )
)
SELECT SCHOOL_NAME, DEPARTMENT_NAME, avg_total_units, total_units_range,
       total_units_variance, total_enrollment, Most_Popular_Course,
       Course_Enrollment, Reason
FROM UnitsStats
UNION ALL
SELECT SCHOOL_NAME, DEPARTMENT_NAME, avg_total_units, total_units_range,
       total_units_variance, total_enrollment, Most_Popular_Course,
       Course_Enrollment, Reason
FROM EnrollmentStats
ORDER BY Reason, SCHOOL_NAME, DEPARTMENT_NAME