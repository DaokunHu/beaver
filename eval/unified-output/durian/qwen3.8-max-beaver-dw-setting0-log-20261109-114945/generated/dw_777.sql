WITH ChemistryEnrollment AS (
    SELECT t.OFFER_DEPT_NAME AS DEPARTMENT_NAME,
           AVG(t.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
           VARIANCE(t.NUM_ENROLLED_STUDENTS) AS enrollment_variance
    FROM TIP_SUBJECT_OFFERED t
    JOIN TIP_DETAIL d ON t.TIP_SUBJECT_OFFERED_KEY = d.TIP_SUBJECT_OFFERED_KEY
    WHERE t.OFFER_DEPT_NAME = 'Chemistry'
    GROUP BY t.OFFER_DEPT_NAME
),
DegreeDeptUnits AS (
    SELECT sd.DEPARTMENT_NAME,
           AVG(c.TOTAL_UNITS) AS avg_total_units,
           VARIANCE(c.TOTAL_UNITS) AS total_units_variance
    FROM SIS_DEPARTMENT sd
    JOIN COURSE_CATALOG_SUBJECT_OFFERED c ON sd.DEPARTMENT_CODE = c.DEPARTMENT_CODE
    WHERE c.ACADEMIC_YEAR = 2022
      AND sd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_CODE <> '7'
    GROUP BY sd.DEPARTMENT_NAME
)
SELECT DEPARTMENT_NAME,
       avg_enrollment,
       enrollment_variance,
       NULL AS avg_total_units,
       NULL AS total_units_variance,
       'ChemistryEnrollment' AS reason_for_inclusion
FROM ChemistryEnrollment
UNION ALL
SELECT DEPARTMENT_NAME,
       NULL AS avg_enrollment,
       NULL AS enrollment_variance,
       avg_total_units,
       total_units_variance,
       'DegreeDeptUnits' AS reason_for_inclusion
FROM DegreeDeptUnits
ORDER BY DEPARTMENT_NAME, reason_for_inclusion