SELECT t.department, MAX(t.avg_enrollment) AS max_avg_enrollment
FROM (
    SELECT lso.OFFER_DEPT_NAME AS department,
           sos.TERM_CODE,
           AVG(sos.NUM_ENROLLED_STUDENTS) AS avg_enrollment
    FROM LIBRARY_SUBJECT_OFFERED lso
    JOIN TIP_DETAIL td ON lso.SUBJECT_ID = td.SUBJECT_ID
    JOIN SUBJECT_OFFERED_SUMMARY sos ON td.SUBJECT_ID = sos.SUBJECT_ID
    WHERE td.RECORD_COUNT >= 1
      AND sos.TOTAL_UNITS > 0
    GROUP BY lso.OFFER_DEPT_NAME, sos.TERM_CODE
) t
GROUP BY t.department