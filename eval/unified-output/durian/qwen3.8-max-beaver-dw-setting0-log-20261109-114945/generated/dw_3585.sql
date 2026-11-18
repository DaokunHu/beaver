WITH room_stats AS (
    SELECT r.DEPT_CODE,
           AVG(r.AREA) AS avg_area,
           MAX(r.AREA) - MIN(r.AREA) AS area_range,
           VARIANCE(r.AREA) AS area_variance
    FROM FCLT_ROOMS r
    WHERE r.AREA > 40
    GROUP BY r.DEPT_CODE
),
unit_stats AS (
    SELECT c.DEPARTMENT_CODE,
           AVG(c.TOTAL_UNITS) AS avg_total_units,
           MAX(c.TOTAL_UNITS) - MIN(c.TOTAL_UNITS) AS total_units_range,
           VARIANCE(c.TOTAL_UNITS) AS total_units_variance
    FROM COURSE_CATALOG_SUBJECT_OFFERED c
    JOIN ACADEMIC_TERMS t ON c.TERM_CODE = t.TERM_CODE
    WHERE t.IS_REGULAR_TERM = 'Y'
    GROUP BY c.DEPARTMENT_CODE
)
SELECT d.DEPARTMENT_NAME,
       rs.avg_area,
       rs.area_range,
       rs.area_variance,
       us.avg_total_units,
       us.total_units_range,
       us.total_units_variance
FROM SIS_DEPARTMENT d
JOIN room_stats rs ON d.DEPARTMENT_CODE = rs.DEPT_CODE
JOIN unit_stats us ON d.DEPARTMENT_CODE = us.DEPARTMENT_CODE