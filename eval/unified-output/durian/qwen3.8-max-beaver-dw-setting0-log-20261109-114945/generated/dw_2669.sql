SELECT
    t1.DEPT_NAMES AS department_name,
    AVG(t1.NUM_OF_SUPERVISEES) AS avg_num_of_supervisees,
    MAX(t1.NUM_OF_SUPERVISEES) - MIN(t1.NUM_OF_SUPERVISEES) AS num_of_supervisees_range,
    VARIANCE(t1.NUM_OF_SUPERVISEES) AS num_of_supervisees_variance,
    SUM(t1.SQFT) AS total_sqft,
    SUM(t1.RESEARCH_VOLUME) AS total_research_volume
FROM SPACE_UNIT t0
INNER JOIN SPACE_SUPERVISOR_USAGE t1
    ON t0.DLC_KEY = t1.DEPT_NAMES
GROUP BY t1.DEPT_NAMES