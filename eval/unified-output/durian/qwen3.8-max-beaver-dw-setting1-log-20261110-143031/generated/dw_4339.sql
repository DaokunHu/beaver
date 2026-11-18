WITH dept_stats AS (
    SELECT ssc.DEPARTMENT_CODE,
           ssc.DEPARTMENT_NAME,
           VARIANCE(sos.TOTAL_UNITS)          AS total_units_variance,
           AVG(sos.NUM_ENROLLED_STUDENTS)     AS avg_enrolled_students
    FROM SIS_SUBJECT_CODE ssc
    JOIN SIS_COURSE_DESCRIPTION scd
      ON scd.COURSE = ssc.COURSE_NUMBER
    JOIN SUBJECT_OFFERED_SUMMARY sos
      ON sos.COURSE_NUMBER = scd.COURSE
     AND sos.OFFER_DEPT_CODE = ssc.DEPARTMENT_CODE
    WHERE scd.IS_DEGREE_GRANTING = 'Y'
      AND sos.NUM_ENROLLED_STUDENTS > 0
    GROUP BY ssc.DEPARTMENT_CODE, ssc.DEPARTMENT_NAME
),
library_reserve_materials AS (
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
           s.OFFER_DEPT_NAME,
           s.OFFER_DEPT_CODE
    FROM LIBRARY_RESERVE_MATRL_DETAIL l
    JOIN TIP_DETAIL t
      ON l.SUBJECT_ID = t.SUBJECT_ID
    JOIN TIP_SUBJECT_OFFERED s
      ON t.SUBJECT_ID = s.SUBJECT_ID
    WHERE l.LIBRARY_MATERIAL_STATUS_KEY = 'U'
),
overall AS (
    SELECT AVG(sos.NUM_ENROLLED_STUDENTS) AS avg_enrollment
    FROM SIS_SUBJECT_CODE ssc
    JOIN SIS_COURSE_DESCRIPTION scd
      ON scd.COURSE = ssc.COURSE_NUMBER
    JOIN SUBJECT_OFFERED_SUMMARY sos
      ON sos.COURSE_NUMBER = scd.COURSE
     AND sos.OFFER_DEPT_CODE = ssc.DEPARTMENT_CODE
    WHERE scd.IS_DEGREE_GRANTING = 'Y'
      AND sos.NUM_ENROLLED_STUDENTS > 0
)
SELECT ds.DEPARTMENT_CODE,
       ds.DEPARTMENT_NAME,
       ds.total_units_variance,
       ds.avg_enrolled_students,
       CASE WHEN ds.avg_enrolled_students > o.avg_enrollment * 1.2 THEN 'HIGH_ENROLLMENT'
            WHEN ds.avg_enrolled_students < o.avg_enrollment * 0.8 THEN 'LOW_ENROLLMENT'
            ELSE 'AVERAGE'
       END AS enrollment_category,
       lrm.LIBRARY_COURSE_INSTRUCTOR_KEY,
       lrm.LIBRARY_RESERVE_CATALOG_KEY,
       lrm.TERM_CODE,
       lrm.SUBJECT_ID,
       lrm.TIP_MATERIAL_KEY,
       lrm.TIP_MATERIAL_STATUS_KEY,
       lrm.ISBN,
       lrm.SUBJECT_TITLE,
       lrm.window_column,
       lrm.RESPONSIBLE_FACULTY_NAME,
       lrm.OFFER_DEPT_NAME
FROM dept_stats ds
JOIN library_reserve_materials lrm
  ON ds.DEPARTMENT_CODE = lrm.OFFER_DEPT_CODE
CROSS JOIN overall o