WITH lib_stats AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           EXP(AVG(LN(lso.NUM_ENROLLED_STUDENTS))) AS geometric_mean_enrollment,
           COUNT(DISTINCT lso.OFFER_DEPT_CODE) AS num_departments
    FROM ACADEMIC_TERMS_ALL ata
    JOIN LIBRARY_SUBJECT_OFFERED lso
      ON ata.TERM_CODE = lso.TERM_CODE
    WHERE lso.NUM_ENROLLED_STUDENTS > 0
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
),
term_stats AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           MAX(tsc.term_subject_count) - MIN(tsc.term_subject_count) AS subject_count_range,
           VARIANCE(tsc.term_subject_count) AS subject_count_variance,
           STDDEV(tsc.term_subject_count) AS subject_count_stddev
    FROM ACADEMIC_TERMS_ALL ata
    JOIN ACADEMIC_TERMS at
      ON ata.TERM_CODE = at.TERM_CODE
    JOIN (
        SELECT tso.TERM_CODE, COUNT(*) AS term_subject_count
        FROM TIP_SUBJECT_OFFERED tso
        GROUP BY tso.TERM_CODE
        HAVING COUNT(*) > 0
    ) tsc
      ON at.TERM_CODE = tsc.TERM_CODE
    GROUP BY ata.ACADEMIC_YEAR, ata.ACADEMIC_YEAR_DESC
)
SELECT ls.ACADEMIC_YEAR,
       ls.ACADEMIC_YEAR_DESC,
       ls.geometric_mean_enrollment,
       ls.num_departments,
       ts.subject_count_range,
       ts.subject_count_variance,
       ts.subject_count_stddev,
       CASE
           WHEN ts.subject_count_stddev > avg_stats.avg_stddev * 1.2 THEN 'HIGH_VARIABILITY'
           WHEN ts.subject_count_stddev < avg_stats.avg_stddev * 0.8 THEN 'LOW_VARIABILITY'
           ELSE 'AVERAGE'
       END AS variability_category
FROM lib_stats ls
JOIN term_stats ts
  ON ls.ACADEMIC_YEAR = ts.ACADEMIC_YEAR
 AND ls.ACADEMIC_YEAR_DESC = ts.ACADEMIC_YEAR_DESC
CROSS JOIN (
    SELECT AVG(subject_count_stddev) AS avg_stddev
    FROM term_stats
) avg_stats
ORDER BY ls.geometric_mean_enrollment DESC;