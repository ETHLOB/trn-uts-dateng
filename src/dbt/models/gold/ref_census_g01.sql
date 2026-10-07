/* ref_census_g01: 2016 Census G01 reference data by LGA. Grain: lga_code. Passed through from Silver. */
select * from {{ ref('stg_census_g01') }}
