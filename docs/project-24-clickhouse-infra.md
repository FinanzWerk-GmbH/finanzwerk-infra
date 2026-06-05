# Project 24: ClickHouse Infrastructure

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![ClickHouse](https://img.shields.io/badge/ClickHouse-FFCC01?logo=clickhouse&logoColor=black)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)

> ClickHouse deployed to Minikube for OLAP (analytical) queries. Data syncs nightly from PostgreSQL. For aggregation queries over millions of rows, it's 100x faster than PostgreSQL.

PostgreSQL is great for the operational stuff — writes, point lookups, joins with foreign key checks. But it's a row-oriented database, which means scanning all 10M incidents to count by severity is slow. ClickHouse stores data by column instead of by row, which makes full-table aggregations extremely fast.

## Deployment topology

```mermaid
graph TB
    subgraph tf["Terraform"]
        CH_TF[clickhouse.tf\nHelm release\n+ user provisioning]
    end

    subgraph k8s["Minikube — namespace: clickhouse"]
        CH[ClickHouse server\n4 CPU · 8Gi\ncolumnar storage]
        MV_CH["Materialized View:\ncht_ict_incidents\ncht_vendor_risk"]
    end

    subgraph pg["PostgreSQL (source)"]
        PG[(compliance.ict_incidents\ncompliance.vendors)]
    end

    subgraph consumers["Query consumers"]
        SUPERSET[Apache Superset\ndashboards]
        BI[External BI tools\nJDBC/HTTP]
    end

    tf --> k8s
    PG -->|batch sync\nnightly via Airflow| MV_CH
    CH --> SUPERSET
    CH --> BI
```

## ClickHouse vs PostgreSQL — when to use which

| Query type | PostgreSQL | ClickHouse |
|-----------|-----------|-----------|
| Write single incident | ✓ fast | ✗ not designed for it |
| Lookup by `incident_id` | ✓ index scan | ✗ full column scan |
| COUNT(*) over 10M rows | ~8 seconds | ~0.02 seconds |
| GROUP BY quarter + severity | ~3 seconds | ~0.01 seconds |

The nightly sync means ClickHouse is always a few hours behind PostgreSQL. That's fine for reporting — nobody needs the compliance dashboard to update in real-time.

## Code

| Path | Description |
|------|-------------|
| [`local/clickhouse.tf`](../local/clickhouse.tf) | ClickHouse Helm + user config |
| [`local/superset.tf`](../local/superset.tf) | Apache Superset Helm (BI frontend) |
