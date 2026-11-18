WITH units_base AS (
    SELECT scd.SCHOOL_NAME, scd.DEPARTMENT_NAME, ccso.TOTAL_UNITS
    FROM SIS_SUBJECT_CODE ssc
    JOIN SIS_COURSE_DESCRIPTION scd ON scd.COURSE = ssc.COURSE_NUMBER
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON ccso.SUBJECT_CODE = scd.COURSE
    WHERE ccso.ACADEMIC_YEAR = 2022
      AND scd.IS_DEGREE_GRANTING = 'Y'
      AND scd.DEPARTMENT_NAME <> 'Mathematics'
),
units_stats AS (
    SELECT SCHOOL_NAME,
           DEPARTMENT_NAME,
           AVG(TOTAL_UNITS) AS avg_total_units,
           MAX(TOTAL_UNITS) - MIN(TOTAL_UNITS) AS total_units_range,
           VARIANCE(TOTAL_UNITS) AS total_units_variance
    FROM units_base
    GROUP BY SCHOOL_NAME, DEPARTMENT_NAME WITH ROLLUP
    HAVING SCHOOL_NAME IS NOT NULL
),
eng_dept_enrollment AS (
    SELECT s.DEPARTMENT_CODE,
           s.DEPARTMENT_NAME,
           s.SCHOOL_NAME,
           SUM(t.NUM_ENROLLED_STUDENTS) AS total_enrollment
    FROM SIS_DEPARTMENT s
    JOIN TIP_SUBJECT_OFFERED t ON s.DEPARTMENT_CODE = t.OFFER_DEPT_CODE
    JOIN STUDENT_DEPARTMENT d ON t.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
    WHERE s.SCHOOL_NAME = 'Engineering'
      AND s.IS_DEGREE_GRANTING = 'Y'
      AND s.DEPARTMENT_CODE <> '15'
    GROUP BY s.DEPARTMENT_CODE, s.DEPARTMENT_NAME, s.SCHOOL_NAME
    HAVING SUM(t.NUM_ENROLLED_STUDENTS) > 50
),
most_popular AS (
    SELECT OFFER_DEPT_CODE,
           SUBJECT_TITLE,
           NUM_ENROLLED_STUDENTS,
           ROW_NUMBER() OVER (PARTITION BY OFFER_DEPT_CODE ORDER BY NUM_ENROLLED_STUDENTS DESC) AS rn
    FROM TIP_SUBJECT_OFFERED
)
SELECT us.SCHOOL_NAME AS `school name`,
       us.DEPARTMENT_NAME AS `department name`,
       us.avg_total_units AS `average total units`,
       us.total_units_range AS `total units range`,
       us.total_units_variance AS `total units variance`,
       NULL AS `total enrollment`,
       NULL AS `most popular course`,
       NULL AS `course enrollment`,
       'UnitsStats' AS reason
FROM units_stats us
UNION ALL
SELECT e.SCHOOL_NAME,
       e.DEPARTMENT_NAME,
       NULL,
       NULL,
       NULL,
       e.total_enrollment,
       mp.SUBJECT_TITLE,
       mp.NUM_ENROLLED_STUDENTS,
       'EnrollmentStats'
FROM eng_dept_enrollment e
LEFT JOIN most_popular mp ON mp.OFFER_DEPT_CODE = e.DEPARTMENT_CODE AND mp.rn = 1