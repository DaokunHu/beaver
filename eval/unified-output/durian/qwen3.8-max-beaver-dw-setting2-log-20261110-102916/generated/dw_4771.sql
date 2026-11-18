WITH DeptEnrolledStats AS (
    SELECT sd.DEPARTMENT_NAME,
           MAX(tso.NUM_ENROLLED_STUDENTS) - MIN(tso.NUM_ENROLLED_STUDENTS) AS enrolled_range,
           VARIANCE(tso.NUM_ENROLLED_STUDENTS) AS enrolled_variance
    FROM TIP_SUBJECT_OFFERED tso
    JOIN SIS_DEPARTMENT sd ON tso.OFFER_DEPT_CODE = sd.DEPARTMENT_CODE
    JOIN SIS_COURSE_DESCRIPTION scd ON sd.DEPARTMENT_CODE = scd.DEPARTMENT
    WHERE sd.IS_DEGREE_GRANTING = 'Y'
      AND scd.COURSE_LEVEL = 'G'
    GROUP BY sd.DEPARTMENT_NAME
),
DeptSubjectMaterialStats AS (
    SELECT tso.OFFER_DEPT_NAME,
           tso.OFFER_SCHOOL_NAME,
           COUNT(DISTINCT tso.SUBJECT_ID) AS subject_count,
           MIN(td.ISBN) AS min_isbn,
           AVG(tso.NUM_ENROLLED_STUDENTS) AS avg_enrolled
    FROM TIP_SUBJECT_OFFERED tso
    JOIN TIP_DETAIL td ON tso.SUBJECT_ID = td.SUBJECT_ID
    WHERE tso.NUM_ENROLLED_STUDENTS > 2
    GROUP BY tso.OFFER_DEPT_NAME, tso.OFFER_SCHOOL_NAME
)
SELECT des.DEPARTMENT_NAME,
       des.enrolled_range,
       des.enrolled_variance,
       dsm.subject_count,
       dsm.min_isbn,
       dsm.avg_enrolled
FROM DeptEnrolledStats des
JOIN DeptSubjectMaterialStats dsm ON des.DEPARTMENT_NAME = dsm.OFFER_DEPT_NAME
ORDER BY des.enrolled_range DESC