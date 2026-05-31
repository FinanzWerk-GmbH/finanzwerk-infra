resource "kubernetes_job_v1" "create_marquez_db" {
  depends_on = [kubernetes_manifest.postgres_cluster]
  metadata {
    name      = "create-marquez-db"
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
            "psql postgresql://${var.postgres_finanzwerk_owner_username}:$OWNER_PASSWORD@postgres-rw:5432/postgres -c 'CREATE DATABASE marquez OWNER ${var.postgres_finanzwerk_owner_username}' || true"
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

resource "helm_release" "marquez" {
  depends_on       = [kubernetes_job_v1.create_marquez_db]
  name             = "marquez"
  repository       = "https://marquezproject.github.io/marquez"
  chart            = "marquez"
  version          = "0.50.0"
  namespace        = kubernetes_namespace_v1.governance_namespace.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 300

  values = [<<-EOT
    marquez:
      migrateOnStartup: true

    postgresql:
      enabled: false

    externalDatabase:
      host: postgres-rw.${var.postgres_namespace}.svc.cluster.local
      port: 5432
      database: marquez
      username: ${var.postgres_finanzwerk_owner_username}
      password: ${var.postgres_finanzwerk_owner_password}

    resources:
      requests:
        memory: 256Mi
        cpu: 100m

    ingress:
      enabled: true
      ingressClassName: ${var.nginx_ingress_classname}
      host: marquez.127.0.0.1.nip.io
  EOT
  ]
}
