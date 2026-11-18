WITH lib_stats AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           EXP(AVG(LN(lso.NUM_ENROLLED_STUDENTS))) AS geometric_mean_enrolled_students,
           COUNT(DISTINCT lso.OFFER_DEPT_CODE) AS num_distinct_departments
    FROM LIBRARY_SUBJECT_OFFERED lso
    JOIN ACADEMIC_TERMS_ALL ata ON lso.TERM_CODE = ata.TERM_CODE
    WHERE lso.NUM_ENROLLED_STUDENTS > 0
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
),
term_subject_counts AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           tso.TERM_CODE,
           COUNT(*) AS num_subjects_offered
    FROM TIP_SUBJECT_OFFERED tso
    JOIN ACADEMIC_TERMS at2 ON tso.TERM_CODE = at2.TERM_CODE
    JOIN ACADEMIC_TERMS_ALL ata ON at2.TERM_CODE = ata.TERM_CODE
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC, tso.TERM_CODE
    HAVING COUNT(*) >= 1
),
tip_stats AS (
    SELECT ACADEMIC_YEAR,
           ACADEMIC_YEAR_DESC,
           MAX(num_subjects_offered) - MIN(num_subjects_offered) AS subjects_offered_range,
           VARIANCE(num_subjects_offered) AS subjects_offered_variance,
           STDDEV(num_subjects_offered) AS subjects_offered_stddev
    FROM term_subject_counts
    GROUP BY ACADEMIC_YEAR, ACADEMIC_YEAR_DESC
),
combined AS (
    SELECT l.ACADEMIC_YEAR,
           l.ACADEMIC_YEAR_DESC,
           l.geometric_mean_enrolled_students,
           l.num_distinct_departments,
           t.subjects_offered_range,
           t.subjects_offered_variance,
           t.subjects_offered_stddev
    FROM lib_stats l
    JOIN tip_stats t
      ON l.ACADEMIC_YEAR = t.ACADEMIC_YEAR
     AND l.ACADEMIC_YEAR_DESC = t.ACADEMIC_YEAR_DESC
)
SELECT c.ACADEMIC_YEAR,
       c.ACADEMIC_YEAR_DESC,
       c.geometric_mean_enrolled_students,
       c.num_distinct_departments,
       c.subjects_offered_range,
       c.subjects_offered_variance,
       c.subjects_offered_stddev,
       CASE WHEN c.subjects_offered_stddev > avg_s.avg_stddev * 1.2 THEN 'HIGH_VARIABILITY'
            WHEN c.subjects_offered_stddev < avg_s.avg_stddev * 0.8 THEN 'LOW_VARIABILITY'
            ELSE 'AVERAGE' END AS variability_category
FROM combined c
CROSS JOIN (SELECT AVG(subjects_offered_stddev) AS avg_stddev FROM combined) avg_s
ORDER BY c.geometric_mean_enrolled_students DESC;