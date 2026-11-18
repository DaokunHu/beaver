WITH ProvostDepartments AS (
    SELECT
        t1.HR_DEPARTMENT_CODE,
        t1.HR_DEPARTMENT_NAME,
        t1.ORG_HIER_SCHOOL_AREA_NAME,
        RANK() OVER (PARTITION BY t1.ORG_HIER_SCHOOL_AREA_NAME ORDER BY t1.HR_DEPARTMENT_CODE) AS dept_rank_in_school_area,
        t1.DLC_KEY
    FROM MASTER_DEPT_HIERARCHY t0
    INNER JOIN HR_ORG_UNIT t1 ON t0.DLC_KEY = t1.DLC_KEY
    WHERE t0.MASTER_DEPT_HIER_LEVEL_2_NAME = 'Provost Area'
),
TopProvostDepartment AS (
    SELECT
        pd.HR_DEPARTMENT_CODE,
        pd.HR_DEPARTMENT_NAME,
        pd.ORG_HIER_SCHOOL_AREA_NAME,
        pd.dept_rank_in_school_area,
        COUNT(su.SPACE_UNIT_KEY) AS space_unit_count,
        SUM(su.SPACE_UNIT_KEY) AS space_unit_key_sum
    FROM ProvostDepartments pd
    JOIN SPACE_UNIT su ON pd.DLC_KEY = su.DLC_KEY
    WHERE su.SPACE_UNIT_KEY > 100000
    GROUP BY pd.HR_DEPARTMENT_CODE, pd.HR_DEPARTMENT_NAME, pd.ORG_HIER_SCHOOL_AREA_NAME, pd.dept_rank_in_school_area
    ORDER BY space_unit_count DESC
    LIMIT 10
),
SpaceUnitRows AS (
    SELECT
        t0.SPACE_UNIT_CODE,
        t1.ORGANIZATION_NAME,
        t2.HR_DEPARTMENT_NAME,
        SUM(t0.SPACE_UNIT_KEY) OVER (PARTITION BY t0.WAREHOUSE_LOAD_DATE ORDER BY t0.SPACE_UNIT_KEY) AS space_unit_key_sum_within_load_date
    FROM SPACE_UNIT t0
    JOIN FCLT_ORGANIZATION t1 ON t0.DLC_KEY = t1.DLC_KEY
    JOIN HR_ORG_UNIT t2 ON t1.DLC_KEY = t2.DLC_KEY
    WHERE t0.SPACE_UNIT_KEY > 100000
)
SELECT
    HR_DEPARTMENT_CODE,
    HR_DEPARTMENT_NAME,
    ORG_HIER_SCHOOL_AREA_NAME,
    dept_rank_in_school_area,
    space_unit_count,
    space_unit_key_sum,
    NULL AS SPACE_UNIT_CODE,
    NULL AS ORGANIZATION_NAME,
    NULL AS space_unit_hr_department_name,
    NULL AS space_unit_key_sum_within_load_date,
    'TopProvostDepartment' AS Source
FROM TopProvostDepartment
UNION ALL
SELECT
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    SPACE_UNIT_CODE,
    ORGANIZATION_NAME,
    HR_DEPARTMENT_NAME,
    space_unit_key_sum_within_load_date,
    'SpaceUnit' AS Source
FROM SpaceUnitRows