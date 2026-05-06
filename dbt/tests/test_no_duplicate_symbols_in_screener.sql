-- dbt test: no symbol appears twice in the screener mart
-- If this fails, the qualify/row_number dedup logic broke

select
    symbol,
    count(*) as row_count
from {{ ref('mart_stock_screener') }}
group by symbol
having count(*) > 1
