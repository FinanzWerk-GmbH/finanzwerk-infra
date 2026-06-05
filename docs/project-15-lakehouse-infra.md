# Project 15: Lakehouse Infrastructure — Spark Operator and MinIO

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Apache Spark](https://img.shields.io/badge/Apache%20Spark-E25A1C?logo=apachespark&logoColor=white)
![MinIO](https://img.shields.io/badge/MinIO-C72E49?logo=minio&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)

> Kubernetes Spark Operator deployed via Terraform so Spark jobs can be submitted as Kubernetes resources. MinIO gets the bucket structure for the three medallion layers. No `spark-submit` scripts.

The Spark Operator replaces `spark-submit` with Kubernetes custom resources. Instead of running a shell command, you define a `SparkApplication` YAML and `kubectl apply` it. That means GitOps works for Spark jobs — the job definition is in source control, not a script someone runs manually.

## Infrastructure components

```mermaid
graph TB
    subgraph tf["Terraform modules"]
        MINIO_TF[minio.tf\nbuckets · IAM policies]
        SPARK_TF[spark.tf\noperator Helm release\nSparkApplication CRDs]
    end

    subgraph k8s["Minikube"]
        subgraph spark_ns["namespace: spark"]
            OP[Spark Operator\ncontroller]
            subgraph job["SparkApplication: bronze_to_silver"]
                DRV[Driver pod\n2 CPU · 4Gi]
                EX1[Executor 1\n2 CPU · 4Gi]
                EX2[Executor 2\n2 CPU · 4Gi]
                EX3[Executor 3\n2 CPU · 4Gi]
            end
            OP -->|creates| DRV
            OP -->|creates| EX1 & EX2 & EX3
        end

        subgraph dt_ns["namespace: data-tools"]
            MINIO[(MinIO\nfinanzwerk-raw/\n  bronze/\n  silver/\n  gold/)]
        end
    end

    tf --> k8s
    DRV <-->|S3A protocol| MINIO
    EX1 <-->|S3A| MINIO
```

The bucket layout matches the medallion layers: `bronze/` for raw landing, `silver/` for cleaned and schema-enforced data, `gold/` for aggregated business-ready data. The S3A protocol means Spark talks to MinIO the same way it would talk to AWS S3 — same configuration, just different endpoint URL.

## Code

| Path | Description |
|------|-------------|
| [`local/spark.tf`](../local/spark.tf) | Spark Operator Helm + RBAC |
| [`local/minio.tf`](../local/minio.tf) | Bucket provisioning + bucket policies |
