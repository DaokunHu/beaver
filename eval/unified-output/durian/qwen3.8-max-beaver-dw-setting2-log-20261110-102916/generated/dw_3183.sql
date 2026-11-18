SELECT SPACE_UNIT, room_count
FROM (
    SELECT su.SPACE_UNIT,
           COUNT(zr.BUILDING_ROOM) AS room_count,
           AVG(COUNT(zr.BUILDING_ROOM)) OVER () AS avg_room_count
    FROM SPACE_UNIT su
    JOIN ZPM_ROOMS_LOAD zr ON su.SPACE_UNIT_CODE = zr.SPACE_UNIT_CODE
    WHERE zr.ACCESS_LEVEL >= 1
    GROUP BY su.SPACE_UNIT
) t
WHERE room_count > avg_room_count