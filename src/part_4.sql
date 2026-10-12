-- Part 4: ad-hoc analysis
--
-- Assumptions shared by every query:
--  * Dimension joins obeys SCD2: the dimension version valid at the fact's month
--    (<f.listing_month> >= <d.valid_from> and (<d.valid_to> is null or <f.listing_month> < <d.valid_to>)),
--    never <is_current>.
--  * "Last 12 months" = the 12 loaded months, May 2020 to April 2021, written once per query in
--    the CTE <period>.
--  * Active listing = <is_active> = 1. Estimated revenue per active listing = avg(<estimated_revenue>)
--    over active listing-months (the same definition as the datamart); stays = 30 - <availability_30>.
--  * A listing's LGA = its <listing_neighbourhood> (an LGA name); join gold.dim_lga on <lga_name> to get
--    the <lga_code>, then the Census tables on <lga_code>.
--  * Rates and percentages are numeric, rounded to 2 decimals.
-- Each query is self-contained and can be run on its own in DBeaver.


-- Question a: What are the demographic differences (e.g., age group distribution, household size)
-- between the top 3 performing and lowest 3 performing LGAs based on estimated revenue per active
-- listing over the last 12 months?
-- Assumptions: only LGAs that match a Census LGA code are ranked; LGAs without active listings are
-- ignored. Age shares are % of total persons (<tot_p_p>) built from the G01 "_p" (persons) columns.
-- Household size comes from G02 (<average_household_size>, <average_num_psns_per_bedroom>).
with period as (
    select date '2020-05-01' as start_month, date '2021-04-01' as end_month
),
lga_revenue as (
    select
        p.listing_neighbourhood as lga_name,
        round(avg(f.estimated_revenue) filter (where f.is_active = 1), 2) as revenue_per_active_listing
    from gold.fct_listings f
    cross join period pr
    join gold.dim_property p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    where f.listing_month between pr.start_month and pr.end_month
    group by p.listing_neighbourhood
),
ranked as (
    select
        l.lga_name,
        d.lga_code,
        l.revenue_per_active_listing,
        row_number() over (order by l.revenue_per_active_listing desc) as rank_top,
        row_number() over (order by l.revenue_per_active_listing asc)  as rank_bottom
    from lga_revenue l
    join gold.dim_lga d on d.lga_name = l.lga_name
    where l.revenue_per_active_listing is not null
)
select
    case when r.rank_top <= 3 then 'top 3' else 'bottom 3' end as "group",
    r.lga_name,
    r.revenue_per_active_listing,
    g2.median_age_persons,
    round((g1.age_0_4_yr_p + g1.age_5_14_yr_p)::numeric / g1.tot_p_p * 100, 2)   as pct_age_0_14,
    round((g1.age_15_19_yr_p + g1.age_20_24_yr_p)::numeric / g1.tot_p_p * 100, 2) as pct_age_15_24,
    round((g1.age_25_34_yr_p + g1.age_35_44_yr_p)::numeric / g1.tot_p_p * 100, 2) as pct_age_25_44,
    round((g1.age_45_54_yr_p + g1.age_55_64_yr_p)::numeric / g1.tot_p_p * 100, 2) as pct_age_45_64,
    round((g1.age_65_74_yr_p + g1.age_75_84_yr_p + g1.age_85ov_p)::numeric / g1.tot_p_p * 100, 2) as pct_age_65_plus,
    g2.average_household_size,
    g2.average_num_psns_per_bedroom,
    g2.median_tot_hhd_inc_weekly,
    g2.median_mortgage_repay_monthly
from ranked r
join gold.ref_census_g01 g1 on g1.lga_code = r.lga_code
join gold.ref_census_g02 g2 on g2.lga_code = r.lga_code
where r.rank_top <= 3 or r.rank_bottom <= 3
order by "group" desc, r.revenue_per_active_listing desc;
-- Compare the age shares, household size and income columns between the two groups to see how 
-- the best and worst LGAs differ.


