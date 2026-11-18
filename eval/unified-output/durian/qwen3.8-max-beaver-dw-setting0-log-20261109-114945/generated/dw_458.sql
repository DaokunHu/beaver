WITH building_cv AS (
    SELECT b.FCLT_BUILDING_KEY,
           b.BUILDING_NAME_LONG,
           STDDEV(r.AREA) / AVG(r.AREA) AS cv_room_area
    FROM FCLT_BUILDING b
    JOIN FCLT_ROOMS r ON b.FCLT_BUILDING_KEY = r.FCLT_BUILDING_KEY
    WHERE b.BUILDING_TYPE = 'ACADEMIC'
      AND b.BUILDING_NAME <> 'ASHDOWN HOUSE'
    GROUP BY b.FCLT_BUILDING_KEY, b.BUILDING_NAME_LONG
),
avg_cv AS (
    SELECT AVG(cv_room_area) AS avg_cv FROM building_cv
)
SELECT bc.cv_room_area,
       bc.BUILDING_NAME_LONG,
       a.POSTAL_CODE
FROM building_cv bc
JOIN FCLT_BUILDING_ADDRESS a ON bc.FCLT_BUILDING_KEY = a.FCLT_BUILDING_KEY
CROSS JOIN avg_cv ac
WHERE bc.cv_room_area > ac.avg_cv