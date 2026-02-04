-- Part 3: Synthetic seed data for npe_claims_demo
-- Rerun-friendly + constraint-safe
-- Engine: PostgreSQL 16


BEGIN;
-- Make randomness stable-ish across runs
SELECT setseed(0.4242);

-- 1) Rerun-friendly truncate in dependency-safe order
TRUNCATE TABLE
  claim_injuries,
  claim_medical_codes,
  claims,
  injury_types,
  medical_codes,
  providers
RESTART IDENTITY;

-- 2) Dimension tables --------------------------------------------------------

-- Providers (target ~30; must respect UNIQUE(provider_name, region))
WITH regions AS (
  SELECT unnest(ARRAY[
    'Oslo','Viken','Vestland','Rogaland','Trondelag','Nordland',
    'Innlandet','Agder','MoreOgRomsdal','Telemark','Troms','Finnmark','Other'
  ]) AS region
),
types AS (
  SELECT unnest(ARRAY['Hospital','Clinic','GP','Specialist','Other']) AS provider_type
),
base AS (
  SELECT
    r.region,
    gs AS seq,
    (SELECT provider_type FROM types ORDER BY provider_type LIMIT 1 OFFSET ((gs - 1) % 5)) AS provider_type
  FROM regions r
  CROSS JOIN generate_series(1, 3) AS gs
)
INSERT INTO providers (provider_name, org_number, provider_type, region, active)
SELECT
  CASE
    WHEN provider_type = 'Hospital'   THEN region || ' Hospital '   || chr(64 + seq)
    WHEN provider_type = 'Clinic'     THEN region || ' Clinic '     || chr(64 + seq)
    WHEN provider_type = 'GP'         THEN region || ' GP Center '  || chr(64 + seq)
    WHEN provider_type = 'Specialist' THEN region || ' Specialist ' || chr(64 + seq)
    ELSE region || ' Provider ' || chr(64 + seq)
  END AS provider_name,
  'NO' || lpad((100000000 + (row_number() OVER ()) )::text, 9, '0') AS org_number,
  provider_type,
  region,
  CASE WHEN random() < 0.92 THEN true ELSE false END AS active
FROM base;

-- Medical codes (84 total; respects UNIQUE(code_system, code))
WITH sys AS (
  SELECT unnest(ARRAY['ICD10','NCSP','ICPC2','Other']) AS code_system
),
n AS (
  SELECT s.code_system, gs AS seq
  FROM sys s
  CROSS JOIN generate_series(1, 21) AS gs
)
INSERT INTO medical_codes (code_system, code, code_title, active)
SELECT
  code_system,
  CASE
    WHEN code_system = 'ICD10' THEN 'I' || lpad(seq::text, 2, '0') || '.' || lpad(((seq*7) % 10)::text, 1, '0')
    WHEN code_system = 'NCSP'  THEN 'N' || lpad(seq::text, 3, '0')
    WHEN code_system = 'ICPC2' THEN 'P' || lpad(seq::text, 2, '0')
    ELSE 'O' || lpad(seq::text, 3, '0')
  END AS code,
  CASE
    WHEN code_system = 'ICD10' THEN 'ICD10 demo diagnosis ' || seq
    WHEN code_system = 'NCSP'  THEN 'NCSP demo procedure ' || seq
    WHEN code_system = 'ICPC2' THEN 'ICPC2 demo primary care code ' || seq
    ELSE 'Other demo code ' || seq
  END AS code_title,
  CASE WHEN random() < 0.95 THEN true ELSE false END AS active
FROM n;

-- Injury types (16 total; respects UNIQUE(injury_group, injury_name))
WITH g AS (
  SELECT unnest(ARRAY['Surgical','Medication','Infection','Diagnostic','Other']) AS injury_group
),
n AS (
  SELECT
    (SELECT injury_group FROM g ORDER BY injury_group LIMIT 1 OFFSET ((gs - 1) % 5)) AS injury_group,
    gs AS seq
  FROM generate_series(1, 16) AS gs
)
INSERT INTO injury_types (injury_group, injury_name, severity, active)
SELECT
  injury_group,
  injury_group || ' issue ' || seq AS injury_name,
  (1 + ((seq - 1) % 5))::smallint AS severity,
  true AS active
FROM n;

-- 3) Claims (target 1200) ----------------------------------------------------

