-- dbt model: gold.mart_stock_screener
-- Analyst-ready mart: latest fundamentals + technicals + quality scores
-- This is the table Power BI dashboards query directly

{{ config(
    materialized='table',
    cluster_by=["sector", "market_cap_category"],
    labels={
        "layer": "gold",
        "team": "research",
        "refresh": "daily"
    }
) }}

with latest_fundamentals as (
    -- One row per symbol — most recent scrape only
    select *
    from {{ ref('stg_trendlyne_fundamentals') }}
    qualify row_number() over (
        partition by symbol
        order by scraped_at desc
    ) = 1
),

latest_technicals as (
    select *
    from {{ ref('stg_trendlyne_technicals') }}
    qualify row_number() over (
        partition by symbol
        order by scraped_at desc
    ) = 1
),

quality_scores as (
    select
        symbol,

        -- Composite quality score (0-100) for screening
        round(
            coalesce(
                case when roe >= 15 then 25 when roe >= 10 then 15 else 5 end, 0
            ) +
            coalesce(
                case when roce >= 15 then 25 when roce >= 10 then 15 else 5 end, 0
            ) +
            coalesce(
                case when debt_to_equity <= 0.5 then 25
                     when debt_to_equity <= 1.0 then 15
                     else 5 end, 0
            ) +
            coalesce(
                case when pat_margin_pct >= 15 then 25
                     when pat_margin_pct >= 10 then 15
                     else 5 end, 0
            )
        , 0) as quality_score,

        -- Valuation signal (simple — not investment advice)
        case
            when pe_ratio < 15 and roe > 15 then 'Potentially Undervalued'
            when pe_ratio > 40 then 'Premium Valuation'
            when pe_ratio between 15 and 25 then 'Fair Value'
            else 'Needs Analysis'
        end as valuation_signal

    from latest_fundamentals
),

final as (
    select
        -- Identity
        f.symbol,
        f.company_name,
        f.sector,
        f.market_cap_category,
        f.market_cap_cr,

        -- Price
        t.current_price,
        t.week_52_high,
        t.week_52_low,
        round(
            (t.current_price - t.week_52_low) /
            nullif(t.week_52_high - t.week_52_low, 0) * 100
        , 1) as pct_from_52w_low,

        -- Fundamentals
        f.pe_ratio,
        f.pb_ratio,
        f.roe,
        f.roce,
        f.debt_to_equity,
        f.revenue_cr,
        f.net_profit_cr,
        f.pat_margin_pct,
        f.eps,
        f.dividend_yield,

        -- Technicals
        t.rsi_14,
        t.sma_50,
        t.sma_200,
        case when t.current_price > t.sma_200 then 'Above' else 'Below' end as vs_200sma,

        -- Scores
        q.quality_score,
        q.valuation_signal,

        -- Data freshness
        f.scraped_date as fundamentals_date,
        t.scraped_date as technicals_date,

        -- Metadata
        current_timestamp() as mart_updated_at

    from latest_fundamentals f
    left join latest_technicals t using (symbol)
    left join quality_scores q using (symbol)
)

select * from final
