WITH dept_filter AS (
    SELECT DEPARTMENT_CODE
    FROM COURSE_CATALOG_SUBJECT_OFFERED
    WHERE TERM_CODE = '2022FA'
    GROUP BY DEPARTMENT_CODE
    HAVING COUNT(*) > 10
),
enroll_stats AS (
    SELECT t.OFFER_DEPT_CODE,
           STDDEV(t.NUM_ENROLLED_STUDENTS) AS enrolled_students_stddev
    FROM TIP_SUBJECT_OFFERED t
    JOIN SIS_DEPARTMENT d ON t.OFFER_DEPT_CODE = d.DEPARTMENT_CODE
    WHERE d.DEPARTMENT_NAME = 'Physics' AND d.DEPARTMENT_CODE = '8'
    GROUP BY t.OFFER_DEPT_CODE
),
room_stats AS (
    SELECT c.DEPARTMENT_CODE,
           AVG(r.AREA) AS avg_room_area,
           VARIANCE(r.AREA) AS room_area_variance,
           STDDEV(r.AREA) AS room_area_stddev
    FROM COURSE_CATALOG_SUBJECT_OFFERED c
    JOIN FCLT_ROOMS r ON c.MEET_PLACE = r.FCLT_ROOM_KEY
    WHERE r.AREA > 100
    GROUP BY c.DEPARTMENT_CODE
)
SELECT d.DEPARTMENT_NAME,
       e.enrolled_students_stddev,
       rs.avg_room_area,
       rs.room_area_variance,
       rs.room_area_stddev
FROM SIS_DEPARTMENT d
JOIN dept_filter f ON d.DEPARTMENT_CODE = f.DEPARTMENT_CODE
JOIN enroll_stats e ON d.DEPARTMENT_CODE = e.OFFER_DEPT_CODE
JOIN room_stats rs ON d.DEPARTMENT_CODE = rs.DEPARTMENT_CODE
WHERE d.DEPARTMENT_NAME = 'Physics' AND d.DEPARTMENT_CODE = '8'