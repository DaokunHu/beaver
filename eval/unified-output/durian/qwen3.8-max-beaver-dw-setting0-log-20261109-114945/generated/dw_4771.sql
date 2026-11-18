WITH Subquery1 AS (
    SELECT sd.DEPARTMENT_NAME,
           MAX(tso.NUM_ENROLLED_STUDENTS) - MIN(tso.NUM_ENROLLED_STUDENTS) AS enrolled_range,
           VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrolled_variance,
           sd.DEPARTMENT_CODE
    FROM TIP_SUBJECT_OFFERED tso
    JOIN SIS_DEPARTMENT sd ON tso.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    JOIN SIS_COURSE_DESCRIPTION scd ON sd.DEPARTMENT_CODE = scd.DEPARTMENT
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND scd.COURSE_LEVEL = 'G'
    GROUP BY sd.DEPARTMENT_NAME, sd.DEPARTMENT_CODE
),
Subquery2 AS (
    SELECT tso.OFFER_DEPT_NAME,
           tso.OFFER_SCHOOL_NAME,
           COUNT(DISTINCT td.SUBJECT_ID) AS num_subject_ids,
           MIN(td.ISBN) AS min_isbn,
           AVG(tso.NUM_ENROLLED_STUDENTS) AS avg_enrolled_students
    FROM TIP_DETAIL td
    JOIN TIP_SUBJECT_OFFERED tso ON td.TIP_SUBJECT_OFFERED_KEY = tso.TIP_SUBJECT_OFFERED_KEY
    WHERE tso.NUM_ENROLLED_STUDENTS > 2
    GROUP BY tso.OFFER_DEPT_NAME, tso.OFFER_SCHOOL_NAME
)
SELECT s1.DEPARTMENT_NAME,
       s1.enrolled_range,
       s1.enrolled_variance,
       s2.num_subject_ids,
       s2.min_isbn,
       s2.avg_enrolled_students
FROM Subquery1 s1
JOIN Subquery2 s2 ON s1.DEPARTMENT_NAME = s2.OFFER_DEPT_NAME