WITH cv_units AS (
  SELECT ata.ACADEMIC_YEAR,
         ata.ACADEMIC_YEAR_DESC,
         STDDEV(ccso.TOTAL_UNITS) / AVG(ccso.TOTAL_UNITS) AS coefficient_of_variation
  FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
  JOIN ACADEMIC_TERMS_ALL ata ON ccso.TERM_CODE = ata.TERM_CODE
  WHERE ccso.DEPARTMENT_NAME = 'Mathematics'
    AND ccso.IS_OFFERED_FALL_TERM = 'Y'
    AND ccso.TOTAL_UNITS > 0
  GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
),
enroll_stats AS (
  SELECT at.ACADEMIC_YEAR,
         MAX(tso.NUM_ENROLLED_STUDENTS) - MIN(tso.NUM_ENROLLED_STUDENTS) AS enrolled_range,
         VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrolled_variance
  FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
  JOIN ACADEMIC_TERMS at ON ccso.TERM_CODE = at.TERM_CODE
  JOIN TIP_SUBJECT_OFFERED tso ON at.TERM_CODE = tso.TERM_CODE
  WHERE ccso.IS_OFFERED_FALL_TERM = 'Y'
    AND tso.NUM_ENROLLED_STUDENTS > 0
    AND ccso.DEPARTMENT_NAME = 'Mathematics'
  GROUP BY at.ACADEMIC_YEAR
)
SELECT cv.ACADEMIC_YEAR,
       cv.ACADEMIC_YEAR_DESC,
       cv.coefficient_of_variation,
       es.enrolled_range,
       es.enrolled_variance
FROM cv_units cv
JOIN enroll_stats es ON cv.ACADEMIC_YEAR = es.ACADEMIC_YEAR
ORDER BY cv.ACADEMIC_YEAR