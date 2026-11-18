WITH EnrolledStddev AS (
    SELECT d.DEPARTMENT_NAME,
           STDDEV(t.NUM_ENROLLED_STUDENTS) AS enrolled_stddev
    FROM SIS_DEPARTMENT d
    JOIN TIP_SUBJECT_OFFERED t ON d.DEPARTMENT_CODE = t.OFFER_DEPT_CODE
    JOIN COURSE_CATALOG_SUBJECT_OFFERED c ON d.DEPARTMENT_CODE = c.DEPARTMENT_CODE
    WHERE c.TERM_CODE = '2022FA'
      AND d.DEPARTMENT_NAME = 'Physics'
      AND d.DEPARTMENT_CODE = '8'
    GROUP BY d.DEPARTMENT_NAME
    HAVING COUNT(*) > 10
    ORDER BY enrolled_stddev DESC
),
RoomAreaStats AS (
    SELECT c.DEPARTMENT_NAME,
           AVG(f.AREA) AS avg_area,
           VARIANCE(f.AREA) AS area_variance,
           STDDEV(f.AREA) AS area_stddev
    FROM FCLT_ROOMS f
    JOIN COURSE_CATALOG_SUBJECT_OFFERED c ON f.FCLT_ROOM_KEY = c.MEET_PLACE
    WHERE f.AREA > 100
      AND c.DEPARTMENT_NAME = 'Physics'
    GROUP BY c.DEPARTMENT_NAME
    ORDER BY area_variance DESC
)
SELECT e.DEPARTMENT_NAME,
       e.enrolled_stddev,
       r.avg_area,
       r.area_variance,
       r.area_stddev
FROM EnrolledStddev e
JOIN RoomAreaStats r ON e.DEPARTMENT_NAME = r.DEPARTMENT_NAME