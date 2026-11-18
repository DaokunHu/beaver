WITH subq1 AS (
    SELECT t1.SUBJECT_CODE,
           t1.SUBJECT_CODE_DESC,
           t0.DEPARTMENT_NAME,
           t1.SCHOOL_NAME,
           AVG(t0.DEPT_BUDGET_CODE) OVER (PARTITION BY t1.SCHOOL_NAME ORDER BY t0.DEPARTMENT_NAME) AS avg_dept_budget_code
    FROM SIS_DEPARTMENT t0
    JOIN SIS_SUBJECT_CODE t1 ON t0.SCHOOL_CODE = t1.SCHOOL_CODE
    WHERE t0.IS_DEGREE_GRANTING = 'Y'
      AND t0.DEPARTMENT_NAME = 'Mathematics'
),
subq2 AS (
    SELECT t0.SUBJECT_CODE,
           t0.SUBJECT_TITLE,
           t0.TOTAL_UNITS,
           DENSE_RANK() OVER (PARTITION BY t0.DEPARTMENT_CODE ORDER BY t0.DEPARTMENT_CODE) AS window_column,
           COUNT(t0.SUBJECT_ID) OVER (PARTITION BY t0.DEPARTMENT_CODE) AS num_subjects_offered
    FROM COURSE_CATALOG_SUBJECT_OFFERED t0
    WHERE t0.DEPARTMENT_NAME = 'Mathematics'
)
SELECT subq1.SUBJECT_CODE,
       subq1.SUBJECT_CODE_DESC,
       subq1.DEPARTMENT_NAME,
       subq1.SCHOOL_NAME,
       subq1.avg_dept_budget_code,
       subq2.SUBJECT_TITLE,
       subq2.TOTAL_UNITS,
       subq2.window_column,
       subq2.num_subjects_offered
FROM subq1
JOIN subq2 ON subq1.SUBJECT_CODE = subq2.SUBJECT_CODE
ORDER BY subq1.DEPARTMENT_NAME, subq2.window_column