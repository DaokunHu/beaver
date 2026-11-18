WITH inner_cte AS (
  SELECT sd.DEPARTMENT_NAME,
         SUM(sad.CLEARING_COST_COLLECTOR) AS total_clearing_cost_collector,
         sd.SCHOOL_NAME
  FROM SIS_DEPARTMENT sd
  JOIN SIS_ADMIN_DEPARTMENT sad
    ON sd.DEPARTMENT_CODE = sad.SIS_ADMIN_DEPARTMENT_CODE
  WHERE sd.IS_DEGREE_GRANTING = 'Y'
    AND sd.DEPT_BUDGET_CODE > 100000
    AND sd.DEPARTMENT_NAME <> 'Mathematics'
    AND sd.DEPARTMENT_CODE <> '8'
  GROUP BY sd.DEPARTMENT_NAME, sd.SCHOOL_NAME
)
SELECT DEPARTMENT_NAME, total_clearing_cost_collector, SCHOOL_NAME
FROM inner_cte
WHERE total_clearing_cost_collector > (SELECT AVG(total_clearing_cost_collector) FROM inner_cte)
ORDER BY DEPARTMENT_NAME ASC, total_clearing_cost_collector DESC