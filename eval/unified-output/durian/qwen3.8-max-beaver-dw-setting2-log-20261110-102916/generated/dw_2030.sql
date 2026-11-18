WITH AdminDeptCov AS (
  SELECT sad.SIS_ADMIN_DEPARTMENT_NAME,
         STDDEV_SAMP(ccso.TOTAL_UNITS) / NULLIF(AVG(ccso.TOTAL_UNITS), 0) AS coefficient_of_variation
  FROM SIS_ADMIN_DEPARTMENT sad
  JOIN SIS_DEPARTMENT sd ON sad.SIS_ADMIN_DEPARTMENT_CODE = sd.DEPARTMENT_CODE
  JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON sd.DEPARTMENT_CODE = ccso.DEPARTMENT_CODE
  WHERE UPPER(sad.SIS_ADMIN_DEPARTMENT_NAME) = 'MECHANICAL ENGINEERING'
    AND ccso.ACADEMIC_YEAR = 2024
  GROUP BY sad.SIS_ADMIN_DEPARTMENT_NAME
),
DeptCov AS (
  SELECT c.DEPARTMENT_NAME,
         STDDEV(c.TOTAL_UNITS) / NULLIF(AVG(c.TOTAL_UNITS), 0) AS coefficient_of_variation,
         COUNT(c.TOTAL_UNITS) AS number_of_subjects
  FROM COURSE_CATALOG_SUBJECT_OFFERED c
  JOIN ACADEMIC_TERMS t ON c.TERM_CODE = t.TERM_CODE
  WHERE t.IS_REGULAR_TERM = 'Y'
    AND c.DEPARTMENT_NAME <> 'Mathematics'
  GROUP BY c.DEPARTMENT_NAME
  HAVING COUNT(c.TOTAL_UNITS) > 0
)
SELECT adc.SIS_ADMIN_DEPARTMENT_NAME,
       adc.coefficient_of_variation AS admin_dept_coefficient_of_variation,
       dc.DEPARTMENT_NAME,
       dc.coefficient_of_variation AS dept_coefficient_of_variation,
       dc.number_of_subjects
FROM AdminDeptCov adc
CROSS JOIN DeptCov dc;