-- Question b: Is there a correlation between the median age of a neighbourhood (from Census data)
-- and the revenue generated per active listing in that neighbourhood?
-- Assumptions: neighbourhood = LGA (<listing_neighbourhood>). Pearson correlation via corr(); LGAs
-- without a Census match or without active listings are dropped. Part 1 is the per-LGA table,
-- part 2 the single-row summary.
-- Part 1: per-LGA data points.
with period as (
    select date '2020-05-01' as start_month, date '2021-04-01' as end_month
),
lga_revenue as (
    select
        p.listing_neighbourhood as lga_name,
        round(avg(f.estimated_revenue) filter (where f.is_active = 1), 2) as revenue_per_active_listing
    from gold.fct_listings f
    cross join period pr
    join gold.dim_property p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    where f.listing_month between pr.start_month and pr.end_month
    group by p.listing_neighbourhood
)
select
    l.lga_name,
    g2.median_age_persons,
    l.revenue_per_active_listing
from lga_revenue l
join gold.dim_lga d on d.lga_name = l.lga_name
join gold.ref_census_g02 g2 on g2.lga_code = d.lga_code
where l.revenue_per_active_listing is not null
  and g2.median_age_persons is not null
order by g2.median_age_persons, l.lga_name;
-- How to read: one row per LGA, ready for a scatter plot (median age on x, revenue on y).

-- Part 2: detecting correlation summary.
with period as (
    select date '2020-05-01' as start_month, date '2021-04-01' as end_month
),
lga_revenue as (
    select
        p.listing_neighbourhood as lga_name,
        avg(f.estimated_revenue) filter (where f.is_active = 1) as revenue_per_active_listing
    from gold.fct_listings f
    cross join period pr
    join gold.dim_property p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    where f.listing_month between pr.start_month and pr.end_month
    group by p.listing_neighbourhood
),
points as (
    select l.lga_name, g2.median_age_persons, l.revenue_per_active_listing
    from lga_revenue l
    join gold.dim_lga d on d.lga_name = l.lga_name
    join gold.ref_census_g02 g2 on g2.lga_code = d.lga_code
    where l.revenue_per_active_listing is not null
      and g2.median_age_persons is not null
)
select
    count(1)                                                                        as n_lgas,
    round(corr(median_age_persons, revenue_per_active_listing)::numeric, 4)         as pearson_corr,
    round(regr_slope(revenue_per_active_listing, median_age_persons)::numeric, 2)   as revenue_change_per_year_of_age,
    round(regr_r2(revenue_per_active_listing, median_age_persons)::numeric, 4)      as r_squared
from points
order by n_lgas;
-- How to read: <pearson_corr> near 0 means no linear relationship; negative means older LGAs earn
-- less per active listing. <revenue_change_per_year_of_age> is the regression slope (dollars per year of median age).


-- Question c: What will be the best type of listing (property type, room type and accommodates for)
-- for the top 5 "<listing_neighbourhood>" (in terms of average estimated revenue per active listing)
-- to have the highest number of stays?
-- Assumptions: "best" = the (<property_type>, <room_type>, <accommodates>) combination with the highest
-- average stays per active listing-month. Only combinations with at least 5 distinct listings and
-- 12 active listing-months are considered, so a single property that is always unavailable (stays
-- = 30 - <availability_30> also counts days blocked by the host) cannot decide the answer. Ties are
-- broken by total stays.
with period as (
    select date '2020-05-01' as start_month, date '2021-04-01' as end_month
),
base as (
    select
        f.listing_id,
        p.listing_neighbourhood,
        p.property_type,
        p.room_type,
        p.accommodates,
        f.is_active,
        f.number_of_stays,
        f.estimated_revenue
    from gold.fct_listings f
    cross join period pr
    join gold.dim_property p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    where f.listing_month between pr.start_month and pr.end_month
),
top_lgas as (
    select listing_neighbourhood, round(avg(estimated_revenue) filter (where is_active = 1), 2) as revenue_per_active_listing
    from base
    group by listing_neighbourhood
    having avg(estimated_revenue) filter (where is_active = 1) is not null
    order by revenue_per_active_listing desc
    limit 5
),
combos as (
    select
        b.listing_neighbourhood,
        b.property_type,
        b.room_type,
        b.accommodates,
        count(distinct b.listing_id)          as n_listings,
        count(1)                              as active_listing_months,
        sum(b.number_of_stays)                as total_stays,
        round(avg(b.number_of_stays), 2)      as avg_stays_per_active_listing_month
    from base b
    join top_lgas t on t.listing_neighbourhood = b.listing_neighbourhood
    where b.is_active = 1
    group by b.listing_neighbourhood, b.property_type, b.room_type, b.accommodates
    having count(distinct b.listing_id) >= 5 and count(1) >= 12
),
ranked as (
    select
        *,
        rank() over (
            partition by listing_neighbourhood
            order by avg_stays_per_active_listing_month desc, total_stays desc
        ) as rnk
    from combos
)
select
    r.listing_neighbourhood,
    t.revenue_per_active_listing,
    r.property_type,
    r.room_type,
    r.accommodates,
    r.avg_stays_per_active_listing_month,
    r.total_stays,
    r.n_listings,
    r.active_listing_months
