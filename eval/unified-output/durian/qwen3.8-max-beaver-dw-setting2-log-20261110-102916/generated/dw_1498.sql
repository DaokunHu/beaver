WITH subject_stats AS (
    SELECT s.SUBJECT_CODE,
           s.SUBJECT_CODE_DESC,
           EXP(AVG(LN(m.student_count))) AS geometric_mean_students,
           SUM(m.student_count) AS total_students
    FROM SIS_SUBJECT_CODE s
    JOIN SIS_DEPARTMENT d
      ON s.DEPARTMENT_CODE = d.DEPARTMENT_CODE
    JOIN (
        SELECT DEPARTMENT, COUNT(*) AS student_count
        FROM MIT_STUDENT_DIRECTORY
        GROUP BY DEPARTMENT
    ) m
      ON d.DEPARTMENT_CODE = m.DEPARTMENT
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_NAME = 'Political Science'
    GROUP BY s.SUBJECT_CODE, s.SUBJECT_CODE_DESC
),
dept_unit_stats AS (
    SELECT scd.DEPARTMENT_NAME,
           AVG(ccso.TOTAL_UNITS) AS avg_total_units,
           MAX(ccso.TOTAL_UNITS) - MIN(ccso.TOTAL_UNITS) AS total_units_range,
           VARIANCE(ccso.TOTAL_UNITS) AS total_units_variance
    FROM SIS_SUBJECT_CODE ssc
    JOIN SIS_COURSE_DESCRIPTION scd
      ON ssc.COURSE_NUMBER = scd.COURSE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
      ON scd.COURSE = ccso.SUBJECT_CODE
    WHERE ccso.ACADEMIC_YEAR = 2022
      AND scd.IS_DEGREE_GRANTING = 'Y'
      AND scd.DEPARTMENT_NAME <> 'Mathematics'
      AND scd.DEPARTMENT <> '18'
    GROUP BY scd.DEPARTMENT_NAME
),
dept_full AS (
    SELECT du.DEPARTMENT_NAME,
           sd.SCHOOL_NAME,
           du.avg_total_units,
           du.total_units_range,
           du.total_units_variance,
           ad.DEPARTMENT_PHONE_NUMBER
    FROM dept_unit_stats du
    LEFT JOIN SIS_DEPARTMENT sd
      ON du.DEPARTMENT_NAME = sd.DEPARTMENT_NAME
    LEFT JOIN SIS_ADMIN_DEPARTMENT ad
      ON sd.DEPARTMENT_CODE = ad.SIS_ADMIN_DEPARTMENT_CODE
)
SELECT ss.SUBJECT_CODE,
       ss.SUBJECT_CODE_DESC,
       ss.geometric_mean_students,
       ss.total_students,
       df.DEPARTMENT_NAME,
       df.SCHOOL_NAME,
       df.avg_total_units,
       df.total_units_range,
       df.total_units_variance,
       df.DEPARTMENT_PHONE_NUMBER
FROM subject_stats ss
CROSS JOIN dept_full df
ORDER BY ss.SUBJECT_CODE, df.SCHOOL_NAME, df.DEPARTMENT_NAME