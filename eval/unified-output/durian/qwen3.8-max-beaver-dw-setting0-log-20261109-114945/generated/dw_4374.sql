WITH year_desc AS (
  SELECT DISTINCT ACADEMIC_YEAR, ACADEMIC_YEAR_DESC
  FROM ACADEMIC_TERMS_ALL
),
branch1 AS (
  SELECT scd.DEPARTMENT_NAME,
         ccso.ACADEMIC_YEAR,
         yd.ACADEMIC_YEAR_DESC,
         COUNT(*) AS subject_count,
         AVG(ccso.TOTAL_UNITS) AS avg_total_units,
         MAX(ccso.TOTAL_UNITS) - MIN(ccso.TOTAL_UNITS) AS total_units_range,
         VARIANCE(ccso.TOTAL_UNITS) AS total_units_variance
  FROM SIS_COURSE_DESCRIPTION scd
  JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON scd.COURSE = ccso.SUBJECT_CODE
  JOIN year_desc yd ON ccso.ACADEMIC_YEAR = yd.ACADEMIC_YEAR
  WHERE scd.IS_DEGREE_GRANTING = 'Y'
    AND ccso.ACADEMIC_YEAR = 2022
  GROUP BY scd.DEPARTMENT_NAME, ccso.ACADEMIC_YEAR, yd.ACADEMIC_YEAR_DESC
  HAVING COUNT(*) >= 5
),
branch2 AS (
  SELECT ccso.DEPARTMENT_NAME,
         ata.ACADEMIC_YEAR,
         ata.ACADEMIC_YEAR_DESC,
         STDDEV(ccso.TOTAL_UNITS) / NULLIF(AVG(ccso.TOTAL_UNITS), 0) AS coefficient_of_variation
  FROM LIBRARY_RESERVE_MATRL_DETAIL lrm
  JOIN ACADEMIC_TERMS_ALL ata ON lrm.TERM_CODE = ata.TERM_CODE
  JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
    ON lrm.TERM_CODE = ccso.TERM_CODE
   AND lrm.SUBJECT_ID = ccso.SUBJECT_ID
  WHERE lrm.LIBRARY_MATERIAL_STATUS_KEY = 'U'
  GROUP BY ccso.DEPARTMENT_NAME, ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
)
SELECT DEPARTMENT_NAME,
       ACADEMIC_YEAR,
       ACADEMIC_YEAR_DESC,
       subject_count,
       avg_total_units,
       total_units_range,
       total_units_variance,
       CAST(NULL AS DOUBLE) AS coefficient_of_variation,
       '2022 Degree-Granting Subjects' AS reason
FROM branch1
UNION ALL
SELECT DEPARTMENT_NAME,
       ACADEMIC_YEAR,
       ACADEMIC_YEAR_DESC,
       CAST(NULL AS SIGNED) AS subject_count,
       CAST(NULL AS DOUBLE) AS avg_total_units,
       CAST(NULL AS DOUBLE) AS total_units_range,
       CAST(NULL AS DOUBLE) AS total_units_variance,
       coefficient_of_variation,
       'Library Reserve Materials' AS reason
FROM branch2
ORDER BY DEPARTMENT_NAME, reason, ACADEMIC_YEAR