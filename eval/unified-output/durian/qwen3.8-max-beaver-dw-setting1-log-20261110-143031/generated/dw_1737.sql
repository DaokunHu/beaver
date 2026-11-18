WITH dept_stats AS (
    SELECT ss.DEPARTMENT_NAME,
           COUNT(ss.SUBJECT_ID) AS total_subjects,
           AVG(ss.TOTAL_UNITS) AS avg_total_units
    FROM SUBJECT_SUMMARY ss
    JOIN ACADEMIC_TERMS t ON ss.TERM_CODE = t.TERM_CODE
    WHERE t.TERM_CODE = '2019FA'
      AND ss.DEPARTMENT_NAME IS NOT NULL
      AND ss.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY ss.DEPARTMENT_NAME
),
term_enroll_avg AS (
    SELECT sc.DEPARTMENT_NAME,
           l.TERM_CODE,
           AVG(l.NUM_ENROLLED_STUDENTS) AS avg_enrolled
    FROM LIBRARY_SUBJECT_OFFERED l
    JOIN SIS_SUBJECT_CODE sc ON l.COURSE_NUMBER = sc.COURSE_NUMBER
    WHERE l.NUM_ENROLLED_STUDENTS > 0
      AND sc.DEPARTMENT_NAME IS NOT NULL
      AND sc.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY sc.DEPARTMENT_NAME, l.TERM_CODE
),
highest_enroll AS (
    SELECT DEPARTMENT_NAME,
           MAX(avg_enrolled) AS highest_avg_enrolled
    FROM term_enroll_avg
    GROUP BY DEPARTMENT_NAME
)
SELECT CASE WHEN GROUPING(d.DEPARTMENT_NAME) = 1 THEN NULL ELSE d.DEPARTMENT_NAME END AS DEPARTMENT_NAME,
       SUM(d.total_subjects) AS total_subjects,
       AVG(d.avg_total_units) AS avg_total_units,
       CASE WHEN GROUPING(d.DEPARTMENT_NAME) = 1 THEN NULL ELSE MAX(h.highest_avg_enrolled) END AS highest_avg_enrolled_students
FROM dept_stats d
LEFT JOIN highest_enroll h ON d.DEPARTMENT_NAME = h.DEPARTMENT_NAME
GROUP BY d.DEPARTMENT_NAME WITH ROLLUP