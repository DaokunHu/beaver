WITH lib AS (
    SELECT ata.ACADEMIC_YEAR,
           ata.ACADEMIC_YEAR_DESC,
           lso.TERM_CODE,
           lso.SUBJECT_ID,
           lso.OFFER_DEPT_NAME,
           lso.NUM_ENROLLED_STUDENTS
    FROM LIBRARY_SUBJECT_OFFERED lso
    JOIN ACADEMIC_TERMS_ALL ata ON lso.TERM_CODE = ata.TERM_CODE
),
enroll_stats AS (
    SELECT ACADEMIC_YEAR,
           ACADEMIC_YEAR_DESC,
           EXP(AVG(LN(NUM_ENROLLED_STUDENTS))) AS geometric_mean_enrollment,
           COUNT(DISTINCT OFFER_DEPT_NAME) AS num_distinct_departments
    FROM lib
    WHERE NUM_ENROLLED_STUDENTS > 0
    GROUP BY ACADEMIC_YEAR, ACADEMIC_YEAR_DESC
),
term_subject_counts AS (
    SELECT ACADEMIC_YEAR,
           TERM_CODE,
           COUNT(*) AS subjects_per_term
    FROM lib
    GROUP BY ACADEMIC_YEAR, TERM_CODE
    HAVING COUNT(*) >= 1
),
term_dispersion AS (
    SELECT ACADEMIC_YEAR,
           MAX(subjects_per_term) - MIN(subjects_per_term) AS range_subjects_per_term,
           VARIANCE(subjects_per_term) AS variance_subjects_per_term,
           STDDEV(subjects_per_term) AS stddev_subjects_per_term
    FROM term_subject_counts
    GROUP BY ACADEMIC_YEAR
),
overall AS (
    SELECT AVG(stddev_subjects_per_term) AS avg_stddev
    FROM term_dispersion
)
SELECT e.ACADEMIC_YEAR,
       e.ACADEMIC_YEAR_DESC,
       e.geometric_mean_enrollment,
       e.num_distinct_departments,
       t.range_subjects_per_term,
       t.variance_subjects_per_term,
       t.stddev_subjects_per_term,
       CASE
           WHEN t.stddev_subjects_per_term >= o.avg_stddev * 1.2 THEN 'HIGH_VARIABILITY'
           WHEN t.stddev_subjects_per_term <= o.avg_stddev * 0.8 THEN 'LOW_VARIABILITY'
           ELSE 'AVERAGE'
       END AS variability_category
FROM enroll_stats e
JOIN term_dispersion t ON e.ACADEMIC_YEAR = t.ACADEMIC_YEAR
CROSS JOIN overall o
ORDER BY e.geometric_mean_enrollment DESC