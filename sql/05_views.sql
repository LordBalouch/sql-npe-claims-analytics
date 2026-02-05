-- Reporting views for Power BI
-- Project: SQL NPE Claims Analytics (Synthetic)
-- Database: PostgreSQL 16, DB: npe_claims_demo, schema: public
--
-- Design principles:
-- - Stable, Power BI-friendly grains (month/region/provider)
-- - Simple aggregations + minimal join complexity
-- - Rerun-friendly (DROP VIEW IF EXISTS)
-- - Avoid divide-by-zero (return NULL when denominator is 0)
--
-- Usage in Power BI:
-- - Treat these as "reporting tables" (import mode).
-- - Add a date table in Power BI and relate to vw_monthly_kpi.month_start_date.

BEGIN;

-- -------------------------------------------------------------------
-- V1) vw_monthly_kpi
-- Grain: month_start_date (YYYY-MM-01)
-- Purpose: executive KPIs over time (received volume, closures, rates, payout, processing time)
-- Notes:
-- - claims_received counts all claims by received_date month
-- - closed_claims counts status='Closed' by decision_date month (closure month)
-- - payout & processing metrics computed for Closed claims only (closure month)
-- - rates computed only when closed_claims > 0 else NULL
-- -------------------------------------------------------------------
DROP VIEW IF EXISTS public.vw_monthly_kpi;

CREATE VIEW public.vw_monthly_kpi AS
WITH months AS (
  -- Anchor set of months that appear in either received_date or decision_date
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
    SUM(claim_amount_nok) AS total_payout_nok,
    AVG((decision_date - received_date)) AS avg_processing_interval
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
  CASE
    WHEN c.avg_processing_interval IS NOT NULL
      THEN EXTRACT(DAY FROM c.avg_processing_interval)::numeric
    ELSE NULL
  END AS avg_processing_days_closed
FROM months m
LEFT JOIN received r
  ON r.month_start_date = m.month_start_date
LEFT JOIN closed c
  ON c.month_start_date = m.month_start_date
ORDER BY m.month_start_date;

-- -------------------------------------------------------------------
-- V2) vw_region_kpi
-- Grain: region
-- Purpose: compare workload/outcomes across regions (volume, closure, rates, payout, processing)
-- Notes:
-- - total_claims counts all claims in region (no date filter)
-- - Closed metrics computed only for status='Closed'
-- - rates computed only when closed_claims > 0 else NULL
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
  CASE
    WHEN COUNT(*) FILTER (
      WHERE c.status='Closed'
        AND c.decision_date IS NOT NULL
        AND c.received_date IS NOT NULL
    ) > 0
      THEN AVG((c.decision_date - c.received_date)) FILTER (
        WHERE c.status='Closed'
          AND c.decision_date IS NOT NULL
          AND c.received_date IS NOT NULL
      )
    ELSE NULL
  END AS avg_processing_interval
FROM public.claims c
GROUP BY c.region;

-- Present avg_processing_days as numeric days (Power BI-friendly)
DROP VIEW IF EXISTS public.vw_region_kpi__final;
CREATE VIEW public.vw_region_kpi__final AS
SELECT
  region,
  total_claims,
  closed_claims,
  approval_rate_closed,
  total_payout_nok,
  CASE
    WHEN avg_processing_interval IS NOT NULL
      THEN EXTRACT(DAY FROM avg_processing_interval)::numeric
    ELSE NULL
  END AS avg_processing_days_closed
FROM public.vw_region_kpi;

-- Swap name to keep only the final view name exposed
DROP VIEW IF EXISTS public.vw_region_kpi;
ALTER VIEW public.vw_region_kpi__final RENAME TO vw_region_kpi;

-- -------------------------------------------------------------------
-- V3) vw_provider_summary
-- Grain: provider_id
-- Purpose: provider benchmarking (volume/outcomes/payout/processing)
-- Notes:
-- - Join providers + claims; group by provider fields
-- - rates computed only when closed_claims > 0 else NULL
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
  CASE
    WHEN COUNT(c.claim_id) FILTER (
      WHERE c.status='Closed'
        AND c.decision_date IS NOT NULL
        AND c.received_date IS NOT NULL
    ) > 0
      THEN EXTRACT(
        DAY FROM AVG((c.decision_date - c.received_date)) FILTER (
          WHERE c.status='Closed'
            AND c.decision_date IS NOT NULL
            AND c.received_date IS NOT NULL
        )
      )::numeric
    ELSE NULL
  END AS avg_processing_days_closed
FROM public.providers p
LEFT JOIN public.claims c
  ON c.provider_id = p.provider_id
GROUP BY
  p.provider_id, p.provider_name, p.provider_type, p.region;

COMMIT;
