resource "kubernetes_job_v1" "create_mlflow_db" {
  depends_on = [kubernetes_manifest.postgres_cluster]
  metadata {
    name      = "create-mlflow-db"
    namespace = var.postgres_namespace
  }
  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "psql"
          image = "ghcr.io/cloudnative-pg/postgresql:16"
          command = [
            "/bin/sh", "-c",
            "psql postgresql://${var.postgres_finanzwerk_owner_username}:$OWNER_PASSWORD@postgres-rw:5432/postgres -c 'CREATE DATABASE mlflow OWNER ${var.postgres_finanzwerk_owner_username}' || true"
          ]
          env {
            name = "OWNER_PASSWORD"
            value_from {
              secret_key_ref {
                name = "postgres-credentials"
                key  = "password"
              }
            }
          }
        }
      }
    }
  }
  timeouts {
    create = "2m"
  }
}

resource "kubernetes_job_v1" "create_mlflow_bucket" {
  depends_on = [helm_release.minio]
  metadata {
    name      = "create-mlflow-bucket"
    namespace = var.minio_namespace
  }
  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "mc"
          image = "minio/mc"
          command = [
            "/bin/sh", "-c",
            <<-EOT
              until mc alias set finanzwerk http://${var.minio_api_endpoint} $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD; do
                sleep 3
              done
              mc mb --ignore-existing finanzwerk/finanzwerk-mlflow
            EOT
          ]
          env {
            name  = "MINIO_ROOT_USER"
            value = var.minio_root_username
          }
          env {
            name  = "MINIO_ROOT_PASSWORD"
            value = var.minio_root_password
          }
        }
      }
    }
  }
  timeouts {
    create = "5m"
  }
}

resource "kubernetes_deployment_v1" "mlflow" {
  depends_on = [
    kubernetes_job_v1.create_mlflow_db,
    kubernetes_job_v1.create_mlflow_bucket,
  ]
  metadata {
    name      = "mlflow"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
    labels    = { app = "mlflow" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "mlflow" }
    }
    template {
      metadata {
        labels = { app = "mlflow" }
      }
      spec {
        container {
          name  = "mlflow"
          image = "ghcr.io/mlflow/mlflow:v2.15.0"
          command = [
            "mlflow", "server",
            "--backend-store-uri", "postgresql+psycopg2://${var.postgres_finanzwerk_owner_username}:${var.postgres_finanzwerk_owner_password}@postgres-rw.${var.postgres_namespace}.svc.cluster.local:5432/mlflow",
            "--artifacts-destination", "s3://finanzwerk-mlflow/",
            "--serve-artifacts",
            "--host", "0.0.0.0",
            "--port", "5000",
          ]
          port {
            container_port = 5000
          }
          env {
            name  = "MLFLOW_S3_ENDPOINT_URL"
            value = "http://${var.minio_api_endpoint}"
          }
          env {
            name  = "AWS_ACCESS_KEY_ID"
            value = var.minio_root_username
          }
          env {
            name  = "AWS_SECRET_ACCESS_KEY"
            value = var.minio_root_password
          }
          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "mlflow" {
  metadata {
    name      = "mlflow"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
  spec {
    selector = { app = "mlflow" }
    port {
      name        = "http"
      port        = 5000
      target_port = 5000
    }
  }
}

resource "kubernetes_ingress_v1" "mlflow" {
  metadata {
    name      = "mlflow"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = "nginx"
    rule {
      host = "mlflow.127.0.0.1.nip.io"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "mlflow"
              port {
                number = 5000
              }
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_deployment_v1.mlflow]
}
