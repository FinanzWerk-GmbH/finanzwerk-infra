# finanzwerk-infra

> Terraform-managed infrastructure for the FinanzWerk data platform — local Minikube and AWS cloud targets.

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?logo=amazonaws&logoColor=white)

All infrastructure is defined as code. `local/` targets Minikube for development; `cloud/` targets AWS EKS. Every service in the stack — PostgreSQL, Airflow, Redpanda, ClickHouse, Dagster, DataHub — is provisioned here and nowhere else.

## Projects in this repo

| # | Project | Stack | Doc |
|---|---------|-------|-----|
| 1 | Local Platform — Minikube, MinIO, PostgreSQL, Vault | Terraform · Kubernetes · Helm | [→](docs/project-01-local-platform.md) |
| 13 | dbt at Depth — Airflow git-sync + Cosmos | Airflow · dbt · Kubernetes | [→](docs/project-13-airflow-dbt-infra.md) |
| 15 | Delta Lake Lakehouse Infrastructure | MinIO · Nessie · Trino | [→](docs/project-15-lakehouse-infra.md) |
| 19 | Streaming Infrastructure — Redpanda + Debezium | Redpanda · Kafka Connect · Kubernetes | [→](docs/project-19-streaming-infra.md) |
| 24 | ClickHouse OLAP Deployment | ClickHouse · Helm | [→](docs/project-24-clickhouse-infra.md) |
| 27 | Keycloak IAM | Keycloak · OIDC · Kubernetes | [→](docs/project-27-keycloak.md) |
| 30 | Governance Infrastructure — Dagster, DataHub, Marquez | Dagster · DataHub · Marquez · Keycloak | [→](docs/project-30-governance-infra.md) |
| 34 | Azure DevOps CI/CD Pipelines | Azure DevOps · Terraform | [→](docs/project-34-azure-devops.md) |

---

---

## Projects

