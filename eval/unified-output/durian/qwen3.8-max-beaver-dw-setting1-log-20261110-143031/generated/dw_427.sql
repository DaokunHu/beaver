WITH dept_avg AS (
    SELECT so.OFFER_DEPT_NAME,
           AVG(sos.TOTAL_UNITS) AS avg_total_units
    FROM SUBJECT_OFFERED so
    JOIN SUBJECT_OFFERED_SUMMARY sos
        ON so.SUBJECT_ID_SORT = sos.SUBJECT_ID_SORT
    WHERE so.TERM_CODE LIKE '2012%'
      AND so.OFFER_DEPT_NAME = 'Harvard Cross-Enrollment Prog'
      AND sos.CLUSTER_TYPE_DESC = 'SWE: School-Wide Electives'
    GROUP BY so.OFFER_DEPT_NAME
),
overall AS (
    SELECT AVG(avg_total_units) AS overall_avg
    FROM dept_avg
)
SELECT d.OFFER_DEPT_NAME,
       d.avg_total_units,
       CASE
           WHEN d.avg_total_units >= o.overall_avg * 1.1 THEN 'ABOVE_AVERAGE'
           WHEN d.avg_total_units <= o.overall_avg * 0.9 THEN 'BELOW_AVERAGE'
           ELSE 'AVERAGE'
       END AS classification
FROM dept_avg d
CROSS JOIN overall o