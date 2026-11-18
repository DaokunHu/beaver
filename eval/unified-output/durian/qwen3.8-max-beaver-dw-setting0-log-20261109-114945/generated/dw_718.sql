WITH unit_stats AS (
    SELECT at.ACADEMIC_YEAR,
           at.ACADEMIC_YEAR_DESC,
           STDDEV(sos.TOTAL_UNITS) / AVG(sos.TOTAL_UNITS) AS cv_total_units
    FROM SUBJECT_OFFERED_SUMMARY sos
    JOIN ACADEMIC_TERMS at ON sos.TERM_CODE = at.TERM_CODE
    WHERE sos.OFFER_DEPT_NAME = 'Mathematics'
      AND sos.TERM_CODE LIKE '%FA'
      AND sos.TOTAL_UNITS > 0
    GROUP BY at.ACADEMIC_YEAR, at.ACADEMIC_YEAR_DESC
),
enroll_stats AS (
    SELECT at.ACADEMIC_YEAR,
           MAX(sos.NUM_ENROLLED_STUDENTS) - MIN(sos.NUM_ENROLLED_STUDENTS) AS range_enrolled_students,
           VARIANCE(sos.NUM_ENROLLED_STUDENTS) AS variance_enrolled_students
    FROM SUBJECT_OFFERED_SUMMARY sos
    JOIN ACADEMIC_TERMS at ON sos.TERM_CODE = at.TERM_CODE
    WHERE sos.OFFER_DEPT_NAME = 'Mathematics'
      AND sos.TERM_CODE LIKE '%FA'
      AND sos.NUM_ENROLLED_STUDENTS > 0
    GROUP BY at.ACADEMIC_YEAR
)
SELECT u.ACADEMIC_YEAR,
       u.ACADEMIC_YEAR_DESC,
       u.cv_total_units,
       e.range_enrolled_students,
       e.variance_enrolled_students
FROM unit_stats u
JOIN enroll_stats e ON u.ACADEMIC_YEAR = e.ACADEMIC_YEAR
ORDER BY u.ACADEMIC_YEAR