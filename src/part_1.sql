/* =====================================================================
   part_1.sql: Bronze layer for the Sydney Airbnb + 2016 Census ELT pipeline
   Pure SQL, run in DBeaver (or any SQL client) connected to the Cloud SQL
   PostgreSQL instance as user postgres.

   Design
   - Bronze keeps the files exactly as delivered: every column is TEXT, so a
     load never fails on formats such as '23/9/2009' or empty strings.
     Typing, cleaning and renaming happen in Silver (dbt).
   - Column names are the CSV headers in lower case (Postgres folds unquoted
     identifiers to lower case anyway).
   - Two lineage columns per table: <_source_file> (which file the row came from;
     Silver derives the listing month from it, because <SCRAPED_DATE> drifts:
     07_2020.csv holds scrapes up to 2020-09-05) and <_loaded_at>.
   - The Airflow DAG loads as the IAM database user of the Composer service
     account (no password for enhanced security). It gets only the rights it
     needs through the group role bronze_loader.
   ===================================================================== */

-- 1. Schema --------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS bronze;

-- 2. Raw tables ------------------------------------------------------------
-- Airbnb Sydney monthly snapshots, May 2020 to April 2021 (one file per month,
-- identical 22-column header)
CREATE TABLE IF NOT EXISTS bronze.raw_listings (
    listing_id                       TEXT,
    scrape_id                        TEXT,
    scraped_date                     TEXT,
    host_id                          TEXT,
    host_name                        TEXT,
    host_since                       TEXT,
    host_is_superhost                TEXT,
    host_neighbourhood               TEXT,
    listing_neighbourhood            TEXT,
    property_type                    TEXT,
    room_type                        TEXT,
    accommodates                     TEXT,
    price                            TEXT,
    has_availability                 TEXT,
    availability_30                  TEXT,
    number_of_reviews                TEXT,
    review_scores_rating             TEXT,
    review_scores_accuracy           TEXT,
    review_scores_cleanliness        TEXT,
    review_scores_checkin            TEXT,
    review_scores_communication      TEXT,
    review_scores_value              TEXT,
    _source_file                     TEXT        NOT NULL,                -- lineage: file the row came from
    _loaded_at                       TIMESTAMPTZ NOT NULL DEFAULT now()   -- lineage: load time
);

