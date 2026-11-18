SELECT so.OFFER_DEPT_NAME,
       COUNT(DISTINCT so.SUBJECT_KEY) AS num_subjects_offered,
       SUM(so.NUM_ENROLLED_STUDENTS) AS total_enrolled_students
FROM SUBJECT_OFFERED so
JOIN TIP_SUBJECT_OFFERED tip ON so.TERM_CODE = tip.TERM_CODE
WHERE so.OFFER_DEPT_NAME = 'Harvard Cross-Enrollment Prog'
  AND so.OFFER_DEPT_NAME <> 'Chemistry'
GROUP BY so.OFFER_DEPT_NAME
ORDER BY num_subjects_offered DESC
LIMIT 10