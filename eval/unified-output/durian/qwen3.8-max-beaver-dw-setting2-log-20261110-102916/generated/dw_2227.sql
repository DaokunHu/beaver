WITH academic_year_term_stats AS (
  SELECT at.ACADEMIC_YEAR,
         at.ACADEMIC_YEAR_DESC,
         at.TERM_CODE,
         MAX(ccso.TOTAL_UNITS) - MIN(ccso.TOTAL_UNITS) AS total_units_range,
         VARIANCE(ccso.TOTAL_UNITS) AS total_units_variance,
         STDDEV(ccso.TOTAL_UNITS) AS total_units_stddev,
         COUNT(ccso.SUBJECT_ID) AS num_math_subjects_offered
  FROM ACADEMIC_TERMS at
  JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON at.TERM_CODE = ccso.TERM_CODE
  WHERE at.IS_REGULAR_TERM = 'Y'
    AND at.TERM_STATUS <> 'Future'
    AND ccso.DEPARTMENT_NAME = 'Mathematics'
  GROUP BY at.ACADEMIC_YEAR, at.ACADEMIC_YEAR_DESC, at.TERM_CODE
),
academic_term_parameter_stats AS (
  SELECT atp.TERM_CODE AS academic_term_parameter,
         atp.TERM_DESCRIPTION,
         AVG(ccso.TOTAL_UNITS) AS avg_total_units,
         VARIANCE(ccso.TOTAL_UNITS) AS var_total_units,
         MAX(ccso.TOTAL_UNITS) AS max_total_units_effective_term
  FROM ACADEMIC_TERM_PARAMETER atp
  JOIN ACADEMIC_TERMS at ON atp.TERM_CODE = at.TERM_CODE
  JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON at.TERM_CODE = ccso.EFFECTIVE_TERM_CODE
  WHERE ccso.IS_OFFERED_THIS_YEAR = 'Y'
    AND ccso.DEPARTMENT_NAME = 'Mathematics'
  GROUP BY atp.TERM_CODE, atp.TERM_DESCRIPTION
)
SELECT ays.ACADEMIC_YEAR,
       ays.ACADEMIC_YEAR_DESC,
       ays.TERM_CODE,
       ays.total_units_range,
       ays.total_units_variance,
       ays.total_units_stddev,
       atps.academic_term_parameter,
       atps.TERM_DESCRIPTION,
       atps.avg_total_units,
       atps.var_total_units,
       ays.num_math_subjects_offered,
       atps.max_total_units_effective_term
FROM academic_year_term_stats ays
JOIN academic_term_parameter_stats atps ON ays.TERM_CODE = atps.academic_term_parameter
ORDER BY ays.ACADEMIC_YEAR, ays.TERM_CODE