-- 2016 Census G01, Selected Person Characteristics by Sex, NSW LGAs (109 columns)
CREATE TABLE IF NOT EXISTS bronze.raw_census_g01 (
    lga_code_2016                    TEXT,
    tot_p_m                          TEXT,
    tot_p_f                          TEXT,
    tot_p_p                          TEXT,
    age_0_4_yr_m                     TEXT,
    age_0_4_yr_f                     TEXT,
    age_0_4_yr_p                     TEXT,
    age_5_14_yr_m                    TEXT,
    age_5_14_yr_f                    TEXT,
    age_5_14_yr_p                    TEXT,
    age_15_19_yr_m                   TEXT,
    age_15_19_yr_f                   TEXT,
    age_15_19_yr_p                   TEXT,
    age_20_24_yr_m                   TEXT,
    age_20_24_yr_f                   TEXT,
    age_20_24_yr_p                   TEXT,
    age_25_34_yr_m                   TEXT,
    age_25_34_yr_f                   TEXT,
    age_25_34_yr_p                   TEXT,
    age_35_44_yr_m                   TEXT,
    age_35_44_yr_f                   TEXT,
    age_35_44_yr_p                   TEXT,
    age_45_54_yr_m                   TEXT,
    age_45_54_yr_f                   TEXT,
    age_45_54_yr_p                   TEXT,
    age_55_64_yr_m                   TEXT,
    age_55_64_yr_f                   TEXT,
    age_55_64_yr_p                   TEXT,
    age_65_74_yr_m                   TEXT,
    age_65_74_yr_f                   TEXT,
    age_65_74_yr_p                   TEXT,
    age_75_84_yr_m                   TEXT,
    age_75_84_yr_f                   TEXT,
    age_75_84_yr_p                   TEXT,
    age_85ov_m                       TEXT,
    age_85ov_f                       TEXT,
    age_85ov_p                       TEXT,
    counted_census_night_home_m      TEXT,
    counted_census_night_home_f      TEXT,
    counted_census_night_home_p      TEXT,
    count_census_nt_ewhere_aust_m    TEXT,
    count_census_nt_ewhere_aust_f    TEXT,
    count_census_nt_ewhere_aust_p    TEXT,
    indigenous_psns_aboriginal_m     TEXT,
    indigenous_psns_aboriginal_f     TEXT,
    indigenous_psns_aboriginal_p     TEXT,
    indig_psns_torres_strait_is_m    TEXT,
    indig_psns_torres_strait_is_f    TEXT,
    indig_psns_torres_strait_is_p    TEXT,
    indig_bth_abor_torres_st_is_m    TEXT,
    indig_bth_abor_torres_st_is_f    TEXT,
    indig_bth_abor_torres_st_is_p    TEXT,
    indigenous_p_tot_m               TEXT,
    indigenous_p_tot_f               TEXT,
    indigenous_p_tot_p               TEXT,
    birthplace_australia_m           TEXT,
    birthplace_australia_f           TEXT,
    birthplace_australia_p           TEXT,
    birthplace_elsewhere_m           TEXT,
    birthplace_elsewhere_f           TEXT,
    birthplace_elsewhere_p           TEXT,
    lang_spoken_home_eng_only_m      TEXT,
    lang_spoken_home_eng_only_f      TEXT,
    lang_spoken_home_eng_only_p      TEXT,
    lang_spoken_home_oth_lang_m      TEXT,
    lang_spoken_home_oth_lang_f      TEXT,
    lang_spoken_home_oth_lang_p      TEXT,
    australian_citizen_m             TEXT,
    australian_citizen_f             TEXT,
    australian_citizen_p             TEXT,
    age_psns_att_educ_inst_0_4_m     TEXT,
    age_psns_att_educ_inst_0_4_f     TEXT,
    age_psns_att_educ_inst_0_4_p     TEXT,
    age_psns_att_educ_inst_5_14_m    TEXT,
    age_psns_att_educ_inst_5_14_f    TEXT,
    age_psns_att_educ_inst_5_14_p    TEXT,
    age_psns_att_edu_inst_15_19_m    TEXT,
    age_psns_att_edu_inst_15_19_f    TEXT,
    age_psns_att_edu_inst_15_19_p    TEXT,
    age_psns_att_edu_inst_20_24_m    TEXT,
    age_psns_att_edu_inst_20_24_f    TEXT,
    age_psns_att_edu_inst_20_24_p    TEXT,
    age_psns_att_edu_inst_25_ov_m    TEXT,
    age_psns_att_edu_inst_25_ov_f    TEXT,
    age_psns_att_edu_inst_25_ov_p    TEXT,
    high_yr_schl_comp_yr_12_eq_m     TEXT,
    high_yr_schl_comp_yr_12_eq_f     TEXT,
    high_yr_schl_comp_yr_12_eq_p     TEXT,
    high_yr_schl_comp_yr_11_eq_m     TEXT,
    high_yr_schl_comp_yr_11_eq_f     TEXT,
    high_yr_schl_comp_yr_11_eq_p     TEXT,
    high_yr_schl_comp_yr_10_eq_m     TEXT,
    high_yr_schl_comp_yr_10_eq_f     TEXT,
    high_yr_schl_comp_yr_10_eq_p     TEXT,
    high_yr_schl_comp_yr_9_eq_m      TEXT,
    high_yr_schl_comp_yr_9_eq_f      TEXT,
    high_yr_schl_comp_yr_9_eq_p      TEXT,
    high_yr_schl_comp_yr_8_belw_m    TEXT,
    high_yr_schl_comp_yr_8_belw_f    TEXT,
    high_yr_schl_comp_yr_8_belw_p    TEXT,
    high_yr_schl_comp_d_n_g_sch_m    TEXT,
    high_yr_schl_comp_d_n_g_sch_f    TEXT,
    high_yr_schl_comp_d_n_g_sch_p    TEXT,
    count_psns_occ_priv_dwgs_m       TEXT,
    count_psns_occ_priv_dwgs_f       TEXT,
    count_psns_occ_priv_dwgs_p       TEXT,
    count_persons_other_dwgs_m       TEXT,
    count_persons_other_dwgs_f       TEXT,
    count_persons_other_dwgs_p       TEXT,
    _source_file                     TEXT        NOT NULL,                -- lineage: file the row came from
    _loaded_at                       TIMESTAMPTZ NOT NULL DEFAULT now()   -- lineage: load time
);

