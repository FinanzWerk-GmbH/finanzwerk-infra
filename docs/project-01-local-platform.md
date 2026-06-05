# Project 1: Local Platform — Minikube, MinIO, PostgreSQL, Vault

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![Vault](https://img.shields.io/badge/Vault-FFEC6E?logo=vault&logoColor=black)

> One `terraform apply` spins up the entire local data platform on Minikube. PostgreSQL, MinIO (S3-compatible object storage), and Vault all running in Kubernetes with no manual steps.

Started here because everything else in the project depends on a running database and somewhere to put files. The goal was to make it fully reproducible — if you nuke the cluster and run `terraform apply` again you get the exact same setup. No clicking around in UIs, no ad-hoc `kubectl apply` commands floating around.

Vault is handling secrets instead of Kubernetes Secrets because k8s Secrets are just base64-encoded (not actually encrypted). Vault gives you proper encryption, versioning, and an audit log. DORA Art. 9 requires documented access controls on ICT systems, so having an audit trail for secret access matters.

## Architecture

```mermaid
graph TB
    TF[terraform apply] -->|provisions| MK

    subgraph MK["Minikube Cluster (local dev)"]
        subgraph pg_ns["namespace: postgres"]
            CNPG[(CloudNativePG\nPostgreSQL 16)]
            BK[barman\nbackup agent]
        end
        subgraph dt_ns["namespace: data-tools"]
            MINIO[(MinIO\nS3-compatible)]
        end
        subgraph vault_ns["namespace: vault"]
            VLT[HashiCorp Vault\ndev mode]
        end
        subgraph af_ns["namespace: airflow"]
            AF[Apache Airflow\nKubernetesExecutor]
        end
    end

    VLT -->|postgres password| CNPG
    VLT -->|minio creds| AF
    BK -->|daily backup| MINIO
    AF -.->|spawns task pods| af_ns
```

CloudNativePG is doing the heavy lifting for Postgres — it handles failover and the backup integration with barman/MinIO automatically. Using MinIO locally means the pipeline code uses the same boto3/S3 API as AWS, so nothing changes when deploying to cloud.

## Code

| Path | Description |
|------|-------------|
| [`local/postgresql.tf`](../local/postgresql.tf) | CloudNativePG cluster, roles, backup config |
| [`local/minio.tf`](../local/minio.tf) | MinIO Helm release, bucket creation Job |
| [`local/vault.tf`](../local/vault.tf) | Vault Helm release, KV secrets engine |
| [`local/namespaces.tf`](../local/namespaces.tf) | All K8s namespace definitions |
| [`local/variables.tf`](../local/variables.tf) | All configurable parameters |
