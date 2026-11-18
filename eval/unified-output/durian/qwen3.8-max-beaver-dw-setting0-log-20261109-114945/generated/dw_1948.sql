WITH AvgVarStats AS (
    SELECT sd.DEPARTMENT_NAME,
           AVG(tso.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
           VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrollment_variance,
           COUNT(tso.TIP_SUBJECT_OFFERED_KEY) AS total_subjects_offered
    FROM SIS_DEPARTMENT sd
    JOIN TIP_SUBJECT_OFFERED tso ON sd.DEPARTMENT_CODE = tso.OFFER_DEPT_CODE
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPARTMENT_NAME <> 'Political Science'
    GROUP BY sd.DEPARTMENT_NAME
),
CoeffVarStats AS (
    SELECT sd.DEPARTMENT_NAME,
           STDDEV(tso.NUM_ENROLLED_STUDENTS) / NULLIF(AVG(tso.NUM_ENROLLED_STUDENTS), 0) AS coefficient_of_variation,
           COUNT(tso.TIP_SUBJECT_OFFERED_KEY) AS total_subjects_offered
    FROM SIS_DEPARTMENT sd
    JOIN TIP_SUBJECT_OFFERED tso ON sd.DEPARTMENT_CODE = tso.OFFER_DEPT_CODE
    WHERE sd.DEPARTMENT_NAME <> 'Chemistry'
    GROUP BY sd.DEPARTMENT_NAME
)
SELECT DEPARTMENT_NAME,
       avg_enrollment,
       enrollment_variance,
       NULL AS coefficient_of_variation,
       total_subjects_offered,
       'Avg/Var' AS reason
FROM AvgVarStats
UNION ALL
SELECT DEPARTMENT_NAME,
       NULL AS avg_enrollment,
       NULL AS enrollment_variance,
       coefficient_of_variation,
       total_subjects_offered,
       'CoeffVar' AS reason
FROM CoeffVarStats
ORDER BY DEPARTMENT_NAME, reason