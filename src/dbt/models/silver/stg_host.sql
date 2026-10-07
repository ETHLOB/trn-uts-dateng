/* stg_host: one row per host with its LATEST attribute set, ready for the SCD2 snapshot.
   Grain: host_id.
   updated_at (snapshot timestamp), gaps-and-islands:
   1. one row per host per month (distinct attribute tuples; a host has one tuple per month);
   2. flag a change when the tuple differs from the previous month's (is distinct from);
   3. running sum of the flags = run id; the last run is the host's current attribute set;
   4. updated_at = first month of that last run.
   Why: the timestamp strategy opens a new version only when updated_at increases, so an
   unchanged host keeps one version (not one per month), a change is dated to the month it
   was first observed, and the non-monotonic scraped_date is not needed.
   host_neighbourhood_lga: suburb name mapped to the canonical LGA name via stg_suburb;
   null when unmatched (e.g. 'Overseas' is not a suburb). */
with monthly as (
    select distinct
        host_id, listing_month, host_name, host_since, host_is_superhost, host_neighbourhood
    from {{ ref('stg_listings') }}
    where host_id is not null
),

flagged as (
    select
        *,
        case
            when (host_name, host_since, host_is_superhost, host_neighbourhood) is distinct from
                 lag((host_name, host_since, host_is_superhost, host_neighbourhood))
                     over (partition by host_id order by listing_month)
            then 1 else 0
        end as is_change
    from monthly
),

runs as (
    select
        *,
        sum(is_change) over (partition by host_id order by listing_month) as run_id
    from flagged
),

latest as (
    select
        host_id, host_name, host_since, host_is_superhost, host_neighbourhood,
        min(listing_month) over (partition by host_id, run_id)            as run_start,
        row_number() over (partition by host_id order by listing_month desc) as rn,
        run_id
    from runs
)

select
    l.host_id,
    l.host_name,
    l.host_since,
    l.host_is_superhost,
    l.host_neighbourhood,
    s.lga_name                    as host_neighbourhood_lga,
    l.run_start::timestamp        as updated_at
from latest as l
left join {{ ref('stg_suburb') }} as s
    on s.suburb_key = upper(trim(l.host_neighbourhood))
where l.rn = 1
