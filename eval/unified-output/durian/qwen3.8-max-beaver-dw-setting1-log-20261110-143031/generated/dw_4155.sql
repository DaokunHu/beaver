WITH inner_cte1 AS (
  SELECT t1.SUBJECT_CODE, t1.SUBJECT_CODE_DESC, t0.DEPARTMENT_NAME, t1.SCHOOL_NAME
  FROM SIS_DEPARTMENT t0
  JOIN SIS_SUBJECT_CODE t1 ON t0.SCHOOL_CODE = t1.SCHOOL_CODE
  WHERE t0.IS_DEGREE_GRANTING = 'Y'
),
SubjectCodeVisibility AS (
  SELECT SUBJECT_CODE, SUBJECT_CODE_DESC, DEPARTMENT_NAME, SCHOOL_NAME,
         CASE WHEN SUBJECT_CODE_DESC IS NOT NULL AND SUBJECT_CODE_DESC <> 'nan'
              THEN 'Has Description' ELSE 'No Description' END AS description_status
  FROM inner_cte1
),
RollupResults AS (
  SELECT SCHOOL_NAME, description_status, COUNT(*) AS total_subject_codes
  FROM SubjectCodeVisibility
  GROUP BY SCHOOL_NAME, description_status WITH ROLLUP
  HAVING COUNT(*) > 0
),
inner_cte2 AS (
  SELECT t1.SUBJECT_ID, t1.TOTAL_UNITS, t1.SUBJECT_CODE,
         DENSE_RANK() OVER (ORDER BY t1.TOTAL_UNITS ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS window_column
  FROM ACADEMIC_TERMS_ALL t0
  JOIN COURSE_CATALOG_SUBJECT_OFFERED t1 ON t0.TERM_CODE = t1.TERM_CODE
  WHERE t0.TERM_CODE = '2022SU'
)
SELECT scv.SUBJECT_CODE,
       scv.SUBJECT_CODE_DESC,
       scv.DEPARTMENT_NAME,
       rr.SCHOOL_NAME,
       rr.description_status,
       rr.total_subject_codes,
       ic2.SUBJECT_ID,
       ic2.TOTAL_UNITS,
       ic2.window_column
FROM RollupResults rr
LEFT JOIN (
  SELECT DISTINCT SUBJECT_CODE, SUBJECT_CODE_DESC, DEPARTMENT_NAME, SCHOOL_NAME, description_status
  FROM SubjectCodeVisibility
) scv ON rr.SCHOOL_NAME = scv.SCHOOL_NAME AND rr.description_status = scv.description_status
LEFT JOIN inner_cte2 ic2 ON scv.SUBJECT_CODE = ic2.SUBJECT_CODE
ORDER BY rr.SCHOOL_NAME, rr.description_status, ic2.TOTAL_UNITS DESC