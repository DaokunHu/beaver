WITH dept_totals AS (
    SELECT s.OFFER_DEPT_NAME,
           COUNT(l.LIBRARY_RESERVE_CATALOG_KEY) AS total_reserved
    FROM LIBRARY_RESERVE_MATRL_DETAIL l
    JOIN TIP_DETAIL t ON l.SUBJECT_ID = t.SUBJECT_ID
    JOIN TIP_SUBJECT_OFFERED s ON t.SUBJECT_ID = s.SUBJECT_ID
    WHERE s.OFFER_SCHOOL_NAME IN ('Engineering', 'Science')
      AND s.IS_NO_COURSE_MATERIAL = 'N'
    GROUP BY s.OFFER_DEPT_NAME
    HAVING COUNT(l.LIBRARY_RESERVE_CATALOG_KEY) > 20
),
detail AS (
    SELECT s.OFFER_DEPT_NAME,
           s.SUBJECT_TITLE,
           s.TERM_CODE,
           s.RESPONSIBLE_FACULTY_NAME,
           d.DEPARTMENT_FULL_NAME,
           d.SCHOOL_NAME,
           MAX(s.NUM_ENROLLED_STUDENTS) OVER (
               ORDER BY s.TIP_SUBJECT_OFFERED_KEY
               ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING
           ) AS max_enrolled
    FROM LIBRARY_RESERVE_MATRL_DETAIL l
    JOIN TIP_DETAIL t ON l.SUBJECT_ID = t.SUBJECT_ID
    JOIN TIP_SUBJECT_OFFERED s ON t.SUBJECT_ID = s.SUBJECT_ID
    JOIN STUDENT_DEPARTMENT d ON s.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
    WHERE s.OFFER_SCHOOL_NAME IN ('Engineering', 'Science')
      AND s.IS_NO_COURSE_MATERIAL = 'N'
)
SELECT dt.OFFER_DEPT_NAME AS department_name,
       dt.total_reserved AS total_reserved_library_materials,
       det.SUBJECT_TITLE AS subject_title,
       det.TERM_CODE AS term_code,
       det.OFFER_DEPT_NAME AS offering_department_name,
       det.RESPONSIBLE_FACULTY_NAME AS responsible_faculty_name,
       det.DEPARTMENT_FULL_NAME AS department_full_name,
       det.SCHOOL_NAME AS school_name,
       det.max_enrolled AS max_enrolled_students,
       ROUND(dt.total_reserved / det.max_enrolled) AS reserved_materials_per_max_enrolled
FROM dept_totals dt
JOIN detail det ON dt.OFFER_DEPT_NAME = det.OFFER_DEPT_NAME
ORDER BY reserved_materials_per_max_enrolled DESC;