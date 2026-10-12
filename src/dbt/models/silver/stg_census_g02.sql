/* stg_census_g02: 2016 Census G02 (selected medians and averages), one row per LGA.
   Grain: <lga_code>. Medians are integers, averages numeric. */
select
    substr(trim(lga_code_2016), 4)::int                         as lga_code,
    nullif(trim(median_age_persons), '')::int                   as median_age_persons,
    nullif(trim(median_mortgage_repay_monthly), '')::int        as median_mortgage_repay_monthly,
    nullif(trim(median_tot_prsnl_inc_weekly), '')::int          as median_tot_prsnl_inc_weekly,
    nullif(trim(median_rent_weekly), '')::int                   as median_rent_weekly,
    nullif(trim(median_tot_fam_inc_weekly), '')::int            as median_tot_fam_inc_weekly,
    nullif(trim(average_num_psns_per_bedroom), '')::numeric     as average_num_psns_per_bedroom,
    nullif(trim(median_tot_hhd_inc_weekly), '')::int            as median_tot_hhd_inc_weekly,
    nullif(trim(average_household_size), '')::numeric           as average_household_size
from {{ source('bronze', 'raw_census_g02') }}
