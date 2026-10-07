-- depends_on: {{ ref('dim_host') }}
-- depends_on: {{ ref('dim_property') }}
/* fct_listings: listing facts, IDs and metrics only.
   Grain: listing_id + listing_month.
   number_of_stays and estimated_revenue are only defined for active listings (null otherwise);
   the dimension attributes are joined in the datamart with SCD2 logic, not stored here. */
select
    listing_id,
    host_id,
    listing_month,
    price,
    availability_30,
    number_of_reviews,
    review_scores_rating,
    case when has_availability then 1 else 0 end                         as is_active,
    case when has_availability then 30 - availability_30 end             as number_of_stays,
    case when has_availability then (30 - availability_30) * price end   as estimated_revenue
from {{ ref('stg_listings') }}