### Project 1: Local Platform — Minikube, MinIO, PostgreSQL, Vault

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![Vault](https://img.shields.io/badge/Vault-FFEC6E?logo=vault&logoColor=black)

The foundation: a single `terraform apply` provisions the entire local data platform on Minikube. PostgreSQL runs via CloudNativePG with automated barman backups to MinIO. Vault manages all credentials — no secrets in Terraform state.

```mermaid
graph TB
    subgraph minikube["Minikube Cluster"]
        subgraph core["namespace: data-core"]
            PG[(CloudNativePG\nPostgreSQL)]
            MINIO[MinIO\nS3-compatible]
            VAULT[HashiCorp\nVault]
        end
        subgraph airflow_ns["namespace: airflow"]
            AF[Apache Airflow\nKubernetesExecutor]
        end
        subgraph data_tools["namespace: data-tools"]
            TOOLS[Analytical\ntools]
        end
        subgraph governance_ns["namespace: governance"]
            GOV[Governance\ntools]
        end
    end
    VAULT -->|credentials| PG
    VAULT -->|credentials| AF
    PG -->|barman backup| MINIO
    AF -.->|spawns task pods| airflow_ns
```

[→ `local/`](local/)

---

### Project 13: dbt at Depth — Airflow + dbt Infrastructure

![Apache Airflow](https://img.shields.io/badge/Apache%20Airflow-017CEE?logo=apacheairflow&logoColor=white)
![dbt](https://img.shields.io/badge/dbt-FF694B?logo=dbt&logoColor=white)

Added git-sync sidecar to the Airflow Helm release, syncing the `finanzwerk-dbt` repo into the scheduler pod. Astronomer Cosmos maps each dbt model to an individual Airflow task, giving per-model failure visibility in the UI.

```mermaid
sequenceDiagram
    participant GH as GitHub\n(finanzwerk-dbt)
    participant GS as git-sync\nsidecar
    participant AF as Airflow\nScheduler
    participant DB as PostgreSQL

    GS->>GH: poll every 60s
    GH-->>GS: dbt project files
    GS->>AF: sync to /dbt/
    AF->>DB: dbt run (via Cosmos\nper-model tasks)
    DB-->>AF: results
```

[→ `local/airflow.tf`](local/airflow.tf)

---

### Project 15: Delta Lake Lakehouse Infrastructure

![MinIO](https://img.shields.io/badge/MinIO-C72E49?logo=minio&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)

Provisioned MinIO buckets for the medallion lakehouse (`finanzwerk-raw`, `finanzwerk-processed`), deployed Project Nessie as the Iceberg catalog, and deployed Trino as the query engine over the lakehouse.

```mermaid
graph LR
    subgraph minio["MinIO (S3-compatible)"]
        RAW[finanzwerk-raw\nbronze layer]
        PROC[finanzwerk-processed\nsilver + gold]
    end
    NESSIE[Project Nessie\nIceberg Catalog]
    TRINO[Trino\nQuery Engine]

    NESSIE -->|catalog metadata| TRINO
    TRINO -->|reads Parquet| RAW
    TRINO -->|reads Parquet| PROC
```

[→ `local/`](local/)

---

### Project 19: Streaming Infrastructure — Redpanda + Debezium

![Apache Kafka](https://img.shields.io/badge/Redpanda-E50695?logo=apachekafka&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)

Deployed Redpanda (Kafka-compatible, no ZooKeeper) in the `data-tools` namespace. Created Debezium Kafka Connect deployment and enabled PostgreSQL logical replication (`wal_level=logical`) on the CloudNativePG cluster for CDC.

```mermaid
graph LR
    PG[(PostgreSQL\nwal_level=logical)] -->|WAL stream| DC[Debezium\nKafka Connect]
    DC -->|CDC events| RP[Redpanda\nKafka broker]
    RP --> T1[ict-events-raw]
    RP --> T2[ict-events-classified]
    RP --> T3[cdc.public.*]
    RP --> T4[ict-alerts]
```

[→ `local/redpanda.tf`](local/redpanda.tf) · [→ `local/debezium.tf`](local/debezium.tf)

---

### Project 24: ClickHouse OLAP Deployment

![ClickHouse](https://img.shields.io/badge/ClickHouse-FFCC01?logo=clickhouse&logoColor=black)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)

Deployed ClickHouse in the `data-tools` namespace. At 10M rows ClickHouse returns the quarterly DORA report 40× faster than PostgreSQL — columnar storage and vectorised execution trading write throughput for read speed.

```mermaid
graph TB
    PG[(PostgreSQL\nOLTP + dbt models)] -->|batch sync| CH[(ClickHouse\nOLAP)]
    CH -->|dashboard queries\n&lt;100ms at 10M rows| DASH[Compliance\nDashboards]
    PG -->|complex SQL\nsmall result sets| RPT[Ad-hoc\nReports]
```

[→ `local/`](local/)

---

### Project 30: Governance Infrastructure

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)

Provisioned the entire governance namespace: Dagster (asset orchestration), DataHub (data catalog), Marquez (OpenLineage backend), Keycloak (OIDC identity provider), and Elasticsearch (DataHub dependency). Six Helm releases, all wired to the shared PostgreSQL and Redpanda instances.

```mermaid
graph TB
    subgraph governance["namespace: governance"]
        DAGSTER[Dagster]
        DH[DataHub]
        MQ[Marquez\nOpenLineage]
        KC[Keycloak\nOIDC]
        ES[Elasticsearch]
    end
    PG[(PostgreSQL)] -->|metadata backend| DAGSTER
    PG -->|metadata backend| DH
    PG -->|lineage backend| MQ
    PG -->|realm backend| KC
    ES -->|search index| DH
    DAGSTER -->|emit lineage| MQ
    AF[Airflow] -->|emit lineage| MQ
```

[→ `local/dagster.tf`](local/dagster.tf) · [→ `local/datahub.tf`](local/datahub.tf) · [→ `local/marquez.tf`](local/marquez.tf)

---

### Project 34: Azure DevOps CI/CD Pipelines

![Azure DevOps](https://img.shields.io/badge/Azure%20DevOps-0078D7?logo=azuredevops&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)

YAML pipeline: Terraform plan outputs an immutable plan artifact, the Apply stage uses a `deployment` job type targeting the `production` environment — requiring manual approval before any infra change reaches production. Satisfies DORA Article 9 change management requirements.

```mermaid
graph LR
    PR[Pull Request] -->|trigger| PLAN[Terraform Plan\nstage]
    PLAN -->|artifact: tfplan| GATE{Manual\nApproval}
    GATE -->|approved| APPLY[Terraform Apply\nstage]
    GATE -->|rejected| STOP[Pipeline\nhalted]
    APPLY --> AWS[AWS EKS\ninfrastructure]
```

[→ `azure-pipelines.yml`](azure-pipelines.yml)
