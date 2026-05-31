resource "kubernetes_job_v1" "create_dagster_db" {
  depends_on = [kubernetes_manifest.postgres_cluster]
  metadata {
    name      = "create-dagster-db"
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
            "psql postgresql://${var.postgres_finanzwerk_owner_username}:$OWNER_PASSWORD@postgres-rw:5432/postgres -c 'CREATE DATABASE dagster OWNER ${var.postgres_finanzwerk_owner_username}' || true"
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
  timeouts { create = "2m" }
}

resource "kubernetes_job_v1" "create_dagster_logs_bucket" {
  depends_on = [helm_release.minio]
  metadata {
    name      = "create-dagster-logs-bucket"
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
              until mc alias set finanzwerk http://${var.minio_api_endpoint} $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD; do sleep 3; done
              mc mb --ignore-existing finanzwerk/finanzwerk-dagster-logs
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
  timeouts { create = "5m" }
}

resource "kubernetes_secret_v1" "dagster_postgresql" {
  metadata {
    name      = "dagster-postgresql-secret"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
  data = {
    postgresql-password = var.postgres_finanzwerk_owner_password
  }
}

resource "helm_release" "dagster" {
  depends_on = [
    kubernetes_job_v1.create_dagster_db,
    kubernetes_job_v1.create_dagster_logs_bucket,
    kubernetes_secret_v1.dagster_postgresql,
  ]
  name             = "dagster"
  repository       = "https://dagster-io.github.io/helm"
  chart            = "dagster"
  version          = "1.8.4"
  namespace        = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 600

  values = [<<-EOT
    global:
      postgresqlSecretName: dagster-postgresql-secret

    postgresql:
      enabled: false
      external:
        host: postgres-rw.${var.postgres_namespace}.svc.cluster.local
        port: 5432
        database: dagster
        user: ${var.postgres_finanzwerk_owner_username}

    dagsterWebserver:
      replicaCount: 1
      resources:
        requests:
          memory: 256Mi
          cpu: 100m

    dagsterDaemon:
      enabled: true
      resources:
        requests:
          memory: 256Mi
          cpu: 100m

    ingress:
      enabled: true
      ingressClassName: ${var.nginx_ingress_classname}
      webserver:
        host: dagster.127.0.0.1.nip.io

    runLauncher:
      type: K8sRunLauncher
      config:
        k8sRunLauncher:
          jobNamespace: ${kubernetes_namespace_v1.data_tools_namespace.metadata[0].name}
          imagePullPolicy: Never

    userDeployments:
      enabled: true
      deployments:
        - name: finanzwerk-user-code
          image:
            repository: finanzwerk/dagster
            tag: latest
            pullPolicy: Never
          dagsterApiGrpcArgs:
            - "-f"
            - "/app/definitions.py"
          port: 4000
          envVars:
            - name: DAGSTER_POSTGRES_URL
              value: "postgresql://${var.postgres_finanzwerk_owner_username}:${var.postgres_finanzwerk_owner_password}@postgres-rw.${var.postgres_namespace}.svc.cluster.local:5432/dagster"
            - name: MINIO_ENDPOINT
              value: "http://${var.minio_api_endpoint}"
            - name: AWS_ACCESS_KEY_ID
              value: ${var.minio_root_username}
            - name: AWS_SECRET_ACCESS_KEY
              value: ${var.minio_root_password}
            - name: DB_HOST
              value: postgres-rw.${var.postgres_namespace}.svc.cluster.local
            - name: DB_NAME
              value: ${var.postgres_finanzwerk_db}
            - name: DB_USER
              value: ${var.postgres_finanzwerk_readwrite_username}
            - name: DB_PASSWORD
              value: ${var.postgres_finanzwerk_readwrite_password}

    computeLogs:
      enabled: true
      custom:
        module: dagster_aws.s3.compute_log_manager
        class: S3ComputeLogManager
        config:
          bucket: finanzwerk-dagster-logs
          prefix: dagster/logs
          endpoint_url: "http://${var.minio_api_endpoint}"
          region_name: us-east-1
          skip_empty_files: true
          upload_interval: 30
  EOT
  ]
}
