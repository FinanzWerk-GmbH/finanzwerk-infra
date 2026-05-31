resource "kubernetes_job_v1" "create_datahub_db" {
  depends_on = [kubernetes_manifest.postgres_cluster]
  metadata {
    name      = "create-datahub-db"
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
            "psql postgresql://${var.postgres_finanzwerk_owner_username}:$OWNER_PASSWORD@postgres-rw:5432/postgres -c 'CREATE DATABASE datahub OWNER ${var.postgres_finanzwerk_owner_username}' || true"
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

# DataHub is resource-intensive (recommended 8+ GB RAM for full stack).
# For Minikube, use --memory 10240 when starting: minikube start --memory 10240 --cpus 4
resource "helm_release" "datahub" {
  depends_on = [
    kubernetes_job_v1.create_datahub_db,
    helm_release.elasticsearch,
  ]
  name             = "datahub"
  repository       = "https://helm.datahubproject.io/"
  chart            = "datahub"
  version          = "0.3.30"
  namespace        = kubernetes_namespace_v1.governance_namespace.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 900

  values = [<<-EOT
    global:
      graph_service_impl: elasticsearch
      elasticsearch:
        host: elasticsearch.${kubernetes_namespace_v1.governance_namespace.metadata[0].name}.svc.cluster.local
        port: "9200"
      kafka:
        bootstrap:
          server: redpanda.${kubernetes_namespace_v1.data_tools_namespace.metadata[0].name}.svc.cluster.local:9093
        schemaregistry:
          url: http://redpanda.${kubernetes_namespace_v1.data_tools_namespace.metadata[0].name}.svc.cluster.local:8081
      sql:
        datasource:
          host_port: "postgres-rw.${var.postgres_namespace}.svc.cluster.local:5432"
          url: "jdbc:postgresql://postgres-rw.${var.postgres_namespace}.svc.cluster.local:5432/datahub"
          driver: "org.postgresql.Driver"
          username: ${var.postgres_finanzwerk_owner_username}
          password:
            secretRef: postgres-credentials
            secretKey: password

    datahub-frontend:
      enabled: true
      ingress:
        enabled: true
        className: ${var.nginx_ingress_classname}
        hosts:
          - host: datahub.127.0.0.1.nip.io
            paths:
              - "/"

    datahub-gms:
      enabled: true
      resources:
        requests:
          memory: 512Mi
          cpu: 250m

    datahub-mae-consumer:
      enabled: true
    datahub-mce-consumer:
      enabled: true

    datahubUpgrade:
      enabled: true

    acryl-datahub-actions:
      enabled: false

    prerequisites:
      enabled: false
      kafka:
        enabled: false
      elasticsearch:
        enabled: false
      mysql:
        enabled: false
  EOT
  ]
}
