WITH su_rooms AS (
    SELECT su.SPACE_UNIT AS space_unit_name,
           COUNT(*) AS room_count,
           SUM(CASE WHEN z.ACCESS_LEVEL >= 1 THEN 1 ELSE 0 END) AS al_room_count
    FROM SPACE_UNIT su
    JOIN ZPM_ROOMS_LOAD z ON su.SPACE_UNIT_CODE = z.SPACE_UNIT_CODE
    GROUP BY su.SPACE_UNIT
)
SELECT space_unit_name, room_count
FROM su_rooms
WHERE al_room_count > (SELECT AVG(al_room_count) FROM su_rooms)
ORDER BY space_unit_name