from ranked r
join top_lgas t on t.listing_neighbourhood = r.listing_neighbourhood
where r.rnk = 1
order by t.revenue_per_active_listing desc, r.listing_neighbourhood;
-- How to read: one row per top-5 LGA (best average stays), with the winning listing type.


-- Question d: For hosts with multiple listings are their properties concentrated within the same
-- LGA, or are they distributed across different LGAs?
-- Assumptions: multiple listings = more than one distinct <listing_id> over the period. Each listing
-- counts once, in its latest LGA in the period (SCD2 version valid that month); otherwise a listing
-- whose neighbourhood label changed would make its host look spread across LGAs.
-- Part 1: distribution of hosts by number of distinct LGAs.
with period as (
    select date '2020-05-01' as start_month, date '2021-04-01' as end_month
),
listing_lga as (
    -- one row per host and listing: the listing's LGA in its latest month in the period
    select distinct on (f.host_id, f.listing_id)
        f.host_id,
        f.listing_id,
        p.listing_neighbourhood as lga_name
    from gold.fct_listings f
    cross join period pr
    join gold.dim_property p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    where f.listing_month between pr.start_month and pr.end_month
    order by f.host_id, f.listing_id, f.listing_month desc
),
host_lgas as (
    select
        host_id,
        count(1)                as n_listings,
        count(distinct lga_name) as n_lgas
    from listing_lga
    group by host_id
    having count(1) > 1
)
select
    n_lgas as distinct_lgas,
    count(1) as hosts,
    round(count(1) * 100.0 / sum(count(1)) over (), 2) as pct_of_hosts
from host_lgas
group by n_lgas
order by n_lgas;
-- How to read: row "1" are hosts whose listings all sit in one LGA; higher rows are spread out.

-- Part 2: one-row summary, concentrated (1 LGA) versus distributed (2+ LGAs).
with period as (
    select date '2020-05-01' as start_month, date '2021-04-01' as end_month
),
listing_lga as (
    -- one row per host and listing: the listing's LGA in its latest month in the period
    select distinct on (f.host_id, f.listing_id)
        f.host_id,
        f.listing_id,
        p.listing_neighbourhood as lga_name
    from gold.fct_listings f
    cross join period pr
    join gold.dim_property p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    where f.listing_month between pr.start_month and pr.end_month
    order by f.host_id, f.listing_id, f.listing_month desc
),
host_lgas as (
    select
        host_id,
        count(1)                as n_listings,
        count(distinct lga_name) as n_lgas
    from listing_lga
    group by host_id
    having count(1) > 1
)
select
    count(1)                                        as multi_listing_hosts,
    count(1) filter (where n_lgas = 1)              as hosts_in_one_lga,
    round(count(1) filter (where n_lgas = 1) * 100.0 / count(1), 2) as pct_in_one_lga,
    count(1) filter (where n_lgas >= 2)             as hosts_in_2plus_lgas,
    round(count(1) filter (where n_lgas >= 2) * 100.0 / count(1), 2) as pct_in_2plus_lgas
from host_lgas
order by multi_listing_hosts;
-- How to read: compare pct_in_one_lga with pct_in_2plus_lgas; the larger share is the typical pattern.


