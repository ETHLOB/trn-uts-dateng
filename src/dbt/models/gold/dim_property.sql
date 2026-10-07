/* dim_property: listing property dimension with SCD2 versions.
   Grain: one row per listing version (property_sk = dbt_scd_id).
   valid_to is null for the current version; join facts on the version valid at listing_month. */
select
    dbt_scd_id                  as property_sk,
    listing_id,
    property_type,
    room_type,
    accommodates,
    listing_neighbourhood,
    dbt_valid_from::date        as valid_from,
    dbt_valid_to::date          as valid_to,
    dbt_valid_to is null        as is_current
from {{ ref('snap_property') }}
