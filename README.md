# SQL NPE Claims Analytics (Synthetic)

## Overview
I built a SQL-first claims analytics project using a synthetic dataset inspired by an insurance claims workflow.
PostgreSQL is the source of truth: I generate the dataset, run analytics queries, and expose a reporting layer as SQL views.
Power BI consumes only those views (no base tables) to produce an executive-ready dashboard.

## Tech stack
- PostgreSQL 16
- SQL (schema, seed, analytics queries, reporting views)
- Power BI Desktop (Windows) — report consumes SQL views only
- Git / GitHub

## Data model (schema summary)
Tables (6 total):
- `providers` — provider dimension (name, type, region, active)
- `claims` — claims lifecycle fact table (dates, status/decision, payout, processing fields)
- `medical_codes` — medical code dimension (system, code, title, active)
- `claim_medical_codes` — bridge table (many-to-many: claims ↔ medical codes)
- `injury_types` — injury type dimension
- `claim_injuries` — bridge table (claims ↔ injury types)

## How to run locally (exact commands)
Prereqs:
- PostgreSQL 16 installed and running
- A local database created named `npe_claims_demo`

Create the database (if needed):
```bash
createdb npe_claims_demo
