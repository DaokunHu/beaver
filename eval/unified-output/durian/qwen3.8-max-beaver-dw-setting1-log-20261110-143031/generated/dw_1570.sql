WITH dept_enroll AS (
    SELECT d.DEPARTMENT_CODE,
           SUM(s.NUM_ENROLLED_STUDENTS) AS total_enrolled
    FROM SUBJECT_OFFERED_SUMMARY s
    JOIN SIS_DEPARTMENT d
      ON s.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
    GROUP BY d.DEPARTMENT_CODE
),
enroll_stats AS (
    SELECT AVG(total_enrolled) AS avg_enrolled,
           STDDEV(total_enrolled) AS sd_enrolled
    FROM dept_enroll
),
math_branch AS (
    SELECT de.DEPARTMENT_CODE,
           d.DEPARTMENT_NAME,
           de.total_enrolled AS total_enrolled_students,
           CAST(NULL AS SIGNED) AS total_unique_course_titles,
           'High Enrollment Mathematics' AS reason_for_inclusion
    FROM dept_enroll de
    JOIN SIS_DEPARTMENT d
      ON d.DEPARTMENT_CODE = de.DEPARTMENT_CODE
    CROSS JOIN enroll_stats es
    WHERE d.DEPARTMENT_NAME = 'Mathematics'
      AND de.total_enrolled > es.avg_enrolled + es.sd_enrolled
),
catalog_counts AS (
    SELECT c.DEPARTMENT_CODE,
           COUNT(DISTINCT c.SUBJECT_TITLE) AS unique_course_titles
    FROM CIS_COURSE_CATALOG c
    GROUP BY c.DEPARTMENT_CODE
),
degree_branch AS (
    SELECT d.DEPARTMENT_CODE,
           d.DEPARTMENT_NAME,
           CAST(NULL AS SIGNED) AS total_enrolled_students,
           cc.unique_course_titles AS total_unique_course_titles,
           'Degree-Granting with Many Courses' AS reason_for_inclusion
    FROM SIS_DEPARTMENT d
    JOIN catalog_counts cc
      ON cc.DEPARTMENT_CODE = d.DEPARTMENT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_CODE <> '6'
      AND d.DEPARTMENT_NAME <> 'Electrical Eng & Computer Sci'
      AND cc.unique_course_titles >= 5
)
SELECT DEPARTMENT_CODE, DEPARTMENT_NAME, total_enrolled_students, total_unique_course_titles, reason_for_inclusion
FROM math_branch
UNION ALL
SELECT DEPARTMENT_CODE, DEPARTMENT_NAME, total_enrolled_students, total_unique_course_titles, reason_for_inclusion
FROM degree_branch