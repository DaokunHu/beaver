WITH room_stats AS (
    SELECT o.HR_DEPARTMENT_NAME AS department_name,
           AVG(r.AREA) AS avg_area,
           MAX(r.AREA) - MIN(r.AREA) AS area_range,
           VARIANCE(r.AREA) AS area_variance
    FROM FCLT_ORG_DLC_KEY d
    JOIN FCLT_ORGANIZATION o ON d.FCLT_ORGANIZATION_KEY = o.FCLT_ORGANIZATION_KEY
    JOIN FCLT_ROOMS r ON o.FCLT_ORGANIZATION_KEY = r.FCLT_ORGANIZATION_KEY
    WHERE r.AREA > 40
    GROUP BY o.HR_DEPARTMENT_NAME
),
unit_stats AS (
    SELECT c.DEPARTMENT_NAME AS department_name,
           AVG(c.TOTAL_UNITS) AS avg_total_units,
           MAX(c.TOTAL_UNITS) - MIN(c.TOTAL_UNITS) AS total_units_range,
           VARIANCE(c.TOTAL_UNITS) AS total_units_variance
    FROM COURSE_CATALOG_SUBJECT_OFFERED c
    JOIN ACADEMIC_TERMS t ON c.TERM_CODE = t.TERM_CODE
    WHERE t.IS_REGULAR_TERM = 'Y'
    GROUP BY c.DEPARTMENT_NAME
)
SELECT rs.department_name,
       rs.avg_area,
       rs.area_range,
       rs.area_variance,
       us.avg_total_units,
       us.total_units_range,
       us.total_units_variance
FROM room_stats rs
JOIN unit_stats us ON rs.department_name = us.department_name
ORDER BY rs.area_range DESC;