-- Question e: For hosts with a single Airbnb listing does the estimated revenue over the last 12
-- months cover the annualised median mortgage repayment in the corresponding LGA? Which LGA has
-- the highest percentage of hosts that can cover it?
-- Assumptions: single-listing host = exactly one distinct <listing_id> over the period. Revenue over
-- the period = sum(<estimated_revenue>) with inactive months counting as 0. The corresponding LGA is
-- the listing's LGA in its latest month in the period. Annualised mortgage = <median_mortgage_repay_monthly> * 12.
-- "Covers" means revenue >= annualised mortgage. LGAs without Census data are dropped.
-- Part 1: per LGA.
with period as (
    select date '2020-05-01' as start_month, date '2021-04-01' as end_month
),
base as (
    select
        f.host_id,
        f.listing_id,
        f.listing_month,
        coalesce(f.estimated_revenue, 0) as revenue,
        p.listing_neighbourhood
    from gold.fct_listings f
    cross join period pr
    join gold.dim_property p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    where f.listing_month between pr.start_month and pr.end_month
),
single_hosts as (
    select host_id
    from base
    group by host_id
    having count(distinct listing_id) = 1
),
host_lga as (
    select
        b.host_id,
        sum(b.revenue) over (partition by b.host_id) as revenue_12m,
        row_number() over (partition by b.host_id order by b.listing_month desc) as rn,
        b.listing_neighbourhood
    from base b
    join single_hosts s on s.host_id = b.host_id
),
host_result as (
    select
        h.host_id,
        d.lga_name,
        h.revenue_12m,
        g2.median_mortgage_repay_monthly * 12 as annual_mortgage
    from host_lga h
    join gold.dim_lga d on d.lga_name = h.listing_neighbourhood
    join gold.ref_census_g02 g2 on g2.lga_code = d.lga_code
    where h.rn = 1
      and g2.median_mortgage_repay_monthly is not null
)
select
    lga_name,
    max(annual_mortgage)                                                  as annual_median_mortgage,
    count(1)                                                              as single_listing_hosts,
    count(1) filter (where revenue_12m >= annual_mortgage)                as hosts_covering,
    round(count(1) filter (where revenue_12m >= annual_mortgage) * 100.0 / count(1), 2) as pct_hosts_covering
from host_result
group by lga_name
order by pct_hosts_covering desc, single_listing_hosts desc, lga_name;
-- How to read: the first row is the LGA with the highest share of single-listing hosts whose
-- revenue covers the annual mortgage (ties broken by number of hosts).

-- Part 2: overall percentage across all LGAs.
with period as (
    select date '2020-05-01' as start_month, date '2021-04-01' as end_month
),
base as (
    select
        f.host_id,
        f.listing_id,
        f.listing_month,
        coalesce(f.estimated_revenue, 0) as revenue,
        p.listing_neighbourhood
    from gold.fct_listings f
    cross join period pr
    join gold.dim_property p
        on p.listing_id = f.listing_id
        and f.listing_month >= p.valid_from
        and (p.valid_to is null or f.listing_month < p.valid_to)
    where f.listing_month between pr.start_month and pr.end_month
),
single_hosts as (
    select host_id
    from base
    group by host_id
    having count(distinct listing_id) = 1
),
host_lga as (
    select
        b.host_id,
        sum(b.revenue) over (partition by b.host_id) as revenue_12m,
        row_number() over (partition by b.host_id order by b.listing_month desc) as rn,
        b.listing_neighbourhood
    from base b
    join single_hosts s on s.host_id = b.host_id
),
host_result as (
    select
        h.host_id,
        h.revenue_12m,
        g2.median_mortgage_repay_monthly * 12 as annual_mortgage
    from host_lga h
    join gold.dim_lga d on d.lga_name = h.listing_neighbourhood
    join gold.ref_census_g02 g2 on g2.lga_code = d.lga_code
    where h.rn = 1
      and g2.median_mortgage_repay_monthly is not null
)
select
    count(1)                                                              as single_listing_hosts,
    count(1) filter (where revenue_12m >= annual_mortgage)                as hosts_covering,
    round(count(1) filter (where revenue_12m >= annual_mortgage) * 100.0 / count(1), 2) as pct_hosts_covering
from host_result
order by single_listing_hosts;
-- How to read: share of all single-listing hosts whose 12-month revenue covers the annualised median mortgage.
