/* dm_host_neighbourhood: monthly metrics per <host_neighbourhood_lga> (host's suburb mapped to its LGA).
   Grain: <host_neighbourhood_lga> + <listing_month>. Hosts without a mappable LGA (empty or 'Overseas'
   neighbourhood) form one group with a null <host_neighbourhood_lga>, kept so no host is dropped.
   Hosts and listing dimensions are joined with SCD2 logic (<valid_from> <= <listing_month> < <valid_to>).
   A host with listings in a month counts once per group; revenue uses ACTIVE listings only. */
with base as (
    select
        f.host_id,
        f.listing_month,
        f.is_active,
        f.estimated_revenue,
        h.host_neighbourhood_lga
    from {{ ref('fct_listings') }} f
    join {{ ref('dim_host') }} h
        on h.host_id = f.host_id
        and f.listing_month >= h.valid_from
        and (h.valid_to is null or f.listing_month < h.valid_to)
),

agg as (
    select
        host_neighbourhood_lga,
        listing_month,
        count(distinct host_id)                                         as distinct_hosts,
        avg(estimated_revenue) filter (where is_active = 1)             as avg_estimated_revenue_per_active_listing,
        sum(estimated_revenue) filter (where is_active = 1)             as total_estimated_revenue
    from base
    group by host_neighbourhood_lga, listing_month
)

select
    host_neighbourhood_lga,
    listing_month,
    to_char(listing_month, 'MM/YYYY')                                   as month_year,
    distinct_hosts,
    -- estimated revenue per active listing = stays * <price>, averaged over active listings
    round(avg_estimated_revenue_per_active_listing, 2)                  as avg_estimated_revenue_per_active_listing,
    -- estimated revenue per host = total estimated revenue of active listings / distinct hosts
    round(total_estimated_revenue / distinct_hosts, 2)                  as estimated_revenue_per_host
from agg
order by host_neighbourhood_lga, listing_month
