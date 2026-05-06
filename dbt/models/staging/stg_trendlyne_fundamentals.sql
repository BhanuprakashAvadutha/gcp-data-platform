-- dbt model: silver_financial.stg_trendlyne_fundamentals
-- Staging layer: clean, type-cast, rename raw Trendlyne data
-- Partitioned by scraped_date for cost-efficient queries

{{ config(
    materialized='incremental',
    partition_by={
        "field": "scraped_date",
        "data_type": "date",
        "granularity": "day"
    },
    cluster_by=["sector", "symbol"],
    incremental_strategy='insert_overwrite',
    on_schema_change='append_new_columns'
) }}

with raw as (
    select
        symbol,
        company_name,
        sector,
        -- Safe cast all numerics — raw data has nulls and "N/A" strings
        safe_cast(market_cap_cr as float64)     as market_cap_cr,
        safe_cast(pe_ratio as float64)          as pe_ratio,
        safe_cast(pb_ratio as float64)          as pb_ratio,
        safe_cast(roe as float64)               as roe,
        safe_cast(roce as float64)              as roce,
        safe_cast(debt_to_equity as float64)    as debt_to_equity,
        safe_cast(revenue_cr as float64)        as revenue_cr,
        safe_cast(net_profit_cr as float64)     as net_profit_cr,
        safe_cast(eps as float64)               as eps,
        safe_cast(dividend_yield as float64)    as dividend_yield,
        date(scraped_at)                        as scraped_date,
        scraped_at

    from {{ source('bronze', 'trendlyne_fundamentals') }}

    {% if is_incremental() %}
        -- Only process new data on incremental runs
        where date(scraped_at) >= date_sub(current_date(), interval 2 day)
    {% endif %}
),

validated as (
    select
        *,
        -- Derived metrics
        case
            when revenue_cr > 0 and net_profit_cr is not null
            then round(net_profit_cr / revenue_cr * 100, 2)
            else null
        end                                     as pat_margin_pct,

        case
            when market_cap_cr > 100000 then 'Large Cap'
            when market_cap_cr > 20000  then 'Mid Cap'
            when market_cap_cr > 5000   then 'Small Cap'
            else 'Micro Cap'
        end                                     as market_cap_category,

        -- Data quality flags
        pe_ratio is null or pe_ratio <= 0       as is_pe_missing,
        roe is null                             as is_roe_missing,

    from raw
    where symbol is not null
      and symbol != ''
)

select * from validated
