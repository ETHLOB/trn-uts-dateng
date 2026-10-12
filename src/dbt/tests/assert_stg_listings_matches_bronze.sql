-- Singular test: rows per source file must be identical in Bronze and stg_listings.
-- Returns the files where the counts differ (test passes when no rows are returned).
with bronze as (
    select _source_file as source_file, count(1) as n
    from {{ source('bronze', 'raw_listings') }}
    group by 1
),

silver as (
    select source_file, count(1) as n
    from {{ ref('stg_listings') }}
    group by 1
)

select
    coalesce(b.source_file, s.source_file) as source_file,
    b.n as bronze_rows,
    s.n as silver_rows
from bronze as b
full join silver as s on s.source_file = b.source_file
where b.n is distinct from s.n
