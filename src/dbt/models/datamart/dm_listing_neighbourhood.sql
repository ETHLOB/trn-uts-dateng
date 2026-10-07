/* dm_listing_neighbourhood: monthly metrics per listing_neighbourhood.
   Grain: listing_neighbourhood + listing_month. View on fct_listings joined to the dimension
   versions valid at listing_month (SCD2: valid_from <= listing_month < valid_to, null valid_to = open),
   never on is_current. Price, rating, stays and revenue metrics use ACTIVE listings only.
   Percentage change compares with the previous CALENDAR month of the same group (null when absent). */
with base as (
    select
        f.listing_id,
        f.host_id,
        f.listing_month,
        f.price,
        f.review_scores_rating,
        f.is_active,
        f.number_of_stays,
        f.estimated_revenue,
        p.listing_neighbourhood,
        h.host_is_superhost
    from {{ ref('fct_listings') }} f
    join {{ ref('dim_property') }} p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    join {{ ref('dim_host') }} h
        on h.host_id = f.host_id
        and f.listing_month >= h.valid_from
        and (h.valid_to is null or f.listing_month < h.valid_to)
),

agg as (
    select
        listing_neighbourhood,
        listing_month,
        count(*)                                                        as total_listings,
        count(*) filter (where is_active = 1)                           as active_listings,
        count(*) filter (where is_active = 0)                           as inactive_listings,
        min(price) filter (where is_active = 1)                         as min_price,
        max(price) filter (where is_active = 1)                         as max_price,
        percentile_cont(0.5) within group (order by price)
            filter (where is_active = 1)                                as median_price,
        avg(price) filter (where is_active = 1)                         as avg_price,
        count(distinct host_id)                                         as distinct_hosts,
        count(distinct host_id) filter (where host_is_superhost)        as superhosts,
        avg(review_scores_rating) filter (where is_active = 1)          as avg_review_scores_rating,
        sum(number_of_stays) filter (where is_active = 1)               as total_stays,
        avg(estimated_revenue) filter (where is_active = 1)             as avg_estimated_revenue_per_active_listing
    from base
    group by listing_neighbourhood, listing_month
),

lagged as (
    select
        *,
        lag(listing_month)     over w as prev_month,
        lag(active_listings)   over w as prev_active_listings,
        lag(inactive_listings) over w as prev_inactive_listings
    from agg
    window w as (partition by listing_neighbourhood order by listing_month)
)

select
    listing_neighbourhood,
    listing_month,
    to_char(listing_month, 'MM/YYYY')                                                       as month_year,
    -- active listing rate = active listings / total listings * 100
    round(active_listings::numeric / total_listings * 100, 2)                               as active_listing_rate,
    min_price,
    max_price,
    round(median_price::numeric, 2)                                                         as median_price,
    round(avg_price, 2)                                                                     as avg_price,
    distinct_hosts,
    -- superhost rate = distinct superhosts / distinct hosts * 100 (null superhost counts as not superhost)
    round(superhosts::numeric / distinct_hosts * 100, 2)                                    as superhost_rate,
    round(avg_review_scores_rating, 2)                                                      as avg_review_scores_rating,
    -- percentage change = (final - original) / original * 100, original = previous calendar month
    case when prev_month = listing_month - interval '1 month'
         then round((active_listings - prev_active_listings)::numeric
                    / nullif(prev_active_listings, 0) * 100, 2) end                         as pct_change_active_listings,
    case when prev_month = listing_month - interval '1 month'
         then round((inactive_listings - prev_inactive_listings)::numeric
                    / nullif(prev_inactive_listings, 0) * 100, 2) end                       as pct_change_inactive_listings,
    -- number of stays (active listings) = sum(30 - availability_30)
    total_stays,
    -- estimated revenue per active listing = stays * price, averaged over active listings
    round(avg_estimated_revenue_per_active_listing, 2)                                      as avg_estimated_revenue_per_active_listing
from lagged
order by listing_neighbourhood, listing_month
