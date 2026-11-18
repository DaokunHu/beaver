WITH dept_totals AS (
    SELECT sd.DEPARTMENT_NAME,
           SUM(sad.CLEARING_COST_COLLECTOR) AS total_clearing_cost_collector
    FROM SIS_DEPARTMENT sd
    JOIN SIS_ADMIN_DEPARTMENT sad
      ON sd.DEPARTMENT_CODE = sad.SIS_ADMIN_DEPARTMENT_CODE
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND sd.DEPT_BUDGET_CODE > 100000
      AND sd.DEPARTMENT_NAME <> 'Mathematics'
      AND sd.DEPARTMENT_CODE <> '8'
    GROUP BY sd.DEPARTMENT_NAME
)
SELECT DEPARTMENT_NAME, total_clearing_cost_collector
FROM dept_totals
WHERE total_clearing_cost_collector > (SELECT AVG(total_clearing_cost_collector) FROM dept_totals)