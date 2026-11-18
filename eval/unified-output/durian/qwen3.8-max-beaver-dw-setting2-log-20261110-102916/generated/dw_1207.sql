WITH subject_cv AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           STDDEV(ccso.TOTAL_UNITS) / AVG(ccso.TOTAL_UNITS) AS cv_total_units_subjects
    FROM COURSE_CATALOG_SUBJECT_OFFERED ccso
    JOIN ACADEMIC_TERMS_ALL ata ON ccso.TERM_CODE = ata.TERM_CODE
    WHERE ccso.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
),
library_cv AS (
    SELECT ata.ACADEMIC_YEAR,
           STDDEV(ccso.TOTAL_UNITS) / AVG(ccso.TOTAL_UNITS) AS cv_total_units_library
    FROM LIBRARY_RESERVE_MATRL_DETAIL lrm
    JOIN ACADEMIC_TERMS_ALL ata ON lrm.TERM_CODE = ata.TERM_CODE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso
      ON ccso.TERM_CODE = lrm.TERM_CODE
     AND ccso.SUBJECT_ID = lrm.SUBJECT_ID
    WHERE lrm.LIBRARY_MATERIAL_STATUS_KEY = 'U'
      AND ccso.DEPARTMENT_NAME = 'Mathematics'
    GROUP BY ata.ACADEMIC_YEAR
)
SELECT s.ACADEMIC_YEAR_DESC,
       s.cv_total_units_subjects,
       l.cv_total_units_library
FROM subject_cv s
LEFT JOIN library_cv l ON s.ACADEMIC_YEAR = l.ACADEMIC_YEAR
ORDER BY s.ACADEMIC_YEAR_DESC