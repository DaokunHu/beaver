WITH dept_stats AS (
    SELECT ssc.DEPARTMENT_CODE,
           ssc.DEPARTMENT_NAME,
           VARIANCE(sos.TOTAL_UNITS) AS total_units_variance,
           AVG(sos.NUM_ENROLLED_STUDENTS) AS avg_enrolled_students
    FROM SIS_SUBJECT_CODE ssc
    JOIN SIS_COURSE_DESCRIPTION scd ON ssc.COURSE_NUMBER = scd.COURSE
    JOIN SUBJECT_OFFERED_SUMMARY sos ON scd.COURSE = sos.COURSE_NUMBER
    WHERE sos.NUM_ENROLLED_STUDENTS > 0
      AND scd.IS_DEGREE_GRANTING = 'Y'
    GROUP BY ssc.DEPARTMENT_CODE, ssc.DEPARTMENT_NAME
),
overall AS (
    SELECT AVG(sos.NUM_ENROLLED_STUDENTS) AS avg_all_enrolled
    FROM SIS_COURSE_DESCRIPTION scd
    JOIN SUBJECT_OFFERED_SUMMARY sos ON scd.COURSE = sos.COURSE_NUMBER
    WHERE sos.NUM_ENROLLED_STUDENTS > 0
      AND scd.IS_DEGREE_GRANTING = 'Y'
),
dept_cat AS (
    SELECT d.DEPARTMENT_CODE,
           d.DEPARTMENT_NAME,
           d.total_units_variance,
           d.avg_enrolled_students,
           CASE WHEN d.avg_enrolled_students > o.avg_all_enrolled * 1.2 THEN 'HIGH_ENROLLMENT'
                WHEN d.avg_enrolled_students < o.avg_all_enrolled * 0.8 THEN 'LOW_ENROLLMENT'
                ELSE 'AVERAGE' END AS enrollment_category
    FROM dept_stats d
    CROSS JOIN overall o
),
library_materials AS (
    SELECT l.LIBRARY_COURSE_INSTRUCTOR_KEY,
           l.LIBRARY_RESERVE_CATALOG_KEY,
           l.TERM_CODE,
           l.SUBJECT_ID,
           t.TIP_MATERIAL_KEY,
           t.TIP_MATERIAL_STATUS_KEY,
           t.ISBN,
           s.SUBJECT_TITLE,
           MIN(t.TIP_MATERIAL_STATUS_KEY) OVER (
               ORDER BY s.NUM_ENROLLED_STUDENTS
               ROWS BETWEEN 3 PRECEDING AND 1 FOLLOWING
           ) AS window_column,
           s.RESPONSIBLE_FACULTY_NAME,
           s.OFFER_DEPT_NAME
    FROM LIBRARY_RESERVE_MATRL_DETAIL l
    JOIN TIP_DETAIL t ON l.SUBJECT_ID = t.SUBJECT_ID
    JOIN TIP_SUBJECT_OFFERED s ON t.SUBJECT_ID = s.SUBJECT_ID
    WHERE l.LIBRARY_MATERIAL_STATUS_KEY = 'U'
)
SELECT dc.DEPARTMENT_CODE,
       dc.DEPARTMENT_NAME,
       dc.total_units_variance,
       dc.avg_enrolled_students,
       dc.enrollment_category,
       lm.LIBRARY_COURSE_INSTRUCTOR_KEY,
       lm.LIBRARY_RESERVE_CATALOG_KEY,
       lm.TERM_CODE,
       lm.SUBJECT_ID,
       lm.TIP_MATERIAL_KEY,
       lm.TIP_MATERIAL_STATUS_KEY,
       lm.ISBN,
       lm.SUBJECT_TITLE,
       lm.window_column,
       lm.RESPONSIBLE_FACULTY_NAME,
       lm.OFFER_DEPT_NAME
FROM dept_cat dc
JOIN library_materials lm ON dc.DEPARTMENT_NAME = lm.OFFER_DEPT_NAME