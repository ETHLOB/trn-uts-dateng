/* dim_suburb: suburb dimension with its LGA. Grain: suburb_key (upper case suburb name). */
select suburb_key, suburb_name, lga_code, lga_name
from {{ ref('stg_suburb') }}
