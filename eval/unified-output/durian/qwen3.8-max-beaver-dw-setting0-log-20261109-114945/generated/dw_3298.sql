WITH MathLibrarySubjects AS (
  SELECT t0.SUBJECT_TITLE,
         t0.NUM_ENROLLED_STUDENTS,
         t0.OFFER_DEPT_NAME,
         t1.TERM_DESCRIPTION,
         t1.ACADEMIC_YEAR,
         t2.SUBJECT_SHORT_TITLE,
         MAX(t2.TOTAL_UNITS) OVER (ORDER BY t0.SUBJECT_ID ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS max_total_units
  FROM LIBRARY_SUBJECT_OFFERED t0
  JOIN ACADEMIC_TERMS t1 ON t0.TERM_CODE = t1.TERM_CODE
  JOIN COURSE_CATALOG_SUBJECT_OFFERED t2 ON t1.TERM_CODE = t2.TERM_CODE AND t0.SUBJECT_ID = t2.SUBJECT_ID
  WHERE t0.OFFER_DEPT_NAME = 'Mathematics'
    AND t1.IS_REGULAR_TERM = 'Y'
),
CIPStats AS (
  SELECT AVG(scd.CIP_PROGRAM_CODE) AS avg_cip_program_code,
         MAX(scd.CIP_PROGRAM_CODE) - MIN(scd.CIP_PROGRAM_CODE) AS cip_program_code_range,
         VARIANCE(scd.CIP_PROGRAM_CODE) AS cip_program_code_variance
  FROM SIS_COURSE_DESCRIPTION scd
  JOIN SIS_DEPARTMENT sd ON scd.DEPARTMENT = sd.DEPARTMENT_CODE
  WHERE scd.IS_DEGREE_GRANTING = 'Y'
    AND scd.COURSE_LEVEL = 'U'
    AND scd.CIP_PROGRAM_CODE IS NOT NULL
    AND sd.DEPARTMENT_NAME = 'Mathematics'
)
SELECT m.SUBJECT_TITLE,
       m.NUM_ENROLLED_STUDENTS,
       m.OFFER_DEPT_NAME,
       m.TERM_DESCRIPTION,
       m.ACADEMIC_YEAR,
       m.SUBJECT_SHORT_TITLE,
       m.max_total_units,
       c.avg_cip_program_code,
       c.cip_program_code_range,
       c.cip_program_code_variance
FROM MathLibrarySubjects m
CROSS JOIN CIPStats c