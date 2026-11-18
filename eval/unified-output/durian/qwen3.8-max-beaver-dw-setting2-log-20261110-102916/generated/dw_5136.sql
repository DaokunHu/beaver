WITH dept_org_stats AS (
  SELECT m.MASTER_DEPT_HIER_LEVEL_2_NAME,
         f.ORGANIZATION_NAME,
         COUNT(f.FCLT_ORGANIZATION_KEY) AS organization_count,
         MIN(f.ORGANIZATION_NUMBER) AS min_organization_number
  FROM MASTER_DEPT_HIERARCHY m
  JOIN FCLT_ORGANIZATION f ON m.DLC_KEY = f.DLC_KEY
  WHERE f.ASSIGNABLE = 1
  GROUP BY m.MASTER_DEPT_HIER_LEVEL_2_NAME, f.ORGANIZATION_NAME
),
org_geom_supervisees AS (
  SELECT f.ORGANIZATION_NAME,
         EXP(AVG(LN(s.NUM_OF_SUPERVISEES))) AS geometric_mean_supervisees
  FROM FCLT_ORGANIZATION f
  JOIN SPACE_UNIT su ON f.DLC_KEY = su.DLC_KEY
  JOIN SPACE_SUPERVISOR_USAGE s ON su.DLC_KEY = s.DEPT_NAMES
  WHERE s.NUM_OF_SUPERVISEES > 0
  GROUP BY f.ORGANIZATION_NAME
),
org_research_volume AS (
  SELECT f.ORGANIZATION_NAME,
         SUM(s.RESEARCH_VOLUME) AS total_research_volume
  FROM FCLT_ORGANIZATION f
  JOIN SPACE_UNIT su ON f.DLC_KEY = su.DLC_KEY
  JOIN SPACE_SUPERVISOR_USAGE s ON su.DLC_KEY = s.DEPT_NAMES
  GROUP BY f.ORGANIZATION_NAME
)
SELECT d.MASTER_DEPT_HIER_LEVEL_2_NAME,
       d.ORGANIZATION_NAME,
       d.organization_count,
       d.min_organization_number,
       g.geometric_mean_supervisees,
       r.total_research_volume
FROM dept_org_stats d
LEFT JOIN org_geom_supervisees g ON d.ORGANIZATION_NAME = g.ORGANIZATION_NAME
LEFT JOIN org_research_volume r ON d.ORGANIZATION_NAME = r.ORGANIZATION_NAME
ORDER BY d.organization_count DESC, g.geometric_mean_supervisees DESC, r.total_research_volume DESC