# SQL NPE Claims Analytics (Synthetic)

SQL-first portfolio project that demonstrates basic → intermediate SQL skills in a realistic healthcare/claims setting using a clean relational schema, reproducible seed data, and report-ready views.

## Tech (Part 1)
- Database: PostgreSQL (default)
- GUI: DBeaver (default)
- Local DB name: `npe_claims_demo`

## How to run (file order)
1. Create an empty database named `npe_claims_demo`
2. Run SQL files in this order:
   - `sql/01_schema.sql` (Part 2)
   - `sql/02_seed_data.sql` (Part 3)
   - `sql/03_queries_basic.sql` (Part 4)
   - `sql/04_queries_intermediate.sql` (Part 5)
   - `sql/05_views.sql` (Part 5)

## Project structure
- `sql/` — schema, seed data, queries, views
- `docs/session_log.md` — running project log (what was done each session)
