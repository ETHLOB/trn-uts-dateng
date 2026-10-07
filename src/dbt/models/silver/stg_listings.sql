/* stg_listings: typed and cleaned Airbnb listings, all loaded months.
   Grain: listing_id + listing_month (one row per listing per monthly file).
   Decisions:
   - listing_month comes from the file name (MM_YYYY.csv), not scraped_date: 07_2020.csv has
     scrapes dated 2020-09-05, so scraped_date is not a reliable month.
   - host_since is d/m/yyyy; empty strings become null.
   - price 0 or empty becomes null (a zero price is a data error).
   - host_is_superhost / has_availability 't'/'f' become boolean; empty becomes null.
   - Categories (property_type etc.) are kept as Airbnb wrote them. */
select
    nullif(trim(listing_id), '')::bigint                        as listing_id,
    nullif(trim(scrape_id), '')::bigint                         as scrape_id,
    nullif(trim(scraped_date), '')::date                        as scraped_date,
    to_date(left(_source_file, 7), 'MM_YYYY')                   as listing_month,
    nullif(trim(host_id), '')::bigint                           as host_id,
    nullif(trim(host_name), '')                                 as host_name,
    to_date(nullif(trim(host_since), ''), 'DD/MM/YYYY')         as host_since,
    case trim(host_is_superhost) when 't' then true when 'f' then false end as host_is_superhost,
    nullif(trim(host_neighbourhood), '')                        as host_neighbourhood,
    nullif(trim(listing_neighbourhood), '')                     as listing_neighbourhood,
    nullif(trim(property_type), '')                             as property_type,
    nullif(trim(room_type), '')                                 as room_type,
    nullif(trim(accommodates), '')::int                         as accommodates,
    nullif(nullif(trim(price), '')::numeric(10, 2), 0)          as price,
    case trim(has_availability) when 't' then true when 'f' then false end as has_availability,
    nullif(trim(availability_30), '')::int                      as availability_30,
    nullif(trim(number_of_reviews), '')::int                    as number_of_reviews,
    nullif(trim(review_scores_rating), '')::numeric             as review_scores_rating,
    nullif(trim(review_scores_accuracy), '')::numeric           as review_scores_accuracy,
    nullif(trim(review_scores_cleanliness), '')::numeric        as review_scores_cleanliness,
    nullif(trim(review_scores_checkin), '')::numeric            as review_scores_checkin,
    nullif(trim(review_scores_communication), '')::numeric      as review_scores_communication,
    nullif(trim(review_scores_value), '')::numeric              as review_scores_value,
    _source_file                                                as source_file,
    _loaded_at                                                  as loaded_at
from {{ source('bronze', 'raw_listings') }}