-- 2016 Census G02, Selected Medians and Averages, NSW LGAs
CREATE TABLE IF NOT EXISTS bronze.raw_census_g02 (
    lga_code_2016                    TEXT,
    median_age_persons               TEXT,
    median_mortgage_repay_monthly    TEXT,
    median_tot_prsnl_inc_weekly      TEXT,
    median_rent_weekly               TEXT,
    median_tot_fam_inc_weekly        TEXT,
    average_num_psns_per_bedroom     TEXT,
    median_tot_hhd_inc_weekly        TEXT,
    average_household_size           TEXT,
    _source_file                     TEXT        NOT NULL,                -- lineage: file the row came from
    _loaded_at                       TIMESTAMPTZ NOT NULL DEFAULT now()   -- lineage: load time
);

-- LGA code to LGA name
CREATE TABLE IF NOT EXISTS bronze.raw_lga_code (
    lga_code                         TEXT,
    lga_name                         TEXT,
    _source_file                     TEXT        NOT NULL,                -- lineage: file the row came from
    _loaded_at                       TIMESTAMPTZ NOT NULL DEFAULT now()   -- lineage: load time
);

-- Suburb to LGA name (the file has a byte-order mark and 25 empty trailing columns; only these 2 are real)
CREATE TABLE IF NOT EXISTS bronze.raw_lga_suburb (
    lga_name                         TEXT,
    suburb_name                      TEXT,
    _source_file                     TEXT        NOT NULL,                -- lineage: file the row came from
    _loaded_at                       TIMESTAMPTZ NOT NULL DEFAULT now()   -- lineage: load time
);

-- 3. Loader role for the Airflow DAG -------------------------------------
-- Group role with the minimum rights for an IDEMpotent load:
-- INSERT new rows, DELETE a file's rows before reloading it, TRUNCATE the
-- small reference tables, SELECT for row-count checks.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bronze_loader') THEN
        CREATE ROLE bronze_loader NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA bronze TO bronze_loader;
GRANT SELECT, INSERT, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA bronze TO bronze_loader;

-- Add the Composer service account's IAM database user to the group.
-- Looked up by pattern so this script contains no project identifier.
DO $$
DECLARE loader TEXT;
BEGIN
    SELECT rolname INTO loader FROM pg_roles WHERE rolname LIKE 'composer-runner@%.iam';
    IF loader IS NULL THEN
        RAISE EXCEPTION '[ERROR] - IAM database user composer-runner@<project>.iam not found: please, create it first';
    END IF;
    EXECUTE format('GRANT bronze_loader TO %I', loader);
END $$;

-- 4. Checks ---------------------------------------------------------------
SELECT table_name,
       (SELECT count(1) FROM information_schema.columns c
         WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name) AS n_columns
FROM information_schema.tables t
WHERE table_schema = 'bronze'
ORDER BY table_name;

-- Before the first DAG run (the stakeholder's advice: truncate all tables first):
-- TRUNCATE bronze.raw_listings, bronze.raw_census_g01, bronze.raw_census_g02,
--          bronze.raw_lga_code, bronze.raw_lga_suburb;
