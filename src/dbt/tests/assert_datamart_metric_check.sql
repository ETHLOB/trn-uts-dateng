-- Independent recomputation of active_listing_rate and avg estimated revenue per active listing
-- for dm_listing_neighbourhood from fct_listings + dim_property (SCD2 join). Returns rows that differ by > 0.01.
with recomputed as (
    select
        p.listing_neighbourhood,
        f.listing_month,
        100.0 * sum(f.is_active) / count(*)                                     as rate,
        sum(f.estimated_revenue) filter (where f.is_active = 1)
            / nullif(count(f.estimated_revenue) filter (where f.is_active = 1), 0) as avg_rev
    from {{ ref('fct_listings') }} f
    join {{ ref('dim_property') }} p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    group by 1, 2
)
select r.listing_neighbourhood, r.listing_month
from recomputed r
full join {{ ref('dm_listing_neighbourhood') }} d
    using (listing_neighbourhood, listing_month)
where abs(coalesce(r.rate, -1) - coalesce(d.active_listing_rate, -1)) > 0.01
   or abs(coalesce(r.avg_rev, -1) - coalesce(d.avg_estimated_revenue_per_active_listing, -1)) > 0.01
