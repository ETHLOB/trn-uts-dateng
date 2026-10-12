/* dim_lga: LGA dimension. Grain: <lga_code>. */
select lga_code, lga_name
from {{ ref('stg_lga') }}
