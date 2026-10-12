-- Returns fact rows that do not match exactly one dim_host version and one dim_property version
-- at their <listing_month> (SCD2 validity window). Passes when empty.
select f.listing_id, f.listing_month
from {{ ref('fct_listings') }} as f
left join {{ ref('dim_host') }} as h
    on h.host_id = f.host_id
   and f.listing_month >= h.valid_from
   and (h.valid_to is null or f.listing_month < h.valid_to)
left join {{ ref('dim_property') }} as p
    on p.listing_id = f.listing_id
   and f.listing_month >= p.valid_from
   and (p.valid_to is null or f.listing_month < p.valid_to)
group by f.listing_id, f.listing_month
having count(distinct h.host_sk) <> 1 or count(distinct p.property_sk) <> 1
