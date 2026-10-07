/* stg_suburb: suburb to LGA mapping.
   Grain: suburb_key (upper case suburb). The file only has the LGA name (upper case), so the
   LGA code and canonical name come from stg_lga. A suburb whose LGA name is not in stg_lga
   keeps lga_code null (visible, not dropped). */
with src as (
    select
        nullif(trim(suburb_name), '') as suburb_name,
        upper(trim(lga_name))         as lga_name_key
    from {{ source('bronze', 'raw_lga_suburb') }}
    where nullif(trim(suburb_name), '') is not null
)

select
    src.suburb_name,
    upper(src.suburb_name) as suburb_key,
    lga.lga_code,
    lga.lga_name
from src
left join {{ ref('stg_lga') }} as lga
    on lga.lga_name_key = src.lga_name_key