WITH p AS (
  SELECT provider_id FROM providers
),
base AS (
  SELECT
    gs AS seq,
    (current_date - (floor(random() * 1096))::int) AS received_date,
    CASE
      WHEN random() < 0.70 THEN 'Closed'
      WHEN random() < 0.90 THEN 'InReview'
      ELSE 'Received'
    END AS status,
    (floor(random() * 91))::smallint AS patient_age,
    CASE
      WHEN random() < 0.49 THEN 'M'
      WHEN random() < 0.98 THEN 'F'
      WHEN random() < 0.99 THEN 'X'
      ELSE 'U'
    END AS patient_sex,
    CASE
      WHEN random() < 0.55 THEN 'Primary'
      WHEN random() < 0.85 THEN 'Specialist'
      ELSE 'Hospital'
    END AS care_level,
    CASE
      WHEN random() < 0.18 THEN 'Oslo'
      WHEN random() < 0.38 THEN 'Viken'
      WHEN random() < 0.50 THEN 'Vestland'
      WHEN random() < 0.60 THEN 'Rogaland'
      WHEN random() < 0.69 THEN 'Trondelag'
      WHEN random() < 0.76 THEN 'Innlandet'
      WHEN random() < 0.82 THEN 'Agder'
      WHEN random() < 0.87 THEN 'MoreOgRomsdal'
      WHEN random() < 0.91 THEN 'Nordland'
      WHEN random() < 0.94 THEN 'Telemark'
      WHEN random() < 0.97 THEN 'Troms'
      WHEN random() < 0.985 THEN 'Finnmark'
      ELSE 'Other'
    END AS region,
    (SELECT provider_id FROM p ORDER BY random() LIMIT 1) AS provider_id
  FROM generate_series(1, 1200) AS gs
),
closed_enriched AS (
  SELECT
    b.*,
    CASE
      WHEN b.status <> 'Closed' THEN NULL
      ELSE
        CASE
          WHEN random() < 0.55 THEN 'Approved'
          WHEN random() < 0.85 THEN 'Rejected'
          ELSE 'PartiallyApproved'
        END
    END AS decision,
    CASE
      WHEN b.status <> 'Closed' THEN NULL
      ELSE (b.received_date + (1 + floor(random() * 180))::int)
    END AS decision_date
  FROM base b
),
amounts AS (
  SELECT
    c.*,
    CASE
      WHEN c.status <> 'Closed' THEN 0::numeric(12,2)
      WHEN c.decision = 'Rejected' THEN 0::numeric(12,2)
      ELSE
        round(
          (
            CASE
              WHEN random() < 0.95 THEN (random() * random() * 250000.0)
              ELSE (250000.0 + (random() * 1750000.0))
            END
          )::numeric
        , 2)
    END AS claim_amount_nok
  FROM closed_enriched c
)
INSERT INTO claims (
  claim_reference,
  patient_age,
  patient_sex,
  region,
  received_date,
  decision_date,
  status,
  decision,
  care_level,
  claim_amount_nok,
  provider_id
)
SELECT
  'CLM-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(seq::text, 6, '0') AS claim_reference,
  patient_age,
  patient_sex,
  region,
  received_date,
  decision_date,
  status,
  decision,
  care_level,
  claim_amount_nok,
  provider_id
FROM amounts;

-- 4) Bridge tables -----------------------------------------------------------

-- claim_medical_codes: 1–3 codes per claim
INSERT INTO claim_medical_codes (claim_id, medical_code_id, code_role)
SELECT
  c.claim_id,
  x.medical_code_id,
  CASE WHEN x.rn = 1 THEN 'Primary' ELSE 'Secondary' END AS code_role
FROM claims c
JOIN LATERAL (
  SELECT
    mc.medical_code_id,
    row_number() OVER () AS rn
  FROM medical_codes mc
  WHERE mc.active = true
  ORDER BY random()
  LIMIT (1 + floor(random() * 3))::int
) x ON true;

-- claim_injuries: 1–2 injuries per claim
INSERT INTO claim_injuries (claim_id, injury_type_id, is_primary)
SELECT
  c.claim_id,
  x.injury_type_id,
  (x.rn = 1) AS is_primary
FROM claims c
JOIN LATERAL (
  SELECT
    it.injury_type_id,
    row_number() OVER () AS rn
  FROM injury_types it
  WHERE it.active = true
  ORDER BY random()
  LIMIT (1 + floor(random() * 2))::int
) x ON true;

-- 5) Verification section ----------------------------------------------------

SELECT 'providers' AS table_name, COUNT(*) AS row_count FROM providers
UNION ALL SELECT 'medical_codes', COUNT(*) FROM medical_codes
UNION ALL SELECT 'injury_types', COUNT(*) FROM injury_types
UNION ALL SELECT 'claims', COUNT(*) FROM claims
UNION ALL SELECT 'claim_medical_codes', COUNT(*) FROM claim_medical_codes
UNION ALL SELECT 'claim_injuries', COUNT(*) FROM claim_injuries
ORDER BY table_name;

SELECT status, COUNT(*) AS n,
       ROUND(100.0 * COUNT(*) / NULLIF((SELECT COUNT(*) FROM claims),0), 1) AS pct
FROM claims
GROUP BY status
ORDER BY n DESC;

SELECT
  SUM(CASE WHEN status <> 'Closed' AND decision IS NOT NULL THEN 1 ELSE 0 END) AS decisions_when_not_closed
FROM claims;

SELECT MIN(received_date) AS min_received_date, MAX(received_date) AS max_received_date
FROM claims;

SELECT
  MIN(claim_amount_nok) AS min_amount,
  MAX(claim_amount_nok) AS max_amount,
  ROUND(AVG(claim_amount_nok), 2) AS avg_amount
FROM claims;

COMMIT;
