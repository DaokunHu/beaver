WITH dept_totals AS (
  SELECT d.DEPARTMENT_NAME,
         SUM(a.CLEARING_COST_COLLECTOR) AS total_clearing_cost_collector,
         d.SCHOOL_NAME
  FROM SIS_DEPARTMENT d
  JOIN SIS_ADMIN_DEPARTMENT a
    ON a.SIS_ADMIN_DEPARTMENT_CODE = d.DEPARTMENT_CODE
  WHERE d.IS_DEGREE_GRANTING = 'Y'
    AND d.DEPT_BUDGET_CODE > 100000
    AND d.DEPARTMENT_NAME NOT IN ('Mathematics', 'Physics')
  GROUP BY d.DEPARTMENT_NAME, d.SCHOOL_NAME
)
SELECT t.DEPARTMENT_NAME,
       t.total_clearing_cost_collector,
       t.SCHOOL_NAME
FROM dept_totals t
CROSS JOIN (
  SELECT AVG(total_clearing_cost_collector) AS avg_ccc
  FROM dept_totals
) x
WHERE t.total_clearing_cost_collector > x.avg_ccc
ORDER BY t.DEPARTMENT_NAME, t.total_clearing_cost_collector DESC