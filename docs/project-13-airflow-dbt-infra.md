# Project 13: dbt and Airflow Infrastructure

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Apache Airflow](https://img.shields.io/badge/Apache%20Airflow-017CEE?logo=apacheairflow&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)

> Airflow deployed to Minikube with KubernetesExecutor. DAG files stay in sync with git via a sidecar container. dbt runs in isolated task pods, not inside the scheduler.

The KubernetesExecutor means each Airflow task spawns its own pod. It's more setup than the LocalExecutor but you get proper resource isolation — a memory-hungry Spark submission doesn't kill the scheduler. Dead task pods clean themselves up.

## Deployment architecture

```mermaid
graph TB
    subgraph tf["terraform apply"]
        AF_TF[airflow.tf\nHelm release]
        NS[namespace: airflow]
    end

    subgraph k8s["Minikube — namespace: airflow"]
        SCHED[Airflow Scheduler\npod]
        WEB[Airflow Webserver\npod]
        GIT[git-sync sidecar\npolls GitHub every 60s]
        subgraph tasks["Task pods (ephemeral)"]
            T1[task: ingest_vendors]
            T2[task: dbt run]
            T3[task: validate_data]
        end
    end

    GIT -->|mounts DAG files| SCHED
    SCHED -->|spawns| tasks
    AF_TF --> k8s

    subgraph config["Key configuration"]
        EXEC["executor: KubernetesExecutor"]
        CONN["connections via Vault\nnot airflow.cfg"]
        RBAC["RBAC enabled\ngit-sync ServiceAccount"]
    end
```

The git-sync sidecar is how DAG deployments work — it watches the GitHub repo and updates the local DAG directory every 60 seconds. You merge a PR and it's live within a minute. No image rebuilds, no rolling restarts.

dbt's `manifest.json` gets written to MinIO after each run and downloaded at the start of the next one. That's what enables `--select state:modified+` to work — dbt compares the current model SQL against the previous manifest to figure out what changed.

## Code

| Path | Description |
|------|-------------|
| [`local/airflow.tf`](../local/airflow.tf) | Airflow Helm release, git-sync config |
