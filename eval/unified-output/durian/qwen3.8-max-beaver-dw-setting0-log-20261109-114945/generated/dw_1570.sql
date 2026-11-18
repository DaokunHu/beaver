WITH dept_enrollment AS (
    SELECT sos.OFFER_DEPT_CODE,
           SUM(sos.NUM_ENROLLED_STUDENTS) AS total_enrolled
    FROM SUBJECT_OFFERED_SUMMARY sos
    GROUP BY sos.OFFER_DEPT_CODE
),
math_branch AS (
    SELECT sd.DEPARTMENT_CODE,
           sd.DEPARTMENT_NAME,
           de.total_enrolled AS total_enrolled_students,
           NULL AS total_unique_course_titles,
           'High Enrollment Mathematics' AS reason_for_inclusion
    FROM SIS_DEPARTMENT sd
    JOIN dept_enrollment de ON de.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    WHERE sd.DEPARTMENT_NAME = 'Mathematics'
      AND de.total_enrolled > (
            SELECT AVG(d2.total_enrolled) + STDDEV(d2.total_enrolled)
            FROM dept_enrollment d2
      )
),
catalog_branch AS (
    SELECT sd.DEPARTMENT_CODE,
           sd.DEPARTMENT_NAME,
           NULL AS total_enrolled_students,
           COUNT(DISTINCT ccso.SUBJECT_TITLE) AS total_unique_course_titles,
           'Degree-Granting with Many Courses' AS reason_for_inclusion
    FROM SIS_DEPARTMENT sd
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
      ON ccso.DEPARTMENT_CODE = sd.DEPARTMENT_CODE
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_NAME != 'Electrical Eng & Computer Sci'
    GROUP BY sd.DEPARTMENT_CODE, sd.DEPARTMENT_NAME
    HAVING COUNT(DISTINCT ccso.SUBJECT_TITLE) >= 5
)
SELECT DEPARTMENT_CODE, DEPARTMENT_NAME, total_enrolled_students, total_unique_course_titles, reason_for_inclusion
FROM math_branch
UNION ALL
SELECT DEPARTMENT_CODE, DEPARTMENT_NAME, total_enrolled_students, total_unique_course_titles, reason_for_inclusion
FROM catalog_branch