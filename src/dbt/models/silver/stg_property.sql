/* stg_property: one row per listing with its LATEST attribute set, ready for the SCD2 snapshot.
   Grain: listing_id.
   updated_at (snapshot timestamp), gaps-and-islands:
   1. one row per listing per month;
   2. flag a change when (property_type, room_type, accommodates, listing_neighbourhood) differs
      from the previous month's (is distinct from);
   3. running sum of the flags = run id; the last run is the current attribute set;
   4. updated_at = first month of that last run.
   Why: the timestamp strategy opens a new version only when updated_at increases, so an
   unchanged listing keeps one version, a change (e.g. the Jul/Aug 2020 property_type
   relabelling) is dated to the month it was first observed, and scraped_date is not usable
   (non-monotonic). Categories are not harmonised: the relabelling is real history. */
with monthly as (
    select distinct
        listing_id, listing_month, property_type, room_type, accommodates, listing_neighbourhood
    from {{ ref('stg_listings') }}
    where listing_id is not null
),

flagged as (
    select
        *,
        case
            when (property_type, room_type, accommodates, listing_neighbourhood) is distinct from
                 lag((property_type, room_type, accommodates, listing_neighbourhood))
                     over (partition by listing_id order by listing_month)
            then 1 else 0
        end as is_change
    from monthly
),

runs as (
    select
        *,
        sum(is_change) over (partition by listing_id order by listing_month) as run_id
    from flagged
),

latest as (
    select
        listing_id, property_type, room_type, accommodates, listing_neighbourhood,
        min(listing_month) over (partition by listing_id, run_id)                as run_start,
        row_number() over (partition by listing_id order by listing_month desc)  as rn
    from runs
)

select
    listing_id,
    property_type,
    room_type,
    accommodates,
    listing_neighbourhood,
    run_start::timestamp as updated_at
from latest
where rn = 1
