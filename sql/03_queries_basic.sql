-- ============================================================
-- Part 4 — BASIC reporting queries (SQL-first, interview-safe)
-- Project: SQL NPE Claims Analytics (Synthetic)
-- Engine: PostgreSQL 16
-- Run: psql -d npe_claims_demo -f sql/03_queries_basic.sql
-- ============================================================

\pset pager off

-- ------------------------------------------------------------
-- Q0. Dataset sanity (counts + date range)
-- Answers: "Did I load what I think I loaded?"
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM claims)              AS claims_count,
  (SELECT COUNT(*) FROM providers)           AS providers_count,
  (SELECT COUNT(*) FROM medical_codes)       AS medical_codes_count,
  (SELECT COUNT(*) FROM claim_medical_codes) AS claim_medical_codes_count,
  (SELECT COUNT(*) FROM injury_types)        AS injury_types_count,
  (SELECT COUNT(*) FROM claim_injuries)      AS claim_injuries_count,
  (SELECT MIN(received_date) FROM claims)    AS min_received_date,
  (SELECT MAX(received_date) FROM claims)    AS max_received_date,
  (SELECT MIN(decision_date) FROM claims)    AS min_decision_date,
  (SELECT MAX(decision_date) FROM claims)    AS max_decision_date;

-- ------------------------------------------------------------
-- Q1. Claims per month (received_date)
-- Answers: "How many claims arrive each month?"
-- ------------------------------------------------------------
SELECT
  date_trunc('month', received_date)::date AS month,
  COUNT(*) AS claims_count
FROM claims
GROUP BY 1
ORDER BY 1;

-- ------------------------------------------------------------
-- Q2. Status distribution (count + percent)
-- Answers: "What is the status mix?"
-- ------------------------------------------------------------
WITH totals AS (
  SELECT COUNT(*)::numeric AS total_claims
  FROM claims
)
SELECT
  c.status,
  COUNT(*) AS claims_count,
  ROUND(COUNT(*)::numeric * 100.0 / t.total_claims, 2) AS pct_of_claims
FROM claims c
CROSS JOIN totals t
GROUP BY c.status, t.total_claims
ORDER BY claims_count DESC;

-- ------------------------------------------------------------
-- Q3. Closed decisions distribution
-- Answers: "Among CLOSED claims, what decisions are made?"
-- ------------------------------------------------------------
WITH closed_totals AS (
  SELECT COUNT(*)::numeric AS total_closed
  FROM claims
  WHERE status = 'Closed'
)
SELECT
  c.decision,
  COUNT(*) AS closed_count,
  ROUND(COUNT(*)::numeric * 100.0 / ct.total_closed, 2) AS pct_of_closed
FROM claims c
CROSS JOIN closed_totals ct
WHERE c.status = 'Closed'
GROUP BY c.decision, ct.total_closed
ORDER BY closed_count DESC;

-- ------------------------------------------------------------
-- Q4. Claim amount summary by decision (Closed only)
-- Answers: "How do claim amounts differ by decision?"
-- ------------------------------------------------------------
SELECT
  decision,
  COUNT(*) AS claim_count,
  ROUND(AVG(claim_amount_nok), 2) AS avg_amount_nok,
  ROUND(SUM(claim_amount_nok), 2) AS sum_amount_nok,
  ROUND(MAX(claim_amount_nok), 2) AS max_amount_nok
FROM claims
WHERE status = 'Closed'
  AND decision IS NOT NULL
GROUP BY decision
ORDER BY claim_count DESC;

-- ------------------------------------------------------------
-- Q5. Claims by region (count)
-- Answers: "Where do claims come from?"
-- ------------------------------------------------------------
SELECT
  region,
  COUNT(*) AS claims_count
FROM claims
GROUP BY region
ORDER BY claims_count DESC;

-- ------------------------------------------------------------
-- Q6. Claims by care_level (count)
-- Answers: "What care levels are involved most?"
-- ------------------------------------------------------------
SELECT
  care_level,
  COUNT(*) AS claims_count
FROM claims
GROUP BY care_level
ORDER BY claims_count DESC;

-- ------------------------------------------------------------
-- Q7. Claims by patient_sex (count)
-- Answers: "What is the sex distribution in the dataset?"
-- ------------------------------------------------------------
SELECT
  patient_sex,
  COUNT(*) AS claims_count
FROM claims
GROUP BY patient_sex
ORDER BY claims_count DESC;

-- ------------------------------------------------------------
-- Q8. Top 10 providers by number of claims (claims → providers)
-- Answers: "Which providers appear most often in claims?"
-- ------------------------------------------------------------
SELECT
  p.provider_name,
  p.region AS provider_region,
  COUNT(*) AS claims_count
FROM claims c
JOIN providers p
  ON p.provider_id = c.provider_id
GROUP BY p.provider_name, p.region
ORDER BY claims_count DESC, p.provider_name
LIMIT 10;

-- ------------------------------------------------------------
-- Q9. Average processing time for Closed claims
-- Answers: "How long does it take from received to decision?"
-- Output: average days (numeric), overall + by region
-- ------------------------------------------------------------


-- Q9a. Overall average processing time (days)
SELECT
  ROUND(AVG((decision_date - received_date)::numeric), 2) AS avg_processing_days
FROM claims
WHERE status = 'Closed'
  AND decision_date IS NOT NULL;


-- Q9b. By region average processing time (days)
SELECT
  region,
  COUNT(*) AS closed_claims,
  ROUND(AVG((decision_date - received_date)::numeric), 2) AS avg_processing_days
FROM claims
WHERE status = 'Closed'
  AND decision_date IS NOT NULL
GROUP BY region
ORDER BY avg_processing_days DESC, closed_claims DESC;


-- ------------------------------------------------------------
-- Q10. Top 10 medical codes
-- Answers: "Which medical codes are most common on claims?"
-- ------------------------------------------------------------
SELECT
  mc.medical_code_id,
  mc.code_system,
  mc.code,
  mc.code_title,
  COUNT(*) AS usage_count
FROM claim_medical_codes cmc
JOIN medical_codes mc
  ON mc.medical_code_id = cmc.medical_code_id
GROUP BY mc.medical_code_id, mc.code_system, mc.code, mc.code_title
ORDER BY usage_count DESC, mc.code_system, mc.code
LIMIT 10;

-- ------------------------------------------------------------
-- Q11. Top 10 injury types
-- Answers: "Which injury types are most common on claims?"
-- ------------------------------------------------------------
SELECT
  it.injury_group,
  it.injury_name,
  COUNT(*) AS usage_count
FROM claim_injuries ci
JOIN injury_types it
  ON it.injury_type_id = ci.injury_type_id
GROUP BY it.injury_group, it.injury_name
ORDER BY usage_count DESC, it.injury_group, it.injury_name
LIMIT 10;
