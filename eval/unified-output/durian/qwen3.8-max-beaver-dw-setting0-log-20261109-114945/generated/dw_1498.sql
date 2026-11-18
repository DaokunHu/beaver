WITH subj_dept AS (
    SELECT DISTINCT
           sc.SUBJECT_CODE,
           sc.SUBJECT_CODE_DESC,
           d.DEPARTMENT_CODE,
           d.DEPARTMENT_NAME,
           d.SCHOOL_NAME
    FROM SIS_SUBJECT_CODE sc
    JOIN SIS_DEPARTMENT d
        ON sc.SCHOOL_CODE = d.SCHOOL_CODE
    WHERE sc.DEPARTMENT_NAME = 'Political Science'
      AND d.IS_DEGREE_GRANTING = 'Y'
),
dept_students AS (
    SELECT msd.DEPARTMENT,
           COUNT(*) AS num_students
    FROM MIT_STUDENT_DIRECTORY msd
    GROUP BY msd.DEPARTMENT
),
subj_agg AS (
    SELECT sd.SUBJECT_CODE,
           sd.SUBJECT_CODE_DESC,
           EXP(AVG(LN(ds.num_students))) AS geometric_mean_students,
           SUM(ds.num_students) AS total_students
    FROM subj_dept sd
    JOIN dept_students ds
        ON ds.DEPARTMENT = sd.DEPARTMENT_CODE
    GROUP BY sd.SUBJECT_CODE, sd.SUBJECT_CODE_DESC
),
dept_units AS (
    SELECT d.DEPARTMENT_NAME,
           d.SCHOOL_NAME,
           AVG(c.TOTAL_UNITS) AS avg_total_units,
           MAX(c.TOTAL_UNITS) - MIN(c.TOTAL_UNITS) AS range_total_units,
           VARIANCE(c.TOTAL_UNITS) AS variance_total_units,
           ad.DEPARTMENT_PHONE_NUMBER
    FROM SIS_DEPARTMENT d
    JOIN COURSE_CATALOG_SUBJECT_OFFERED c
        ON d.DEPARTMENT_CODE = c.DEPARTMENT_CODE
    LEFT JOIN SIS_ADMIN_DEPARTMENT ad
        ON d.DEPARTMENT_CODE = ad.SIS_ADMIN_DEPARTMENT_CODE
    WHERE c.ACADEMIC_YEAR = 2022
      AND d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_NAME <> 'Mathematics'
    GROUP BY d.DEPARTMENT_NAME, d.SCHOOL_NAME, ad.DEPARTMENT_PHONE_NUMBER
)
SELECT sa.SUBJECT_CODE,
       sa.SUBJECT_CODE_DESC,
       sa.geometric_mean_students,
       sa.total_students,
       du.DEPARTMENT_NAME,
       du.SCHOOL_NAME,
       du.avg_total_units,
       du.range_total_units,
       du.variance_total_units,
       du.DEPARTMENT_PHONE_NUMBER
FROM subj_agg sa
JOIN (SELECT DISTINCT SUBJECT_CODE, DEPARTMENT_NAME FROM subj_dept) sdx
    ON sdx.SUBJECT_CODE = sa.SUBJECT_CODE
JOIN dept_units du
    ON du.DEPARTMENT_NAME = sdx.DEPARTMENT_NAME
ORDER BY sa.SUBJECT_CODE, du.SCHOOL_NAME, du.DEPARTMENT_NAME