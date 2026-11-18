WITH ProvostAreaDepts AS (
    SELECT m.DLC_NAME,
           f.FCLT_ORGANIZATION_KEY,
           COUNT(f.FCLT_ORGANIZATION_KEY) AS org_count,
           MIN(m.MASTER_DEPT_HIER_LEVEL_3_CODE) AS min_level3_code
    FROM MASTER_DEPT_HIERARCHY m
    JOIN FCLT_ORG_DLC_KEY f ON m.DLC_KEY = f.DLC_KEY
    WHERE m.MASTER_DEPT_HIER_LEVEL_2_NAME = 'Provost Area'
    GROUP BY m.DLC_NAME, f.FCLT_ORGANIZATION_KEY
),
ProvostAreaDeptsMinMax AS (
    SELECT i.DLC_NAME,
           i.FCLT_ORGANIZATION_KEY,
           i.org_count,
           i.min_level3_code,
           MAX(m.MASTER_DEPT_HIER_LEVEL_3_CODE) AS max_level3_code
    FROM ProvostAreaDepts i
    JOIN MASTER_DEPT_HIERARCHY m ON i.DLC_NAME = m.DLC_NAME
    GROUP BY i.DLC_NAME, i.FCLT_ORGANIZATION_KEY, i.org_count, i.min_level3_code
),
OrgSpaceUnits AS (
    SELECT fo.ORGANIZATION_NAME,
           COUNT(su.SPACE_UNIT_KEY) AS space_unit_count
    FROM FCLT_ORG_DLC_KEY fok
    JOIN FCLT_ORGANIZATION fo ON fok.DLC_KEY = fo.DLC_KEY
    JOIN SPACE_UNIT su ON fo.DLC_KEY = su.DLC_KEY
    GROUP BY fo.ORGANIZATION_NAME
),
AvgStats AS (
    SELECT AVG(space_unit_count) AS avg_space_units FROM OrgSpaceUnits
)
SELECT p.DLC_NAME,
       p.FCLT_ORGANIZATION_KEY,
       p.org_count,
       p.min_level3_code,
       p.max_level3_code,
       os.ORGANIZATION_NAME,
       os.space_unit_count,
       a.avg_space_units,
       CASE WHEN os.space_unit_count > a.avg_space_units * 1.2 THEN 'LARGE_HOLDER'
            WHEN os.space_unit_count < a.avg_space_units * 0.8 THEN 'SMALL_HOLDER'
            ELSE 'AVERAGE_HOLDER' END AS holder_category
FROM ProvostAreaDeptsMinMax p
JOIN FCLT_ORGANIZATION fo ON p.FCLT_ORGANIZATION_KEY = fo.FCLT_ORGANIZATION_KEY
JOIN OrgSpaceUnits os ON fo.ORGANIZATION_NAME = os.ORGANIZATION_NAME
CROSS JOIN AvgStats a
ORDER BY p.DLC_NAME, os.ORGANIZATION_NAME