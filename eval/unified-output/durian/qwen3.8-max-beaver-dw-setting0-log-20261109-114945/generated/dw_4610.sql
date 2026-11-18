WITH DepartmentEnrollmentStats AS (
  SELECT d.DEPARTMENT_NAME,
         d.DEPARTMENT_CODE,
         VARIANCE(t.NUM_ENROLLED_STUDENTS) AS enrolled_students_variance,
         STDDEV(t.NUM_ENROLLED_STUDENTS) AS enrolled_students_stddev
  FROM TIP_SUBJECT_OFFERED t
  JOIN SIS_DEPARTMENT d ON t.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
  JOIN SIS_SUBJECT_CODE s ON d.DEPARTMENT_CODE = s.DEPARTMENT_CODE
  WHERE d.IS_DEGREE_GRANTING = 'Y'
    AND s.SUBJECT_CODE_DESC IS NOT NULL
  GROUP BY d.DEPARTMENT_NAME, d.DEPARTMENT_CODE
  ORDER BY enrolled_students_variance DESC
),
TopReservedSubjects AS (
  SELECT s.SUBJECT_TITLE,
         s.OFFER_DEPT_NAME,
         s.OFFER_DEPT_CODE,
         COUNT(l.LIBRARY_RESERVE_CATALOG_KEY) AS reserved_materials,
         s.TOTAL_UNITS
  FROM LIBRARY_RESERVE_MATRL_DETAIL l
  JOIN TIP_DETAIL t ON l.SUBJECT_ID = t.SUBJECT_ID
  JOIN SUBJECT_OFFERED_SUMMARY s ON t.SUBJECT_ID = s.SUBJECT_ID
  WHERE l.TERM_CODE = '2009SP'
  GROUP BY s.SUBJECT_TITLE, s.OFFER_DEPT_NAME, s.OFFER_DEPT_CODE, s.TOTAL_UNITS
  ORDER BY reserved_materials DESC
  LIMIT 10
)
SELECT trs.SUBJECT_TITLE,
       trs.OFFER_DEPT_NAME,
       des.enrolled_students_variance,
       des.enrolled_students_stddev,
       trs.reserved_materials,
       trs.TOTAL_UNITS
FROM TopReservedSubjects trs
JOIN DepartmentEnrollmentStats des ON trs.OFFER_DEPT_CODE = des.DEPARTMENT_CODE
ORDER BY trs.reserved_materials DESC;