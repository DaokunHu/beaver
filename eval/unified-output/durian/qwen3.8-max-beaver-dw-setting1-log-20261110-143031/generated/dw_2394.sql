WITH chem_cip AS (
    SELECT d.DEPARTMENT_NAME,
           MAX(c.CIP_PROGRAM_CODE) AS max_cip_code,
           d.DEPARTMENT_FULL_NAME
    FROM SIS_COURSE_DESCRIPTION c
    JOIN SIS_DEPARTMENT d ON c.DEPARTMENT = d.DEPARTMENT_CODE
    JOIN SIS_ADMIN_DEPARTMENT ad ON ad.SIS_ADMIN_DEPARTMENT_CODE = d.DEPARTMENT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPARTMENT_NAME <> 'Mathematics'
      AND d.DEPARTMENT_NAME = 'Chemistry'
    GROUP BY d.DEPARTMENT_NAME, d.DEPARTMENT_FULL_NAME
    HAVING MAX(c.CIP_PROGRAM_CODE) > 120000
),
enroll_base AS (
    SELECT t0.TERM_CODE,
           t0.OFFER_DEPT_NAME,
           t0.NUM_ENROLLED_STUDENTS
    FROM TIP_SUBJECT_OFFERED t0
    JOIN TIP_DETAIL t1 ON t0.SUBJECT_ID = t1.SUBJECT_ID
    WHERE t0.OFFER_DEPT_NAME = 'Chemistry'
      AND t1.TIP_MATERIAL_STATUS_KEY <> 'NM'
),
rollup_tbl AS (
    SELECT CASE WHEN GROUPING(TERM_CODE) = 1 AND GROUPING(OFFER_DEPT_NAME) = 1 THEN 'zzz' ELSE TERM_CODE END AS term_sort,
           CASE WHEN GROUPING(TERM_CODE) = 0 AND GROUPING(OFFER_DEPT_NAME) = 1 THEN 'SUBTOTAL'
                WHEN GROUPING(TERM_CODE) = 1 AND GROUPING(OFFER_DEPT_NAME) = 1 THEN 'TOTAL'
                ELSE TERM_CODE END AS term,
           CASE WHEN GROUPING(TERM_CODE) = 0 AND GROUPING(OFFER_DEPT_NAME) = 1 THEN 'zzz' ELSE OFFER_DEPT_NAME END AS dept_sort,
           OFFER_DEPT_NAME AS dept,
           AVG(NUM_ENROLLED_STUDENTS) AS avg_enrolled_students,
           STDDEV(NUM_ENROLLED_STUDENTS) AS stddev_enrolled_students
    FROM enroll_base
    GROUP BY TERM_CODE, OFFER_DEPT_NAME WITH ROLLUP
)
SELECT CASE WHEN LAG(r.term) OVER (ORDER BY r.term_sort, r.term, r.dept_sort) = r.term THEN NULL ELSE r.term END AS term,
       r.dept AS department_name,
       r.avg_enrolled_students,
       r.stddev_enrolled_students,
       cc.max_cip_code,
       cc.DEPARTMENT_FULL_NAME
FROM rollup_tbl r
CROSS JOIN chem_cip cc
ORDER BY r.term_sort, r.dept_sort