WITH inner_cte AS (
    SELECT t1.FULL_NAME,
           t1.EMAIL_ADDRESS,
           t0.DEPARTMENT_FULL_NAME,
           t0.DEPARTMENT_CODE
    FROM SIS_DEPARTMENT t0
    JOIN MIT_STUDENT_DIRECTORY t1
        ON t0.DEPARTMENT_CODE = t1.DEPARTMENT
    WHERE t0.IS_DEGREE_GRANTING = 'Y'
      AND t1.STUDENT_YEAR = 'G'
),
school_agg AS (
    SELECT lso.OFFER_DEPT_CODE,
           lso.OFFER_SCHOOL_NAME,
           MIN(lso.NUM_ENROLLED_STUDENTS) AS min_enrolled_students,
           SUM(sos.TOTAL_UNITS) AS total_units
    FROM LIBRARY_SUBJECT_OFFERED lso
    JOIN TIP_DETAIL td
        ON lso.SUBJECT_ID = td.SUBJECT_ID
    JOIN SUBJECT_OFFERED_SUMMARY sos
        ON td.SUBJECT_ID = sos.SUBJECT_ID
    WHERE td.TIP_MATERIAL_STATUS_KEY = 'RQ'
    GROUP BY lso.OFFER_DEPT_CODE, lso.OFFER_SCHOOL_NAME
)
SELECT i.FULL_NAME,
       i.EMAIL_ADDRESS,
       i.DEPARTMENT_FULL_NAME,
       LENGTH(i.FULL_NAME) - avg_len.avg_full_name_length AS diff_from_avg_length,
       sa.OFFER_SCHOOL_NAME,
       sa.min_enrolled_students,
       sa.total_units
FROM inner_cte i
JOIN (
    SELECT AVG(LENGTH(FULL_NAME)) AS avg_full_name_length
    FROM inner_cte
) avg_len ON 1 = 1
JOIN school_agg sa
    ON sa.OFFER_DEPT_CODE = i.DEPARTMENT_CODE