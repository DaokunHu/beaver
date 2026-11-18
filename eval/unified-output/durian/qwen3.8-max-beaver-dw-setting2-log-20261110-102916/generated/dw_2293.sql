WITH ReservedMaterials AS (
  SELECT tso.OFFER_DEPT_NAME AS department_name,
         COUNT(DISTINCT lrm.LIBRARY_RESERVE_CATALOG_KEY) AS total_reserved_materials
  FROM TIP_SUBJECT_OFFERED tso
  JOIN TIP_DETAIL td ON tso.SUBJECT_ID = td.SUBJECT_ID
  JOIN LIBRARY_RESERVE_MATRL_DETAIL lrm ON td.SUBJECT_ID = lrm.SUBJECT_ID
  WHERE tso.OFFER_SCHOOL_NAME IN ('Engineering', 'Science')
    AND tso.IS_NO_COURSE_MATERIAL = 'N'
  GROUP BY tso.OFFER_DEPT_NAME
  HAVING COUNT(DISTINCT lrm.LIBRARY_RESERVE_CATALOG_KEY) > 20
),
SchoolSubjects AS (
  SELECT t0.SUBJECT_TITLE,
         t0.TERM_CODE,
         t0.OFFER_DEPT_NAME,
         t0.RESPONSIBLE_FACULTY_NAME,
         t1.DEPARTMENT_FULL_NAME,
         t1.SCHOOL_NAME,
         MAX(t0.NUM_ENROLLED_STUDENTS) OVER (ORDER BY t0.TIP_SUBJECT_OFFERED_KEY ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS max_enrolled_students,
         t0.OFFER_DEPT_NAME AS join_dept_name
  FROM TIP_SUBJECT_OFFERED t0
  JOIN STUDENT_DEPARTMENT t1 ON t0.OFFER_DEPT_CODE = t1.DEPARTMENT_CODE
  WHERE t0.NUM_ENROLLED_STUDENTS >= 0
    AND t0.TERM_CODE IS NOT NULL
    AND t0.OFFER_SCHOOL_NAME IN ('Engineering', 'Science')
    AND t0.IS_NO_COURSE_MATERIAL = 'N'
)
SELECT rm.department_name,
       rm.total_reserved_materials,
       ss.SUBJECT_TITLE,
       ss.TERM_CODE,
       ss.OFFER_DEPT_NAME,
       ss.RESPONSIBLE_FACULTY_NAME,
       ss.DEPARTMENT_FULL_NAME,
       ss.SCHOOL_NAME,
       ss.max_enrolled_students,
       ROUND(rm.total_reserved_materials / NULLIF(ss.max_enrolled_students, 0), 2) AS reserved_materials_per_max_enrollment
FROM ReservedMaterials rm
JOIN SchoolSubjects ss ON rm.department_name = ss.join_dept_name
ORDER BY reserved_materials_per_max_enrollment DESC