# Project 34: Azure DevOps CI/CD

![Azure DevOps](https://img.shields.io/badge/Azure%20DevOps-0078D7?logo=azuredevops&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![dbt](https://img.shields.io/badge/dbt-FF694B?logo=dbt&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white)

> Azure Pipelines for the three main repos. The infra pipeline has a mandatory human approval gate between plan and apply. The dbt pipeline only runs models that actually changed. Airflow has parallel lint and test stages.

The infra pipeline is the most important one to get right. In a regulated environment, a `terraform apply` without any approval process is a governance finding. The approval gate is enforced by the pipeline definition using a `deployment` job — it's not just convention, it can't be bypassed without changing the YAML.

## Pipeline overview

```mermaid
flowchart TD
    subgraph infra["finanzwerk-infra — azure-pipelines.yml"]
        TF_PLAN["Plan stage\nterraform init + plan\nPublish artifact: tfplan"]
        GATE{Environment: production\nApproval required}
        TF_APPLY["Apply stage\nDownload artifact: tfplan\nterraform apply"]
        TF_PLAN --> GATE --> TF_APPLY
    end

    subgraph dbt["finanzwerk-dbt — azure-pipelines.yml"]
        LINT_DBT[sqlfluff lint]
        DBT_BUILD["dbt build\n--select state:modified+"]
        PUB_MNF[Publish manifest.json]
        LINT_DBT --> DBT_BUILD --> PUB_MNF
    end

    subgraph airflow["finanzwerk-airflow — azure-pipelines.yml"]
        direction LR
        RUFF[ruff lint]
        PYTEST[pytest + coverage]
        RUFF -.->|concurrent| PYTEST
    end
```

The terraform approval works because `deployment` jobs in Azure Pipelines can be gated on an `environment` resource. The tfplan artifact is published before the gate — whoever approves sees exactly what will be applied. After approval, that same plan file is downloaded and applied. The plan can't drift between review and execution.

## Code

| Path | Description |
|------|-------------|
| [`azure-pipelines.yml`](../azure-pipelines.yml) | Infra Plan + gated Apply |
| [`docs/cicd_comparison.md`](../docs/cicd_comparison.md) | GitHub Actions vs Azure DevOps comparison |
| [`azure-pipelines.yml`](../../finanzwerk-dbt/azure-pipelines.yml) | dbt lint + state-aware build |
| [`azure-pipelines.yml`](../../finanzwerk-airflow/azure-pipelines.yml) | Parallel lint + pytest |
