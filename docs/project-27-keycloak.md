# Project 27: Keycloak IAM Infrastructure

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Keycloak](https://img.shields.io/badge/Keycloak-4D4D4D?logo=keycloak&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)

> Keycloak deployed to Minikube as the central identity provider. Realm, groups, and OAuth clients all managed through Terraform — no manual clicking in the Keycloak admin UI.

The problem with clicking through the Keycloak UI is that you can't reproduce it. If the cluster dies, you have to remember what you configured. With the Terraform Keycloak provider, destroying and recreating the cluster restores the exact same auth setup. It's also reviewable — you can see in git exactly what changed and when.

## Identity provider architecture

```mermaid
graph TB
    subgraph tf["Terraform (keycloak provider)"]
        REALM[Realm: finanzwerk\nOIDC configuration]
        GROUPS[Groups:\n  data-engineers\n  compliance\n  read-only]
        CLIENTS[Clients:\n  dagster\n  airflow\n  superset]
    end

    subgraph k8s["Minikube — namespace: keycloak"]
        KC[Keycloak server\nRealm: finanzwerk]
        KC_DB[(PostgreSQL\nkeycloak schema)]
    end

    subgraph apps["Applications"]
        DAGSTER[Dagster]
        AIRFLOW[Airflow]
        SUPERSET[Superset]
    end

    tf --> KC
    KC --> DAGSTER & AIRFLOW & SUPERSET
    KC_DB --- KC

    DAGSTER -->|check group membership| OPA[OPA policy engine]
```

Three groups map to what each person can do:

| Keycloak group | PostgreSQL role | Can do |
|---------------|----------------|--------|
| `data-engineers` | `readwrite` | Run any pipeline, materialize any asset |
| `compliance` | `readonly` | Read compliance assets, can't modify |
| `read-only` | `readonly` | Browse lineage and catalogue, nothing else |

## Code

| Path | Description |
|------|-------------|
| [`local/keycloak.tf`](../local/keycloak.tf) | Keycloak Helm + realm + groups |
| [`local/opa.tf`](../local/opa.tf) | Open Policy Agent deployment |
