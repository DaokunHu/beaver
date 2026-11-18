WITH DeptUnits AS (
  SELECT t1.DLC_KEY,
         COUNT(*) AS space_unit_count
  FROM SPACE_UNIT t0
  JOIN FCLT_ORGANIZATION t1 ON t0.DLC_KEY = t1.DLC_KEY
  JOIN HR_ORG_UNIT t2 ON t1.DLC_KEY = t2.DLC_KEY
  WHERE t0.SPACE_UNIT_KEY > 100000
  GROUP BY t1.DLC_KEY
),
ProvostDepartments AS (
  SELECT t1.HR_DEPARTMENT_CODE,
         t1.HR_DEPARTMENT_NAME,
         t1.ORG_HIER_SCHOOL_AREA_NAME,
         RANK() OVER (PARTITION BY t1.ORG_HIER_SCHOOL_AREA_NAME ORDER BY t1.HR_DEPARTMENT_CODE) AS dept_rank,
         t1.DLC_KEY
  FROM MASTER_DEPT_HIERARCHY t0
  INNER JOIN HR_ORG_UNIT t1 ON t0.DLC_KEY = t1.DLC_KEY
  WHERE t0.MASTER_DEPT_HIER_LEVEL_2_NAME = 'Provost Area'
),
TopProvostDepartment AS (
  SELECT pd.HR_DEPARTMENT_CODE,
         pd.HR_DEPARTMENT_NAME,
         pd.ORG_HIER_SCHOOL_AREA_NAME,
         pd.dept_rank,
         du.space_unit_count,
         SUM(t0.SPACE_UNIT_KEY) AS sum_space_unit_keys
  FROM ProvostDepartments pd
  JOIN DeptUnits du ON pd.DLC_KEY = du.DLC_KEY
  JOIN SPACE_UNIT t0 ON t0.DLC_KEY = pd.DLC_KEY AND t0.SPACE_UNIT_KEY > 100000
  GROUP BY pd.HR_DEPARTMENT_CODE, pd.HR_DEPARTMENT_NAME, pd.ORG_HIER_SCHOOL_AREA_NAME, pd.dept_rank, du.space_unit_count
  ORDER BY du.space_unit_count DESC
  LIMIT 10
),
SpaceUnitRows AS (
  SELECT t0.SPACE_UNIT_CODE,
         t1.ORGANIZATION_NAME,
         t2.HR_DEPARTMENT_NAME,
         SUM(t0.SPACE_UNIT_KEY) OVER (PARTITION BY t0.WAREHOUSE_LOAD_DATE ORDER BY t0.SPACE_UNIT_KEY) AS sum_keys_within_load_date
  FROM SPACE_UNIT t0
  JOIN FCLT_ORGANIZATION t1 ON t0.DLC_KEY = t1.DLC_KEY
  JOIN HR_ORG_UNIT t2 ON t1.DLC_KEY = t2.DLC_KEY
  WHERE t0.SPACE_UNIT_KEY > 100000
),
Combined AS (
  SELECT HR_DEPARTMENT_CODE,
         HR_DEPARTMENT_NAME,
         ORG_HIER_SCHOOL_AREA_NAME,
         dept_rank,
         space_unit_count,
         sum_space_unit_keys,
         NULL AS SPACE_UNIT_CODE,
         NULL AS ORGANIZATION_NAME,
         NULL AS space_hr_department_name,
         NULL AS sum_keys_within_load_date,
         'TopProvostDepartment' AS Source
  FROM TopProvostDepartment
  UNION ALL
  SELECT NULL AS HR_DEPARTMENT_CODE,
         NULL AS HR_DEPARTMENT_NAME,
         NULL AS ORG_HIER_SCHOOL_AREA_NAME,
         NULL AS dept_rank,
         NULL AS space_unit_count,
         NULL AS sum_space_unit_keys,
         SPACE_UNIT_CODE,
         ORGANIZATION_NAME,
         HR_DEPARTMENT_NAME AS space_hr_department_name,
         sum_keys_within_load_date,
         'SpaceUnit' AS Source
  FROM SpaceUnitRows
)
SELECT HR_DEPARTMENT_CODE,
       HR_DEPARTMENT_NAME,
       ORG_HIER_SCHOOL_AREA_NAME,
       dept_rank,
       space_unit_count,
       sum_space_unit_keys,
       SPACE_UNIT_CODE,
       ORGANIZATION_NAME,
       space_hr_department_name,
       sum_keys_within_load_date,
       Source
FROM Combined
ORDER BY Source, HR_DEPARTMENT_CODE, SPACE_UNIT_CODE