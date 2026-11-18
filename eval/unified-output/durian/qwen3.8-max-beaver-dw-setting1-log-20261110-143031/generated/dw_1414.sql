SELECT
    DEPARTMENT_NAME,
    total_clearing_cost_collector,
    SCHOOL_NAME
FROM (
    SELECT
        d.DEPARTMENT_NAME,
        SUM(a.CLEARING_COST_COLLECTOR) AS total_clearing_cost_collector,
        d.SCHOOL_NAME,
        AVG(SUM(a.CLEARING_COST_COLLECTOR)) OVER () AS avg_clearing_cost_collector
    FROM SIS_DEPARTMENT d
    JOIN SIS_ADMIN_DEPARTMENT a
        ON a.SIS_ADMIN_DEPARTMENT_CODE = d.DEPARTMENT_CODE
    WHERE d.IS_DEGREE_GRANTING = 'Y'
      AND d.DEPT_BUDGET_CODE > 100000
      AND d.DEPARTMENT_NAME != 'Mathematics'
      AND d.DEPARTMENT_CODE != '8'
    GROUP BY d.DEPARTMENT_NAME, d.SCHOOL_NAME
) t
WHERE total_clearing_cost_collector > avg_clearing_cost_collector
ORDER BY DEPARTMENT_NAME, total_clearing_cost_collector DESC