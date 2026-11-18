WITH inner_cte AS (
    SELECT b.BUILDING_NAME_LONG,
           a.POSTAL_CODE,
           STDDEV(r.AREA) / NULLIF(AVG(r.AREA), 0) AS coefficient_of_variation
    FROM FCLT_ROOMS r
    JOIN FCLT_BUILDING b ON r.FCLT_BUILDING_KEY = b.FCLT_BUILDING_KEY
    JOIN FCLT_BUILDING_ADDRESS a ON b.FCLT_BUILDING_KEY = a.FCLT_BUILDING_KEY
    WHERE b.BUILDING_TYPE = 'ACADEMIC'
      AND b.BUILDING_NAME <> 'ASHDOWN HOUSE'
    GROUP BY b.BUILDING_NAME_LONG, a.POSTAL_CODE
    HAVING AVG(r.AREA) > 0
)
SELECT i.BUILDING_NAME_LONG,
       i.POSTAL_CODE,
       i.coefficient_of_variation
FROM inner_cte i
WHERE i.coefficient_of_variation > (SELECT AVG(c.coefficient_of_variation) FROM inner_cte c)
ORDER BY i.coefficient_of_variation DESC;