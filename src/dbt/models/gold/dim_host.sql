/* dim_host: host dimension with SCD2 versions.
   Grain: one row per host version (<host_sk> = <dbt_scd_id>).
   <valid_to> is null for the current version; join facts with
   <listing_month> >= <valid_from> and (<valid_to> is null or <listing_month> < <valid_to>). */
select
    dbt_scd_id                  as host_sk,
    host_id,
    host_name,
    host_since,
    host_is_superhost,
    host_neighbourhood,
    host_neighbourhood_lga,
    dbt_valid_from::date        as valid_from,
    dbt_valid_to::date          as valid_to,
    dbt_valid_to is null        as is_current
from {{ ref('snap_host') }}
