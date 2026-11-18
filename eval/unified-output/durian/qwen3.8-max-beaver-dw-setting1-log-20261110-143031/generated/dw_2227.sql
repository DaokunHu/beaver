WITH TermStats AS (
  SELECT
    at.ACADEMIC_YEAR,
    at.ACADEMIC_YEAR_DESC,
    at.TERM_CODE,
    MAX(ccso.TOTAL_UNITS) - MIN(ccso.TOTAL_UNITS) AS range_total_units,
    VARIANCE(ccso.TOTAL_UNITS) AS variance_total_units,
    STDDEV(ccso.TOTAL_UNITS) AS stddev_total_units,
    COUNT(ccso.SUBJECT_ID) AS num_math_subjects_offered
  FROM ACADEMIC_TERMS at
  JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON at.TERM_CODE = ccso.TERM_CODE
  WHERE at.IS_REGULAR_TERM = 'Y'
    AND at.TERM_STATUS <> 'Future'
    AND ccso.DEPARTMENT_NAME = 'Mathematics'
  GROUP BY at.ACADEMIC_YEAR, at.ACADEMIC_YEAR_DESC, at.TERM_CODE
),
EffectiveTermStats AS (
  SELECT
    atp.TERM_CODE AS academic_term_parameter_code,
    atp.TERM_DESCRIPTION,
    AVG(ccso.TOTAL_UNITS) AS avg_total_units,
    VARIANCE(ccso.TOTAL_UNITS) AS variance_total_units_effective,
    MAX(ccso.TOTAL_UNITS) AS max_total_units_effective
  FROM ACADEMIC_TERM_PARAMETER atp
  JOIN ACADEMIC_TERMS at ON atp.TERM_CODE = at.TERM_CODE
  JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON at.TERM_CODE = ccso.EFFECTIVE_TERM_CODE
  WHERE ccso.IS_OFFERED_THIS_YEAR = 'Y'
    AND ccso.DEPARTMENT_NAME = 'Mathematics'
  GROUP BY atp.TERM_CODE, atp.TERM_DESCRIPTION
)
SELECT
  ts.ACADEMIC_YEAR,
  ts.ACADEMIC_YEAR_DESC,
  ts.TERM_CODE,
  ts.range_total_units,
  ts.variance_total_units,
  ts.stddev_total_units,
  ets.academic_term_parameter_code,
  ets.TERM_DESCRIPTION,
  ets.avg_total_units,
  ets.variance_total_units_effective,
  ts.num_math_subjects_offered,
  ets.max_total_units_effective
FROM TermStats ts
JOIN EffectiveTermStats ets ON ts.TERM_CODE = ets.academic_term_parameter_code