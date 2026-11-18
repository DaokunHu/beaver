WITH YearStats AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           STDDEV(lso.NUM_ENROLLED_STUDENTS) AS stddev_num_enrolled_students
    FROM LIBRARY_SUBJECT_OFFERED lso
    JOIN ACADEMIC_TERMS_ALL ata
        ON lso.TERM_CODE = ata.TERM_CODE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
        ON lso.TERM_CODE = ccso.TERM_CODE
       AND lso.SUBJECT_ID = ccso.SUBJECT_ID
    WHERE ccso.DEPARTMENT_NAME = 'Mathematics'
      AND ccso.IS_OFFERED_FALL_TERM = 'Y'
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
    HAVING COUNT(*) > 5
),
Top10Years AS (
    SELECT ACADEMIC_YEAR, ACADEMIC_YEAR_DESC, stddev_num_enrolled_students
    FROM YearStats
    ORDER BY stddev_num_enrolled_students DESC
    LIMIT 10
),
TopSubject AS (
    SELECT ata.ACADEMIC_YEAR,
           lso.SUBJECT_ID,
           lso.SUBJECT_TITLE,
           lso.NUM_ENROLLED_STUDENTS,
           ROW_NUMBER() OVER (
               PARTITION BY ata.ACADEMIC_YEAR
               ORDER BY lso.NUM_ENROLLED_STUDENTS DESC
           ) AS rn
    FROM LIBRARY_SUBJECT_OFFERED lso
    JOIN ACADEMIC_TERMS_ALL ata
        ON lso.TERM_CODE = ata.TERM_CODE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
        ON lso.TERM_CODE = ccso.TERM_CODE
       AND lso.SUBJECT_ID = ccso.SUBJECT_ID
    WHERE ccso.DEPARTMENT_NAME = 'Mathematics'
      AND ccso.IS_OFFERED_FALL_TERM = 'Y'
)
SELECT t.ACADEMIC_YEAR_DESC,
       t.stddev_num_enrolled_students,
       ts.SUBJECT_ID,
       ts.SUBJECT_TITLE,
       ts.NUM_ENROLLED_STUDENTS
FROM Top10Years t
JOIN TopSubject ts
    ON t.ACADEMIC_YEAR = ts.ACADEMIC_YEAR
   AND ts.rn = 1
ORDER BY t.stddev_num_enrolled_students DESC;