SELECT sos.OFFER_DEPT_NAME AS department_name,
       COUNT(DISTINCT sos.SUBJECT_ID) AS num_unique_subjects,
       SUM(sos.NUM_ENROLLED_STUDENTS) AS total_enrolled_students
FROM SUBJECT_OFFERED_SUMMARY sos
WHERE sos.OFFER_DEPT_NAME = 'Harvard Cross-Enrollment Prog'
  AND sos.OFFER_DEPT_NAME <> 'Chemistry'
  AND sos.TERM_CODE IN (SELECT tso.TERM_CODE FROM TIP_SUBJECT_OFFERED tso)
GROUP BY sos.OFFER_DEPT_NAME
ORDER BY num_unique_subjects DESC
LIMIT 10