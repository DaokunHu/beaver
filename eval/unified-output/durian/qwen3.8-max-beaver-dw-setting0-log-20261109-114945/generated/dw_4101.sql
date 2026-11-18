WITH ProvostAreaDepts AS (
  SELECT m.DLC_NAME,
         f.FCLT_ORGANIZATION_KEY,
         COUNT(f.FCLT_ORGANIZATION_KEY) AS org_count,
         MIN(m.MASTER_DEPT_HIER_LEVEL_3_CODE) AS min_level3_code,
         MAX(m.MASTER_DEPT_HIER_LEVEL_3_CODE) AS max_level3_code
  FROM MASTER_DEPT_HIERARCHY m
  JOIN FCLT_ORG_DLC_KEY f ON m.DLC_KEY = f.DLC_KEY
  WHERE m.MASTER_DEPT_HIER_LEVEL_2_NAME = 'Provost Area'
  GROUP BY m.DLC_NAME, f.FCLT_ORGANIZATION_KEY
),
SpaceUnitStats AS (
  SELECT s.FCLT_ORGANIZATION_KEY,
         COUNT(s.SPACE_UNIT_KEY) AS space_unit_count
  FROM SPACE_UNIT s
  GROUP BY s.FCLT_ORGANIZATION_KEY
),
Combined AS (
  SELECT p.DLC_NAME,
         p.FCLT_ORGANIZATION_KEY,
         p.org_count,
         p.min_level3_code,
         p.max_level3_code,
         o.ORGANIZATION_NAME,
         su.space_unit_count
  FROM ProvostAreaDepts p
  JOIN FCLT_ORGANIZATION o ON p.FCLT_ORGANIZATION_KEY = o.FCLT_ORGANIZATION_KEY
  JOIN SpaceUnitStats su ON p.FCLT_ORGANIZATION_KEY = su.FCLT_ORGANIZATION_KEY
)
SELECT c.DLC_NAME,
       c.FCLT_ORGANIZATION_KEY,
       c.org_count,
       c.min_level3_code,
       c.max_level3_code,
       c.ORGANIZATION_NAME,
       c.space_unit_count,
       oa.avg_space_unit_count,
       CASE WHEN c.space_unit_count > oa.avg_space_unit_count THEN 'LARGE_HOLDER'
            WHEN c.space_unit_count < oa.avg_space_unit_count THEN 'SMALL_HOLDER'
            ELSE 'AVERAGE_HOLDER' END AS holder_category
FROM Combined c
CROSS JOIN (SELECT AVG(space_unit_count) AS avg_space_unit_count FROM Combined) oa
ORDER BY c.DLC_NAME, c.ORGANIZATION_NAME