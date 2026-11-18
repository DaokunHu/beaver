WITH Students AS (
    SELECT
        msd.FULL_NAME,
        msd.EMAIL_ADDRESS,
        sd.DEPARTMENT_FULL_NAME,
        msd.DEPARTMENT,
        LENGTH(msd.FULL_NAME) - AVG(LENGTH(msd.FULL_NAME)) OVER () AS name_length_difference
    FROM MIT_STUDENT_DIRECTORY msd
    JOIN SIS_DEPARTMENT sd
        ON msd.DEPARTMENT = sd.DEPARTMENT_CODE
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND msd.STUDENT_YEAR = 'G'
),
SchoolStats AS (
    SELECT
        lso.OFFER_DEPT_CODE,
        lso.OFFER_SCHOOL_NAME,
        MIN(lso.NUM_ENROLLED_STUDENTS) AS min_enrolled_students,
        SUM(sos.TOTAL_UNITS) AS total_units
    FROM LIBRARY_SUBJECT_OFFERED lso
    JOIN LIBRARY_RESERVE_MATRL_DETAIL lrmd
        ON lso.SUBJECT_ID = lrmd.SUBJECT_ID
    JOIN SUBJECT_OFFERED_SUMMARY sos
        ON lso.SUBJECT_ID = sos.SUBJECT_ID
    WHERE lrmd.LIBRARY_MATERIAL_STATUS_KEY = 'Y'
    GROUP BY lso.OFFER_DEPT_CODE, lso.OFFER_SCHOOL_NAME
)
SELECT
    s.FULL_NAME,
    s.EMAIL_ADDRESS,
    s.DEPARTMENT_FULL_NAME,
    s.name_length_difference,
    ss.OFFER_SCHOOL_NAME,
    ss.min_enrolled_students,
    ss.total_units
FROM Students s
JOIN SchoolStats ss
    ON s.DEPARTMENT = ss.OFFER_DEPT_CODE
ORDER BY s.FULL_NAME, ss.OFFER_SCHOOL_NAME;