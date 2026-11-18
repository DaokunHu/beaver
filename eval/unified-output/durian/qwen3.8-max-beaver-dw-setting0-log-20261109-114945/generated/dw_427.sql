WITH dept_avg AS (
    SELECT OFFER_DEPT_NAME,
           AVG(TOTAL_UNITS) AS avg_total_units
    FROM SUBJECT_OFFERED_SUMMARY
    WHERE TERM_CODE LIKE '2012%'
      AND OFFER_DEPT_NAME = 'Harvard Cross-Enrollment Prog'
      AND CLUSTER_TYPE_DESC = 'SWE: School-Wide Electives'
    GROUP BY OFFER_DEPT_NAME
),
overall AS (
    SELECT AVG(avg_total_units) AS overall_avg_total_units
    FROM dept_avg
)
SELECT d.OFFER_DEPT_NAME,
       d.avg_total_units,
       o.overall_avg_total_units,
       CASE
           WHEN d.avg_total_units >= o.overall_avg_total_units * 1.1 THEN 'ABOVE_AVERAGE'
           WHEN d.avg_total_units <= o.overall_avg_total_units * 0.9 THEN 'BELOW_AVERAGE'
           ELSE 'AVERAGE'
       END AS classification
FROM dept_avg d
CROSS JOIN overall o
ORDER BY d.OFFER_DEPT_NAME