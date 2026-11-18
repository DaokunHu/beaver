WITH inner_cte AS (
    SELECT l.SUBJECT_TITLE,
           l.NUM_ENROLLED_STUDENTS,
           t.RESPONSIBLE_FACULTY_NAME,
           t.OFFER_DEPT_NAME,
           MIN(l.NUM_ENROLLED_STUDENTS) OVER (
               ORDER BY t.RESPONSIBLE_FACULTY_MIT_ID
               ROWS BETWEEN 3 PRECEDING AND 1 FOLLOWING
           ) AS window_column
    FROM LIBRARY_SUBJECT_OFFERED l
    JOIN TIP_SUBJECT_OFFERED t ON l.TERM_CODE = t.TERM_CODE
    WHERE l.TERM_CODE = '2014FA'
      AND t.OFFER_DEPT_NAME = 'Chemistry'
),
chem_total AS (
    SELECT COUNT(*) AS total_chemistry_subjects
    FROM TIP_SUBJECT_OFFERED
    WHERE TERM_CODE = '2014FA'
      AND OFFER_DEPT_NAME = 'Chemistry'
),
iap_yearly AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           VARIANCE(isd.MAX_ENROLLMENT) AS max_enrollment_variance,
           STDDEV(isd.MAX_ENROLLMENT) AS max_enrollment_stddev,
           ccso.DEPARTMENT_NAME
    FROM IAP_SUBJECT_DETAIL isd
    JOIN ACADEMIC_TERMS_ALL ata ON isd.TERM_CODE = ata.TERM_CODE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON ata.TERM_CODE = ccso.TERM_CODE
    WHERE isd.ENROLLMENT_TYPE = 'Advance sign-up required'
      AND isd.IS_CANCELLED = 'N'
      AND isd.MAX_ENROLLMENT IS NOT NULL
      AND ccso.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC, ccso.DEPARTMENT_NAME
),
rollup_results AS (
    SELECT DEPARTMENT_NAME,
           ACADEMIC_YEAR_DESC,
           SUM(max_enrollment_variance) AS total_variance,
           SUM(max_enrollment_stddev) AS total_stddev
    FROM iap_yearly
    GROUP BY DEPARTMENT_NAME, ACADEMIC_YEAR_DESC WITH ROLLUP
    HAVING SUM(max_enrollment_variance) IS NOT NULL
)
SELECT c.SUBJECT_TITLE,
       c.NUM_ENROLLED_STUDENTS,
       c.RESPONSIBLE_FACULTY_NAME,
       c.OFFER_DEPT_NAME,
       c.window_column,
       ct.total_chemistry_subjects,
       rr.DEPARTMENT_NAME,
       rr.ACADEMIC_YEAR_DESC,
       rr.total_variance,
       rr.total_stddev
FROM inner_cte c
CROSS JOIN chem_total ct
CROSS JOIN rollup_results rr