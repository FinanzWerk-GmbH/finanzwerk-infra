# Project 30: Data Governance Infrastructure — DataHub and Marquez

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![DataHub](https://img.shields.io/badge/DataHub-00A8E0?logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)

> Two governance tools running on Minikube: DataHub for the data catalogue, Marquez for lineage tracking. Both deployed via Terraform so they come up automatically with the rest of the platform.

DataHub answers "what is this dataset and who owns it". Marquez answers "where did this data come from and what touched it". They're not competing tools — they do different things. DataHub is more for business users and data owners. Marquez is more for engineers debugging a broken pipeline.

## Platform topology

```mermaid
graph TB
    subgraph tf["Terraform modules"]
        DH_TF["datahub.tf\nHelm: datahub-helm"]
        MQ_TF["marquez.tf\nHelm: marquez"]
    end

    subgraph k8s["Minikube - namespace: governance"]
        subgraph datahub["DataHub"]
            DH_GMS["GMS - Metadata Service\n:8080"]
            DH_FE["DataHub Frontend\n:9002"]
            DH_ES[("Elasticsearch\nmetadata index")]
            DH_PG[("PostgreSQL\ndatahub schema")]
        end
        subgraph marquez_ns["Marquez"]
            MQ_API["Marquez API\n:5000"]
            MQ_UI["Marquez Web\n:3000"]
            MQ_PG[("PostgreSQL\nmarquez schema")]
        end
    end

    tf --> datahub & marquez_ns

    subgraph emitters["Metadata emitters"]
        REG["register_products.py\nDatahubRestEmitter"]
        OL["OpenLineage events\nDagster - Airflow - Spark"]
    end

    REG --> DH_GMS
    OL --> MQ_API
```

## Why run both

DataHub needs Elasticsearch under the hood, which makes it heavier to run locally. But it's the tool people actually use to browse and search the catalogue. Marquez is much lighter (just a REST API + Postgres) and handles the raw lineage data that OpenLineage emitters push to it.

In prod you'd probably hook DataHub up to Marquez as a lineage source too, but for local dev keeping them separate is fine.

## Code

| Path | Description |
|------|-------------|
| [`local/datahub.tf`](../local/datahub.tf) | DataHub Helm + Elasticsearch + Kafka |
| [`local/marquez.tf`](../local/marquez.tf) | Marquez Helm + PostgreSQL backend |
