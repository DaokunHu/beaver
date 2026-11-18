WITH inner_dept AS (
  SELECT s.DEPARTMENT_NAME, SUM(t.NUM_ENROLLED_STUDENTS) AS total_enrollment
  FROM SIS_DEPARTMENT s
  JOIN TIP_SUBJECT_OFFERED t ON s.DEPARTMENT_CODE = t.OFFER_DEPT_CODE
  JOIN STUDENT_DEPARTMENT d ON t.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
  WHERE s.SCHOOL_NAME = 'Engineering'
  GROUP BY s.DEPARTMENT_NAME
  HAVING SUM(t.NUM_ENROLLED_STUDENTS) > 50
),
engineering_dept_enrollment AS (
  SELECT i.DEPARTMENT_NAME, i.total_enrollment
  FROM inner_dept i
  JOIN (SELECT AVG(total_enrollment) AS avg_enrollment FROM inner_dept) a
    ON i.total_enrollment > a.avg_enrollment
),
library_inner AS (
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
         s.TIP_SUBJECT_OFFERED_KEY
  FROM LIBRARY_RESERVE_MATRL_DETAIL l
  JOIN TIP_DETAIL t ON l.SUBJECT_ID = t.SUBJECT_ID
  JOIN TIP_SUBJECT_OFFERED s ON t.SUBJECT_ID = s.SUBJECT_ID
  WHERE l.LIBRARY_MATERIAL_STATUS_KEY = 'U'
),
library_reserve_materials AS (
  SELECT li.LIBRARY_COURSE_INSTRUCTOR_KEY,
         li.LIBRARY_RESERVE_CATALOG_KEY,
         li.TERM_CODE,
         li.SUBJECT_ID,
         li.TIP_MATERIAL_KEY,
         li.TIP_MATERIAL_STATUS_KEY,
         li.ISBN,
         li.SUBJECT_TITLE,
         li.window_column,
         s.RESPONSIBLE_FACULTY_NAME,
         s.OFFER_DEPT_NAME
  FROM library_inner li
  JOIN TIP_SUBJECT_OFFERED s ON li.TIP_SUBJECT_OFFERED_KEY = s.TIP_SUBJECT_OFFERED_KEY
)
SELECT ede.DEPARTMENT_NAME,
       ede.total_enrollment,
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
FROM engineering_dept_enrollment ede
JOIN library_reserve_materials lrm ON ede.DEPARTMENT_NAME = lrm.OFFER_DEPT_NAME