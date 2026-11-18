SELECT
    t1.SPACE_UNIT AS department_name,
    AVG(t0.NUM_OF_SUPERVISEES) AS avg_num_of_supervisees,
    MAX(t0.NUM_OF_SUPERVISEES) - MIN(t0.NUM_OF_SUPERVISEES) AS range_num_of_supervisees,
    VARIANCE(t0.NUM_OF_SUPERVISEES) AS variance_num_of_supervisees,
    SUM(t0.SQFT) AS total_sqft,
    SUM(t0.RESEARCH_VOLUME) AS total_research_volume
FROM SPACE_SUPERVISOR_USAGE t0
JOIN SPACE_UNIT t1 ON t0.DEPT_NAMES = t1.DLC_KEY
GROUP BY t1.SPACE_UNIT