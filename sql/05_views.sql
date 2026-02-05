-- Reporting views for Power BI
-- Project: SQL NPE Claims Analytics (Synthetic)
-- Database: PostgreSQL 16, DB: npe_claims_demo, schema: public
--
-- Design principles:
-- - Stable, Power BI-friendly grains (month/region/provider)
-- - Simple aggregations + minimal join complexity
-- - Rerun-friendly (DROP VIEW IF EXISTS)
-- - Avoid divide-by-zero (return NULL when denominator is 0)

BEGIN;

-- Helper convention for processing days:
-- Convert date differences to INTERVAL safely by casting to timestamp, then compute days via epoch seconds.
-- days = EXTRACT(EPOCH FROM (decision_ts - received_ts)) / 86400.0

-- -------------------------------------------------------------------
-- V1) vw_monthly_kpi
-- Grain: month_start_date (YYYY-MM-01)
-- Purpose: executive KPIs over time
-- - claims_received: by received_date month
-- - closed_claims + payout + processing: by decision_date month (closure month)
-- -------------------------------------------------------------------
DROP VIEW IF EXISTS public.vw_monthly_kpi;

CREATE VIEW public.vw_monthly_kpi AS
WITH months AS (
  SELECT DISTINCT date_trunc('month', received_date)::date AS month_start_date
  FROM public.claims
  WHERE received_date IS NOT NULL
  UNION
  SELECT DISTINCT date_trunc('month', decision_date)::date AS month_start_date
  FROM public.claims
  WHERE decision_date IS NOT NULL
),
received AS (
  SELECT
    date_trunc('month', received_date)::date AS month_start_date,
    COUNT(*)::int AS claims_received
  FROM public.claims
  WHERE received_date IS NOT NULL
  GROUP BY 1
),
closed AS (
  SELECT
    date_trunc('month', decision_date)::date AS month_start_date,
    COUNT(*)::int AS closed_claims,
    COUNT(*) FILTER (WHERE decision IN ('Approved', 'PartiallyApproved'))::int AS approved_or_partial_closed,
    COUNT(*) FILTER (WHERE decision = 'Rejected')::int AS rejected_closed,
    SUM(claim_amount_nok)::numeric AS total_payout_nok,
    -- avg processing days for closed claims (closure month)
    AVG(
      EXTRACT(EPOCH FROM (decision_date::timestamp - received_date::timestamp)) / 86400.0
    )::numeric AS avg_processing_days_closed
  FROM public.claims
  WHERE status = 'Closed'
    AND decision_date IS NOT NULL
    AND received_date IS NOT NULL
  GROUP BY 1
)
SELECT
  m.month_start_date,
  COALESCE(r.claims_received, 0)::int AS claims_received,
  COALESCE(c.closed_claims, 0)::int AS closed_claims,
  CASE
    WHEN COALESCE(c.closed_claims, 0) > 0
      THEN (c.approved_or_partial_closed::numeric / c.closed_claims::numeric)
    ELSE NULL
  END AS approval_rate_closed,
  CASE
    WHEN COALESCE(c.closed_claims, 0) > 0
      THEN (c.rejected_closed::numeric / c.closed_claims::numeric)
    ELSE NULL
  END AS rejected_rate_closed,
  COALESCE(c.total_payout_nok, 0)::numeric AS total_payout_nok,
  c.avg_processing_days_closed
FROM months m
LEFT JOIN received r
  ON r.month_start_date = m.month_start_date
LEFT JOIN closed c
  ON c.month_start_date = m.month_start_date
ORDER BY m.month_start_date;

-- -------------------------------------------------------------------
-- V2) vw_region_kpi
-- Grain: region
-- Purpose: compare workload/outcomes across regions
-- -------------------------------------------------------------------
DROP VIEW IF EXISTS public.vw_region_kpi;

CREATE VIEW public.vw_region_kpi AS
SELECT
  c.region,
  COUNT(*)::int AS total_claims,
  COUNT(*) FILTER (WHERE c.status = 'Closed')::int AS closed_claims,
  CASE
    WHEN COUNT(*) FILTER (WHERE c.status = 'Closed') > 0
      THEN (
        COUNT(*) FILTER (
          WHERE c.status = 'Closed'
            AND c.decision IN ('Approved', 'PartiallyApproved')
        )::numeric
        / COUNT(*) FILTER (WHERE c.status = 'Closed')::numeric
      )
    ELSE NULL
  END AS approval_rate_closed,
  COALESCE(
    SUM(c.claim_amount_nok) FILTER (WHERE c.status = 'Closed'),
    0
  )::numeric AS total_payout_nok,
  AVG(
    EXTRACT(EPOCH FROM (c.decision_date::timestamp - c.received_date::timestamp)) / 86400.0
  ) FILTER (
    WHERE c.status='Closed'
      AND c.decision_date IS NOT NULL
      AND c.received_date IS NOT NULL
  )::numeric AS avg_processing_days_closed
FROM public.claims c
GROUP BY c.region;

-- -------------------------------------------------------------------
-- V3) vw_provider_summary
-- Grain: provider_id
-- Purpose: provider benchmarking
-- -------------------------------------------------------------------
DROP VIEW IF EXISTS public.vw_provider_summary;

CREATE VIEW public.vw_provider_summary AS
SELECT
  p.provider_id,
  p.provider_name,
  p.provider_type,
  p.region,
  COUNT(c.claim_id)::int AS total_claims,
  COUNT(c.claim_id) FILTER (WHERE c.status = 'Closed')::int AS closed_claims,
  CASE
    WHEN COUNT(c.claim_id) FILTER (WHERE c.status = 'Closed') > 0
      THEN (
        COUNT(c.claim_id) FILTER (
          WHERE c.status='Closed'
            AND c.decision IN ('Approved', 'PartiallyApproved')
        )::numeric
        / COUNT(c.claim_id) FILTER (WHERE c.status='Closed')::numeric
      )
    ELSE NULL
  END AS approval_rate_closed,
  COALESCE(
    SUM(c.claim_amount_nok) FILTER (WHERE c.status = 'Closed'),
    0
  )::numeric AS total_payout_nok,
  AVG(
    EXTRACT(EPOCH FROM (c.decision_date::timestamp - c.received_date::timestamp)) / 86400.0
  ) FILTER (
    WHERE c.status='Closed'
      AND c.decision_date IS NOT NULL
      AND c.received_date IS NOT NULL
  )::numeric AS avg_processing_days_closed
FROM public.providers p
LEFT JOIN public.claims c
  ON c.provider_id = p.provider_id
GROUP BY
  p.provider_id, p.provider_name, p.provider_type, p.region;

COMMIT;
