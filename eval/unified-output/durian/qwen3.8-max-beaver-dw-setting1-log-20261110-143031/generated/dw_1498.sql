WITH dept_student_counts AS (
    SELECT msd.DEPARTMENT,
           COUNT(*) AS student_count
    FROM MIT_STUDENT_DIRECTORY msd
    GROUP BY msd.DEPARTMENT
),
subject_dept AS (
    SELECT DISTINCT sc.SUBJECT_CODE, sc.SUBJECT_CODE_DESC, sc.DEPARTMENT_CODE
    FROM SIS_SUBJECT_CODE sc
    JOIN SIS_DEPARTMENT d ON d.DEPARTMENT_CODE = sc.DEPARTMENT_CODE
    WHERE d.DEPARTMENT_NAME = 'Political Science'
      AND d.IS_DEGREE_GRANTING = 'Y'
),
student_stats AS (
    SELECT sd.SUBJECT_CODE,
           sd.SUBJECT_CODE_DESC,
           EXP(AVG(LN(dsc.student_count))) AS geometric_mean_students,
           SUM(dsc.student_count) AS total_students
    FROM subject_dept sd
    JOIN dept_student_counts dsc ON dsc.DEPARTMENT = sd.DEPARTMENT_CODE
    GROUP BY sd.SUBJECT_CODE, sd.SUBJECT_CODE_DESC
),
unit_stats AS (
    SELECT sc.SUBJECT_CODE,
           d.DEPARTMENT_NAME,
           d.SCHOOL_NAME,
           AVG(cc.TOTAL_UNITS) AS avg_total_units,
           MAX(cc.TOTAL_UNITS) - MIN(cc.TOTAL_UNITS) AS total_units_range,
           VARIANCE(cc.TOTAL_UNITS) AS total_units_variance,
           ad.DEPARTMENT_PHONE_NUMBER
    FROM SIS_SUBJECT_CODE sc
    JOIN SIS_DEPARTMENT d ON d.DEPARTMENT_CODE = sc.DEPARTMENT_CODE
    JOIN SIS_COURSE_DESCRIPTION cd ON cd.COURSE = sc.COURSE_NUMBER
    JOIN COURSE_CATALOG_SUBJECT_OFFERED cc ON cc.SUBJECT_CODE = cd.COURSE
    LEFT JOIN SIS_ADMIN_DEPARTMENT ad ON ad.SIS_ADMIN_DEPARTMENT_CODE = d.DEPARTMENT_CODE
    WHERE d.DEPARTMENT_NAME = 'Political Science'
      AND cc.ACADEMIC_YEAR = 2022
      AND cd.IS_DEGREE_GRANTING = 'Y'
      AND cd.DEPARTMENT_NAME <> 'Mathematics'
    GROUP BY sc.SUBJECT_CODE, d.DEPARTMENT_NAME, d.SCHOOL_NAME, ad.DEPARTMENT_PHONE_NUMBER
)
SELECT ss.SUBJECT_CODE,
       ss.SUBJECT_CODE_DESC,
       ss.geometric_mean_students,
       ss.total_students,
       us.DEPARTMENT_NAME,
       us.SCHOOL_NAME,
       us.avg_total_units,
       us.total_units_range,
       us.total_units_variance,
       us.DEPARTMENT_PHONE_NUMBER
FROM student_stats ss
JOIN unit_stats us ON us.SUBJECT_CODE = ss.SUBJECT_CODE
ORDER BY ss.SUBJECT_CODE, us.SCHOOL_NAME, us.DEPARTMENT_NAME