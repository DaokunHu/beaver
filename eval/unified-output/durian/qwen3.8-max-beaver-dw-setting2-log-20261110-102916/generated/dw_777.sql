SELECT tso.OFFER_DEPT_NAME AS department_name,
       AVG(tso.NUM_ENROLLED_STUDENTS) AS avg_enrollment,
       VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrollment_variance,
       NULL AS avg_total_units,
       NULL AS var_total_units,
       'ChemistryEnrollment' AS reason_for_inclusion
FROM TIP_SUBJECT_OFFERED tso
JOIN TIP_DETAIL td ON tso.TERM_CODE = td.TERM_CODE
WHERE td.RECORD_COUNT > 0
  AND tso.OFFER_DEPT_NAME = 'Chemistry'
GROUP BY tso.OFFER_DEPT_NAME
UNION ALL
SELECT sd.DEPARTMENT_NAME AS department_name,
       NULL AS avg_enrollment,
       NULL AS enrollment_variance,
       AVG(ccso.TOTAL_UNITS) AS avg_total_units,
       VARIANCE(ccso.TOTAL_UNITS) AS var_total_units,
       'DegreeDeptUnits' AS reason_for_inclusion
FROM SIS_DEPARTMENT sd
JOIN COURSE_CATALOG_SUBJECT_OFFERED ccso ON sd.DEPARTMENT_CODE = ccso.DEPARTMENT_CODE
WHERE sd.IS_DEGREE_GRANTING = 'Y'
  AND ccso.ACADEMIC_YEAR = 2022
  AND sd.DEPARTMENT_CODE <> '7'
GROUP BY sd.DEPARTMENT_NAME
ORDER BY reason_for_inclusion, department_name