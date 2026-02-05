-- Intermediate reporting queries
-- Engine: PostgreSQL 16
-- DB: npe_claims_demo
-- File: sql/04_queries_intermediate.sql

\echo '--- I0. Sanity header (counts + distincts) ---'
SELECT 'claims' AS table_name, COUNT(*) AS row_count FROM claims
UNION ALL SELECT 'providers', COUNT(*) FROM providers
UNION ALL SELECT 'medical_codes', COUNT(*) FROM medical_codes
UNION ALL SELECT 'injury_types', COUNT(*) FROM injury_types
UNION ALL SELECT 'claim_medical_codes', COUNT(*) FROM claim_medical_codes
UNION ALL SELECT 'claim_injuries', COUNT(*) FROM claim_injuries
ORDER BY table_name;

SELECT
  (SELECT COUNT(DISTINCT provider_id) FROM claims) AS distinct_providers,
  (SELECT COUNT(DISTINCT medical_code_id) FROM claim_medical_codes) AS distinct_codes,
  (SELECT COUNT(DISTINCT injury_type_id) FROM claim_injuries) AS distinct_injuries;

\echo '--- I1. Monthly KPI table: received, closed, approval_rate, payout ---'
WITH m AS (
  SELECT
    date_trunc('month', received_date)::date AS month,
    COUNT(*) AS claims_received,
    SUM(CASE WHEN status = 'Closed' THEN 1 ELSE 0 END) AS closed_count,
    SUM(CASE WHEN status = 'Closed' AND decision = 'Approved' THEN 1 ELSE 0 END) AS approved_closed,
    SUM(CASE WHEN status = 'Closed' THEN claim_amount_nok ELSE 0 END) AS total_payout_nok
  FROM claims
  GROUP BY 1
)
SELECT
  month,
  claims_received,
  closed_count,
  ROUND(100.0 * approved_closed / NULLIF(closed_count, 0), 1) AS approval_rate_closed_pct,
  ROUND(total_payout_nok, 2) AS total_payout_nok
FROM m
ORDER BY month;

\echo '--- I2. Approval rate by region (Closed only) ---'
SELECT
  region,
  COUNT(*) AS closed_count,
  SUM(CASE WHEN decision = 'Approved' THEN 1 ELSE 0 END) AS approved_count,
  ROUND(100.0 * SUM(CASE WHEN decision = 'Approved' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS approval_rate_pct
FROM claims
WHERE status = 'Closed'
GROUP BY region
ORDER BY approval_rate_pct DESC, closed_count DESC;

\echo '--- I3. Processing days by care_level (Closed only): min/avg/max ---'
SELECT
  care_level,
  COUNT(*) AS closed_count,
  MIN((decision_date - received_date)) AS min_days,
  ROUND(AVG((decision_date - received_date))::numeric, 1) AS avg_days,
  MAX((decision_date - received_date)) AS max_days
FROM claims
WHERE status = 'Closed'
  AND decision_date IS NOT NULL
GROUP BY care_level
ORDER BY avg_days DESC;

\echo '--- I4. Backlog snapshot: InReview + Received by region ---'
SELECT
  region,
  SUM(CASE WHEN status = 'InReview' THEN 1 ELSE 0 END) AS inreview_count,
  SUM(CASE WHEN status = 'Received' THEN 1 ELSE 0 END) AS received_count,
  SUM(CASE WHEN status IN ('InReview','Received') THEN 1 ELSE 0 END) AS backlog_total
FROM claims
GROUP BY region
ORDER BY backlog_total DESC;

\echo '--- I5. Top provider per region (Closed claims count) ---'
WITH counts AS (
  SELECT
    c.region,
    p.provider_name,
    c.provider_id,
    COUNT(*) AS closed_claims
  FROM claims c
  JOIN providers p ON p.provider_id = c.provider_id
  WHERE c.status = 'Closed'
  GROUP BY c.region, p.provider_name, c.provider_id
),
ranked AS (
  SELECT
    region,
    provider_name,
    provider_id,
    closed_claims,
    ROW_NUMBER() OVER (PARTITION BY region ORDER BY closed_claims DESC, provider_id) AS rn
  FROM counts
)
SELECT
  region,
  provider_name,
  provider_id,
  closed_claims
FROM ranked
WHERE rn = 1
ORDER BY closed_claims DESC, region;

\echo '--- I6. Most common medical code per region (count) ---'
WITH code_counts AS (
  SELECT
    c.region,
    mc.medical_code_id,
    COUNT(*) AS code_uses
  FROM claims c
  JOIN claim_medical_codes cmc ON cmc.claim_id = c.claim_id
  JOIN medical_codes mc ON mc.medical_code_id = cmc.medical_code_id
  GROUP BY c.region, mc.medical_code_id
),
ranked AS (
  SELECT
    region,
    medical_code_id,
    code_uses,
    DENSE_RANK() OVER (PARTITION BY region ORDER BY code_uses DESC, medical_code_id) AS rnk
  FROM code_counts
)
SELECT
  r.region,
  r.medical_code_id,
  m.code_system,
  m.code,
  m.code_title,
  r.code_uses
FROM ranked r
JOIN medical_codes m ON m.medical_code_id = r.medical_code_id
WHERE r.rnk = 1
ORDER BY r.code_uses DESC, r.region;

\echo '--- I7. Rejection rate by care_level (Closed only): rejected/closed ---'
SELECT
  care_level,
  COUNT(*) AS closed_count,
  SUM(CASE WHEN decision = 'Rejected' THEN 1 ELSE 0 END) AS rejected_count,
  ROUND(100.0 * SUM(CASE WHEN decision = 'Rejected' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS rejection_rate_pct
FROM claims
WHERE status = 'Closed'
GROUP BY care_level
ORDER BY rejection_rate_pct DESC, closed_count DESC;

\echo '--- I8. High payout outliers: top 20 claims by claim_amount_nok ---'
SELECT
  c.claim_id,
  c.claim_reference,
  c.received_date,
  c.status,
  c.decision,
  c.claim_amount_nok,
  c.region,
  p.provider_name
FROM claims c
JOIN providers p ON p.provider_id = c.provider_id
ORDER BY c.claim_amount_nok DESC
LIMIT 20;

\echo '--- I9. Data quality checks (should be 0) ---'
SELECT
  SUM(CASE WHEN status = 'Closed' AND decision IS NULL THEN 1 ELSE 0 END) AS closed_with_decision_null,
  SUM(CASE WHEN decision_date IS NOT NULL AND decision_date < received_date THEN 1 ELSE 0 END) AS decision_before_received,
  SUM(CASE WHEN decision = 'Rejected' AND claim_amount_nok > 0 THEN 1 ELSE 0 END) AS rejected_with_positive_amount
FROM claims;
