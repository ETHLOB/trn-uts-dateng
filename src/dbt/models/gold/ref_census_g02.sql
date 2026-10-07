/* ref_census_g02: 2016 Census G02 reference data by LGA. Grain: lga_code. Passed through from Silver. */
select * from {{ ref('stg_census_g02') }}
