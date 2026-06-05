# Project 19: Streaming Infrastructure — Redpanda on Minikube

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Redpanda](https://img.shields.io/badge/Redpanda-E3000F?logo=redpanda&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)

> Redpanda (Kafka-compatible, no JVM) deployed to Minikube via Terraform. Topics created as part of the Terraform apply. Same Kafka client libraries work unchanged.

Picked Redpanda over Kafka for local dev because it doesn't need a JVM or ZooKeeper — it's a single binary that starts in a couple of seconds. The API is 100% Kafka-compatible so all the Python producer/consumer code works without any changes if you switch to a real Kafka cluster.

## Cluster topology

```mermaid
graph TB
    subgraph tf["Terraform"]
        RP_TF[redpanda.tf\nHelm release\ntopic provisioning Job]
    end

    subgraph k8s["Minikube — namespace: redpanda"]
        subgraph cluster["Redpanda cluster (3 brokers)"]
            B1[broker-0\n1 CPU · 2Gi]
            B2[broker-1\n1 CPU · 2Gi]
            B3[broker-2\n1 CPU · 2Gi]
        end
        SR[Schema Registry\n:8081]
        ADMIN[Admin API\n:9644]
        CON[Kafka Connect\n:8083]

        subgraph topics["Topics (provisioned by init Job)"]
            T1[ict-incidents\n3 partitions · 2 replicas]
            T2[vendor-updates\n1 partition · 2 replicas]
            T3[ict-incidents-dlq\n1 partition · 1 replica]
        end
    end

    tf --> cluster
    tf --> topics
```

3 partitions on `ict-incidents` so up to 3 consumer instances can process in parallel. There are three separate consumer groups reading from this topic (bronze, classification, notification) — each gets all messages independently.

## Code

| Path | Description |
|------|-------------|
| [`local/redpanda.tf`](../local/redpanda.tf) | Redpanda Helm + topic init Job |
| [`local/kafka_connect.tf`](../local/kafka_connect.tf) | Kafka Connect for Debezium |
