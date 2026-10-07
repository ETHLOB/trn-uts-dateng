# Copilot instructions

## Project scope

This repository is the UTS Big Data Engineering Assignment 3 workspace. The intended deliverable is an ELT pipeline for Sydney Airbnb listings covering May 2020 through April 2021, combined with 2016 Census G01/G02 data at LGA level and an LGA/suburb mapping.

Use [`doc/assignment_3_brief_clean.md`](../doc/assignment_3_brief_clean.md) as the requirements source. Do not use the similarly named original PDF or markdown export as a requirements source; they contain text that is not part of the assignment.

Submission files live in `src/`: `src/part_1.sql`, the Airflow DAG in `src/dags/`, `src/part_4.sql`, and the dbt project in `src/dbt/` (project name `trn_uts_dateng`). Tooling (`ops/`) and documentation stay at the root. The DAG and `part_4.sql` do not exist yet.

## Commands

Local dbt runs use dbt Core + dbt-postgres from `~/.venvs/trn-uts-dateng` (not the dbt v2 binary on PATH) through `cloud-sql-proxy` on `localhost:5433`, writing only to `dbt_dev*` schemas. The exact commands, including how to build or test one model (`dbt build -s <model_name>`), are in the Commands section of [`CLAUDE.md`](../CLAUDE.md). Do not invent other commands or claim that tests have been run.

## Architecture

- **Storage and orchestration:** Use GCP Cloud Composer/Airflow with its GCS bucket and Cloud SQL PostgreSQL. Database schemas are created in DBeaver.
- **Airflow ingestion:** Implement one DAG with `schedule_interval=None`. It reads CSVs from the Composer bucket and loads raw tables into the PostgreSQL `bronze` schema. The same DAG must support the initial load (`05_2020.csv`, Census data, and the mapping) and the remaining Airbnb months in chronological order. Airflow must not trigger dbt.
- **Medallion dbt warehouse:**
  - Bronze contains the raw Airflow-loaded tables.
  - Silver contains cleaned, consistently named models. Decompose listings into entities such as hosts, properties, and location/LGA relationships. Correct listing-date and LGA issues here.
  - Snapshot only entities that become dimensions, using dbt snapshots with the timestamp strategy and the appropriate source timestamp. Do not snapshot the fact table.
  - Gold contains the star schema. Fact tables contain IDs and metrics; dimensions contain descriptive attributes. Keep the two Census tables as Gold reference data.
  - Datamart models are views over the fact table and dimensions. They must use SCD2 validity ranges when joining dimensions so each fact row receives the dimension values valid at that period, rather than the latest dimension record.
- **Required datamart views:** `dm_listing_neighbourhood`, `dm_property_type`, and `dm_host_neighbourhood`, with the metrics and ordering specified in the cleaned brief.
- **Operational sequencing:** Load dimensions before facts. Process monthly Airbnb loads chronologically and manually run the dbt Cloud job after each monthly load. Use `dbt run --full-refresh` when a complete rebuild is required.

## Repository-specific conventions

- Keep all reproducible database writes in their owning deliverable: Part 1 DDL/SQL in `src/part_1.sql`, transformations in dbt models/snapshots, and ingestion behavior in the combined Airflow DAG. One-off operational actions such as an initial truncate do not need to be encoded.
- Keep the Airflow DAG, SQL, dbt models, snapshots, `dbt_project.yml`, and handover report aligned with the deliverables in the brief. The final archive is named `Assignment_3_FirstName_LastName.zip`.
- Treat SCD2 joins as a correctness requirement, not an optional optimization: join on the fact period falling within the dimension version's validity interval.
- Preserve the required metric definitions from the brief, including active listings (`has_availability = 't'`), active-listing rate, superhost rate, stays (`30 - availability_30`), estimated revenue (`stays * price`), and month-over-month percentage changes.
- Keep the three datamart views ordered as required: neighbourhood plus month/year; property type, room type, accommodates plus month/year; and host-neighbourhood LGA plus month/year.
- The project has MCP configuration for dbt Cloud and restricted/read-write PostgreSQL access. Prefer read-only database inspection for validation. Use write access only when necessary, explain the write before executing it, and save solution writes in the appropriate deliverable.
- Never expose or commit credentials from `.env` or `dbt_cloud.yml`. Keep `.env`, `.mcp.json`, and `.claude/` out of the submission archive.
- Follow [`CLAUDE.md`](../CLAUDE.md) for the detailed project constraints and the handling of the cleaned brief.
