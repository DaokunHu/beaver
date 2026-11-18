WITH DeptEnrollmentStats AS (
  SELECT scd.DEPARTMENT_NAME,
         AVG(sos.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
         VARIANCE(sos.NUM_ENROLLED_STUDENTS) AS enrollment_variance,
         COUNT(sos.SUBJECT_ID) AS total_subjects_offered
  FROM SIS_COURSE_DESCRIPTION scd
  JOIN SUBJECT_OFFERED_SUMMARY sos ON scd.COURSE = sos.COURSE_NUMBER
  WHERE sos.NUM_ENROLLED_STUDENTS > 0
    AND scd.IS_DEGREE_GRANTING = 'Y'
    AND scd.DEPARTMENT_NAME != 'Political Science'
  GROUP BY scd.DEPARTMENT_NAME
),
DeptCoefficientOfVariation AS (
  SELECT sd.DEPARTMENT_NAME,
         STDDEV_SAMP(sos.NUM_ENROLLED_STUDENTS) / AVG(sos.NUM_ENROLLED_STUDENTS) AS coefficient_of_variation,
         COUNT(sos.SUBJECT_ID) AS total_subjects_offered
  FROM SIS_DEPARTMENT sd
  JOIN SUBJECT_OFFERED_SUMMARY sos ON sd.DEPARTMENT_CODE = sos.OFFER_DEPT_CODE
  WHERE sos.NUM_ENROLLED_STUDENTS > 0
    AND sd.DEPARTMENT_NAME <> 'Chemistry'
  GROUP BY sd.DEPARTMENT_NAME
  HAVING COUNT(sos.NUM_ENROLLED_STUDENTS) > 1
),
CombinedDeptStats AS (
  SELECT d1.DEPARTMENT_NAME,
         d1.avg_enrollment,
         d1.enrollment_variance,
         NULL AS coefficient_of_variation,
         d1.total_subjects_offered,
         'Avg/Var' AS Reason
  FROM DeptEnrollmentStats d1
  UNION ALL
  SELECT d2.DEPARTMENT_NAME,
         NULL AS avg_enrollment,
         NULL AS enrollment_variance,
         d2.coefficient_of_variation,
         d2.total_subjects_offered,
         'CoeffVar' AS Reason
  FROM DeptCoefficientOfVariation d2
)
SELECT DEPARTMENT_NAME, avg_enrollment, enrollment_variance, coefficient_of_variation, total_subjects_offered, Reason
FROM CombinedDeptStats
ORDER BY DEPARTMENT_NAME, Reason