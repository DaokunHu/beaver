WITH dept_stats AS (
    SELECT d.DEPARTMENT_CODE,
           d.DEPARTMENT_NAME,
           VARIANCE(s.TOTAL_UNITS) AS total_units_variance,
           AVG(s.NUM_ENROLLED_STUDENTS) AS avg_enrolled_students
    FROM SIS_DEPARTMENT d
    JOIN SUBJECT_OFFERED_SUMMARY s ON d.DEPARTMENT_CODE = s.OFFER_DEPT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND s.NUM_ENROLLED_STUDENTS > 0
    GROUP BY d.DEPARTMENT_CODE, d.DEPARTMENT_NAME
),
overall_stats AS (
    SELECT AVG(s.NUM_ENROLLED_STUDENTS) AS overall_avg_enrolled
    FROM SIS_DEPARTMENT d
    JOIN SUBJECT_OFFERED_SUMMARY s ON d.DEPARTMENT_CODE = s.OFFER_DEPT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND s.NUM_ENROLLED_STUDENTS > 0
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
    JOIN TIP_DETAIL t ON l.SUBJECT_ID = t.SUBJECT_ID
    JOIN TIP_SUBJECT_OFFERED s ON t.SUBJECT_ID = s.SUBJECT_ID
    WHERE l.LIBRARY_MATERIAL_STATUS_KEY = 'U'
)
SELECT ds.DEPARTMENT_CODE,
       ds.DEPARTMENT_NAME,
       ds.total_units_variance,
       ds.avg_enrolled_students,
       CASE
           WHEN ds.avg_enrolled_students > os.overall_avg_enrolled * 1.2 THEN 'HIGH_ENROLLMENT'
           WHEN ds.avg_enrolled_students < os.overall_avg_enrolled * 0.8 THEN 'LOW_ENROLLMENT'
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
CROSS JOIN overall_stats os
JOIN library_reserve_materials lrm ON ds.DEPARTMENT_CODE = lrm.OFFER_DEPT_CODE