WITH StudentYearCounts AS (
    SELECT d.DEPARTMENT_NAME,
           msd.STUDENT_YEAR,
           COUNT(*) AS num_students
    FROM SIS_SUBJECT_CODE sc
    JOIN SIS_DEPARTMENT d ON sc.DEPARTMENT_CODE = d.DEPARTMENT_CODE
    JOIN MIT_STUDENT_DIRECTORY msd ON msd.DEPARTMENT = d.DEPARTMENT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_NAME <> 'Biology'
    GROUP BY d.DEPARTMENT_NAME, msd.STUDENT_YEAR
),
DeptStudentStats AS (
    SELECT DEPARTMENT_NAME,
           VARIANCE(num_students) AS variance_num_students,
           STDDEV(num_students) AS stddev_num_students
    FROM StudentYearCounts
    GROUP BY DEPARTMENT_NAME
),
MathYearStats AS (
    SELECT cso.DEPARTMENT_NAME,
           at.ACADEMIC_YEAR,
           COUNT(DISTINCT ss.SUBJECT_ID) AS num_unique_subjects,
           MIN(ss.TOTAL_UNITS) AS min_total_units
    FROM COURSE_CATALOG_SUBJECT_OFFERED cso
    JOIN ACADEMIC_TERMS at ON cso.EFFECTIVE_TERM_CODE = at.TERM_CODE
    JOIN SUBJECT_SUMMARY ss ON at.TERM_CODE = ss.TERM_CODE
                           AND cso.DEPARTMENT_NAME = ss.DEPARTMENT_NAME
    WHERE cso.DEPARTMENT_NAME = 'Mathematics'
      AND ss.SUBJECT_ENROLLMENT_NUMBER > 10
    GROUP BY cso.DEPARTMENT_NAME, at.ACADEMIC_YEAR
)
SELECT d.DEPARTMENT_NAME,
       d.variance_num_students,
       d.stddev_num_students,
       m.ACADEMIC_YEAR,
       m.num_unique_subjects,
       m.min_total_units
FROM DeptStudentStats d
LEFT JOIN MathYearStats m ON d.DEPARTMENT_NAME = m.DEPARTMENT_NAME
ORDER BY d.DEPARTMENT_NAME, m.ACADEMIC_YEAR