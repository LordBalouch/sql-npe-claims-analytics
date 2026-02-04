-- sql/01_schema.sql
-- Project: SQL NPE Claims Analytics (Synthetic)
-- Engine: PostgreSQL 16
-- Part 2: Schema (DDL) only. No seed data.

-- =========================
-- RERUN-FRIENDLY DROPS
-- =========================
DROP TABLE IF EXISTS claim_injuries CASCADE;
DROP TABLE IF EXISTS claim_medical_codes CASCADE;
DROP TABLE IF EXISTS claims CASCADE;
DROP TABLE IF EXISTS injury_types CASCADE;
DROP TABLE IF EXISTS medical_codes CASCADE;
DROP TABLE IF EXISTS providers CASCADE;

-- =========================
-- 1) PROVIDERS
-- =========================
CREATE TABLE providers (
  provider_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider_name      TEXT NOT NULL,
  org_number         TEXT NULL,
  provider_type      TEXT NOT NULL,
  region             TEXT NOT NULL,
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_providers_provider_type
    CHECK (provider_type IN ('Hospital','Clinic','GP','Specialist','Other')),

  CONSTRAINT chk_providers_region
    CHECK (region IN ('Oslo','Viken','Vestland','Rogaland','Trondelag','Nordland','Innlandet','Agder','MoreOgRomsdal','Telemark','Troms','Finnmark','Other'))
);

CREATE UNIQUE INDEX ux_providers_name_region
  ON providers (provider_name, region);

-- =========================
-- 2) CLAIMS
-- =========================
CREATE TABLE claims (
  claim_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  claim_reference    TEXT NOT NULL,
  patient_age        SMALLINT NOT NULL,
  patient_sex        TEXT NOT NULL,
  region             TEXT NOT NULL,
  received_date      DATE NOT NULL,
  decision_date      DATE NULL,
  status             TEXT NOT NULL,
  decision           TEXT NULL,
  care_level         TEXT NOT NULL,
  claim_amount_nok   NUMERIC(12,2) NOT NULL DEFAULT 0,
  provider_id        BIGINT NOT NULL REFERENCES providers(provider_id),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_claims_claim_reference
    UNIQUE (claim_reference),

  CONSTRAINT chk_claims_patient_age
    CHECK (patient_age BETWEEN 0 AND 120),

  CONSTRAINT chk_claims_patient_sex
    CHECK (patient_sex IN ('M','F','X','U')),

  CONSTRAINT chk_claims_region
    CHECK (region IN ('Oslo','Viken','Vestland','Rogaland','Trondelag','Nordland','Innlandet','Agder','MoreOgRomsdal','Telemark','Troms','Finnmark','Other')),

  CONSTRAINT chk_claims_status
    CHECK (status IN ('Received','InReview','Closed')),

  CONSTRAINT chk_claims_decision
    CHECK (decision IS NULL OR decision IN ('Approved','Rejected','PartiallyApproved')),

  CONSTRAINT chk_claims_care_level
    CHECK (care_level IN ('Primary','Specialist','Hospital')),

  CONSTRAINT chk_claims_decision_date_after_received
    CHECK (decision_date IS NULL OR decision_date >= received_date),

  CONSTRAINT chk_claims_closed_requires_decision
    CHECK (
      (status <> 'Closed' AND decision IS NULL)
      OR
      (status = 'Closed' AND decision IS NOT NULL)
    )
);

CREATE INDEX ix_claims_received_date
  ON claims (received_date);

CREATE INDEX ix_claims_decision_date
  ON claims (decision_date);

CREATE INDEX ix_claims_status
  ON claims (status);

CREATE INDEX ix_claims_region
  ON claims (region);

CREATE INDEX ix_claims_provider_id
  ON claims (provider_id);

CREATE INDEX ix_claims_region_status_received
  ON claims (region, status, received_date);

-- =========================
-- 3) MEDICAL_CODES
-- =========================
CREATE TABLE medical_codes (
  medical_code_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code_system        TEXT NOT NULL,
  code               TEXT NOT NULL,
  code_title         TEXT NOT NULL,
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_medical_codes_system
    CHECK (code_system IN ('ICD10','NCSP','ICPC2','Other')),

  CONSTRAINT uq_medical_codes_system_code
    UNIQUE (code_system, code)
);

-- =========================
-- 4) CLAIM_MEDICAL_CODES (bridge)
-- =========================
CREATE TABLE claim_medical_codes (
  claim_id           BIGINT NOT NULL REFERENCES claims(claim_id) ON DELETE CASCADE,
  medical_code_id    BIGINT NOT NULL REFERENCES medical_codes(medical_code_id),
  code_role          TEXT NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_claim_medical_codes
    PRIMARY KEY (claim_id, medical_code_id),

  CONSTRAINT chk_claim_medical_codes_role
    CHECK (code_role IN ('Primary','Secondary'))
);

CREATE INDEX ix_claim_medical_codes_claim
  ON claim_medical_codes (claim_id);

CREATE INDEX ix_claim_medical_codes_code
  ON claim_medical_codes (medical_code_id);

-- =========================
-- 5) INJURY_TYPES
-- =========================
CREATE TABLE injury_types (
  injury_type_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  injury_group       TEXT NOT NULL,
  injury_name        TEXT NOT NULL,
  severity           SMALLINT NOT NULL,
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_injury_types_group
    CHECK (injury_group IN ('Surgical','Medication','Infection','Diagnostic','Other')),

  CONSTRAINT chk_injury_types_severity
    CHECK (severity BETWEEN 1 AND 5),

  CONSTRAINT uq_injury_types_group_name
    UNIQUE (injury_group, injury_name)
);

-- =========================
-- 6) CLAIM_INJURIES (bridge)
-- =========================
CREATE TABLE claim_injuries (
  claim_id           BIGINT NOT NULL REFERENCES claims(claim_id) ON DELETE CASCADE,
  injury_type_id     BIGINT NOT NULL REFERENCES injury_types(injury_type_id),
  is_primary         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_claim_injuries
    PRIMARY KEY (claim_id, injury_type_id)
);

CREATE INDEX ix_claim_injuries_claim
  ON claim_injuries (claim_id);

CREATE INDEX ix_claim_injuries_injury
  ON claim_injuries (injury_type_id);

CREATE INDEX ix_claim_injuries_primary
  ON claim_injuries (is_primary);
