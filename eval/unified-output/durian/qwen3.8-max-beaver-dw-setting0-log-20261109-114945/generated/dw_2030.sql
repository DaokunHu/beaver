WITH admin_dept_cv AS (
    SELECT sad.SIS_ADMIN_DEPARTMENT_NAME,
           STDDEV(ccso.TOTAL_UNITS) / AVG(ccso.TOTAL_UNITS) AS admin_cv_total_units
    FROM SIS_ADMIN_DEPARTMENT sad
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
        ON sad.SIS_ADMIN_DEPARTMENT_CODE = ccso.DEPARTMENT_CODE
    WHERE sad.SIS_ADMIN_DEPARTMENT_NAME = 'Mechanical Engineering'
      AND ccso.ACADEMIC_YEAR = 2024
    GROUP BY sad.SIS_ADMIN_DEPARTMENT_NAME
),
dept_regular_cv AS (
    SELECT ccso.DEPARTMENT_NAME,
           STDDEV(ccso.TOTAL_UNITS) / AVG(ccso.TOTAL_UNITS) AS dept_cv_total_units,
           COUNT(ccso.SUBJECT_ID) AS num_subjects_offered
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN ACADEMIC_TERMS at
        ON ccso.TERM_CODE = at.TERM_CODE
    WHERE at.IS_REGULAR_TERM = 'Y'
      AND ccso.DEPARTMENT_NAME <> 'Mathematics'
    GROUP BY ccso.DEPARTMENT_NAME
)
SELECT a.SIS_ADMIN_DEPARTMENT_NAME,
       a.admin_cv_total_units,
       d.DEPARTMENT_NAME,
       d.dept_cv_total_units,
       d.num_subjects_offered
FROM admin_dept_cv a
CROSS JOIN dept_regular_cv d