# gcp-data-platform

Full GCP data platform for Indian financial market data. Medallion architecture (Bronze → Silver → Gold) powering daily research at Sampadha Research Financial Limited (SEBI-registered).

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        GCP Data Platform                             │
│                                                                      │
│  SOURCES                                                             │
│  Trendlyne API · NSE · RSS Feeds · Google Forms                      │
│         │                                                            │
│  BRONZE LAYER (GCS)                                                  │
│  gs://sampadha-bronze/                                               │
│  ├── trendlyne/{date}/fundamentals.json   (raw, never modified)      │
│  ├── trendlyne/{date}/technicals.json                                │
│  └── news/{date}/raw_sources.json                                    │
│         │ Cloud Functions trigger on new GCS object                  │
│  SILVER LAYER (BigQuery)                                             │
│  silver_financial.*                                                  │
│  ├── stg_trendlyne_fundamentals   (partitioned by date, clustered)   │
│  ├── stg_trendlyne_technicals                                        │
│  └── stg_news_articles                                               │
│         │ dbt runs nightly                                           │
│  GOLD LAYER (BigQuery)                                               │
│  gold.*                                                              │
│  ├── mart_stock_screener          (analyst-ready, Power BI source)   │
│  ├── mart_sector_summary                                             │
│  └── mart_daily_digest            (drives the news email)            │
│         │                                                            │
│  CONSUMPTION                                                         │
│  Power BI Dashboard · Research Reports · Gmail Digest                │
└──────────────────────────────────────────────────────────────────────┘

ORCHESTRATION: Cloud Scheduler → Cloud Functions
TRANSFORMATION: dbt Core (open source)
IaC: Terraform (GCS + BigQuery + Cloud Scheduler + IAM)
```

## Key Design Decisions

### Why partition by date in Silver?
Each daily scrape is ~50 stocks × 2 tables. Without partitioning, every Power BI query scans the full table. With `PARTITION BY scraped_date`, queries for "today's data" scan 1 partition — cost drops 95%.

### Why cluster by sector + symbol?
Analysts filter by sector constantly ("show me all IT stocks"). Clustering makes these queries 3–5x faster at no extra cost.

### Why dbt for Gold, not raw SQL?
- Tests: `test_no_duplicate_symbols_in_screener.sql` runs on every deploy
- Documentation: auto-generated data dictionary from model descriptions  
- Lineage: dbt DAG shows exactly which tables feed which marts

### Bronze immutability
Bronze data is never modified after write. If Silver logic breaks, we reprocess from Bronze. This is the SEBI compliance guarantee — we can always reconstruct what data existed on any given date.

## dbt Models

| Model | Layer | Materialization | Description |
|-------|-------|----------------|-------------|
| `stg_trendlyne_fundamentals` | Silver | Incremental | Clean, typed fundamentals |
| `stg_trendlyne_technicals` | Silver | Incremental | Clean technicals |
| `mart_stock_screener` | Gold | Table | Analyst-ready screener |
| `mart_sector_summary` | Gold | Table | Sector-level rollups |

## Infrastructure (Terraform)

```bash
cd terraform
terraform init
terraform plan -var="project_id=your-project"
terraform apply
```

Provisions:
- GCS buckets (bronze, silver staging area)
- BigQuery datasets (silver_financial, gold)
- Cloud Scheduler jobs
- IAM service accounts with least-privilege roles

## Running dbt

```bash
pip install dbt-bigquery
dbt deps
dbt run --select staging   # Silver layer
dbt run --select marts     # Gold layer
dbt test                   # Data quality checks
dbt docs generate && dbt docs serve
```

## Power BI Connection

Gold layer tables are the direct source for Power BI:
```
Server: bigquery.googleapis.com
Project: sampadha-research
Dataset: gold
Table: mart_stock_screener
```

DirectQuery mode — dashboard always shows fresh data from last pipeline run.
