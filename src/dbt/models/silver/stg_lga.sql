/* stg_lga: LGA code to LGA name (canonical display name for the project).
   Grain: <lga_code>. <lga_name_key> (upper case) is the join key to suburb and listing names. */
select
    trim(lga_code)::int       as lga_code,
    trim(lga_name)            as lga_name,
    upper(trim(lga_name))     as lga_name_key
from {{ source('bronze', 'raw_lga_code') }}
