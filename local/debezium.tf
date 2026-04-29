resource "kubernetes_secret_v1" "debezium_user" {
  depends_on = [kubernetes_namespace_v1.postgres_namespace]
  metadata {
    name      = "debezium-secret"
    namespace = var.postgres_namespace
  }
  data = {
    username = "debezium"
    password = var.postgres_debezium_password
  }
}

resource "kubernetes_secret_v1" "streaming_db_credentials" {
  metadata {
    name      = "streaming-db-credentials"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
  data = {
    username = var.postgres_finanzwerk_readwrite_username
    password = var.postgres_finanzwerk_readwrite_password
  }
}

resource "kubernetes_deployment_v1" "kafka_connect" {
  metadata {
    name      = "kafka-connect"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
    labels    = { app = "kafka-connect" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "kafka-connect" }
    }
    template {
      metadata {
        labels = { app = "kafka-connect" }
      }
      spec {
        container {
          name  = "kafka-connect"
          image = "debezium/connect:2.5"
          port {
            container_port = 8083
          }
          env {
            name  = "BOOTSTRAP_SERVERS"
            value = "redpanda.${kubernetes_namespace_v1.data_tools_namespace.metadata[0].name}.svc.cluster.local:9093"
          }
          env {
            name  = "GROUP_ID"
            value = "debezium-connect-cluster"
          }
          env {
            name  = "CONFIG_STORAGE_TOPIC"
            value = "debezium.configs"
          }
          env {
            name  = "OFFSET_STORAGE_TOPIC"
            value = "debezium.offsets"
          }
          env {
            name  = "STATUS_STORAGE_TOPIC"
            value = "debezium.status"
          }
          env {
            name  = "CONFIG_STORAGE_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "OFFSET_STORAGE_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "STATUS_STORAGE_REPLICATION_FACTOR"
            value = "1"
          }
          resources {
            requests = {
              memory = "512Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }
          liveness_probe {
            http_get {
              path = "/"
              port = 8083
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }
        }
      }
    }
  }
  depends_on = [helm_release.redpanda, kubernetes_job_v1.redpanda_topics]
}

resource "kubernetes_service_v1" "kafka_connect" {
  metadata {
    name      = "kafka-connect"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
  spec {
    selector = { app = "kafka-connect" }
    port {
      name        = "rest"
      port        = 8083
      target_port = 8083
    }
  }
}
