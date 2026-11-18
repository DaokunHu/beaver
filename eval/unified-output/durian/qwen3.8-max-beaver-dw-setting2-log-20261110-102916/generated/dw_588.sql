WITH base AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           lso.SUBJECT_ID,
           lso.SUBJECT_TITLE,
           lso.NUM_ENROLLED_STUDENTS
    FROM LIBRARY_SUBJECT_OFFERED lso
    JOIN ACADEMIC_TERMS_ALL ata
        ON lso.TERM_CODE = ata.TERM_CODE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
        ON lso.TERM_CODE = ccso.TERM_CODE
       AND lso.SUBJECT_ID = ccso.SUBJECT_ID
    WHERE ccso.DEPARTMENT_NAME = 'Mathematics'
      AND ccso.IS_OFFERED_FALL_TERM = 'Y'
),
year_stats AS (
    SELECT ACADEMIC_YEAR,
           ACADEMIC_YEAR_DESC,
           STDDEV(NUM_ENROLLED_STUDENTS) AS stddev_num_enrolled_students
    FROM base
    GROUP BY ACADEMIC_YEAR, ACADEMIC_YEAR_DESC
    HAVING COUNT(*) > 5
),
top_subject AS (
    SELECT ACADEMIC_YEAR,
           SUBJECT_ID,
           SUBJECT_TITLE,
           NUM_ENROLLED_STUDENTS,
           ROW_NUMBER() OVER (PARTITION BY ACADEMIC_YEAR
                              ORDER BY NUM_ENROLLED_STUDENTS DESC) AS rn
    FROM base
)
SELECT ys.ACADEMIC_YEAR_DESC,
       ys.stddev_num_enrolled_students,
       ts.SUBJECT_ID,
       ts.SUBJECT_TITLE,
       ts.NUM_ENROLLED_STUDENTS
FROM year_stats ys
JOIN top_subject ts
    ON ys.ACADEMIC_YEAR = ts.ACADEMIC_YEAR
   AND ts.rn = 1
ORDER BY ys.stddev_num_enrolled_students DESC
LIMIT 10;