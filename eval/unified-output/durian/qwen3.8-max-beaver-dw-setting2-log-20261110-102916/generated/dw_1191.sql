WITH MathSubjects2024 AS (
    SELECT t0.SUBJECT_ID,
           t0.SUBJECT_CODE,
           t0.SUBJECT_NUMBER,
           t0.DEPARTMENT_CODE,
           t0.DEPARTMENT_NAME,
           t0.SUBJECT_SHORT_TITLE,
           t0.SUBJECT_TITLE,
           t0.LECTURE_UNITS,
           t0.LAB_UNITS,
           t0.TOTAL_UNITS,
           t0.GRADE_TYPE,
           t0.GRADE_RULE,
           MIN(t0.TOTAL_UNITS) OVER (PARTITION BY t0.DEPARTMENT_CODE ORDER BY t0.DEPARTMENT_CODE) AS min_total_units_by_dept
    FROM COURSE_CATALOG_SUBJECT_OFFERED t0
    JOIN CIS_COURSE_CATALOG t1 ON t0.SUBJECT_ID = t1.SUBJECT_ID
    WHERE t0.ACADEMIC_YEAR = 2024
      AND t0.DEPARTMENT_NAME = 'Mathematics'
),
DeptSubjectStats AS (
    SELECT d.DEPARTMENT_NAME,
           s.SUBJECT_CODE,
           COUNT(s.SUBJECT_CODE) AS subject_code_count,
           MIN(d.DEPT_BUDGET_CODE) AS min_dept_budget_code
    FROM SIS_DEPARTMENT d
    JOIN SIS_SUBJECT_CODE s ON d.DEPARTMENT_CODE = s.DEPARTMENT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_NAME = 'Mathematics'
      AND d.DEPARTMENT_CODE = '18'
    GROUP BY d.DEPARTMENT_NAME, s.SUBJECT_CODE
)
SELECT ms.SUBJECT_ID,
       ms.SUBJECT_CODE,
       ms.SUBJECT_NUMBER,
       ms.DEPARTMENT_NAME,
       ms.SUBJECT_SHORT_TITLE,
       ms.SUBJECT_TITLE,
       ms.LECTURE_UNITS,
       ms.LAB_UNITS,
       ms.TOTAL_UNITS,
       ms.GRADE_TYPE,
       ms.GRADE_RULE,
       ms.min_total_units_by_dept,
       dss.subject_code_count,
       dss.min_dept_budget_code
FROM MathSubjects2024 ms
JOIN DeptSubjectStats dss
  ON ms.SUBJECT_CODE = dss.SUBJECT_CODE
 AND ms.DEPARTMENT_NAME = dss.DEPARTMENT_NAME
ORDER BY ms.DEPARTMENT_CODE, ms.SUBJECT_CODE, ms.SUBJECT_NUMBER