resource "kubernetes_job_v1" "create_keycloak_db" {
  depends_on = [kubernetes_manifest.postgres_cluster]
  metadata {
    name      = "create-keycloak-db"
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
            "psql postgresql://${var.postgres_finanzwerk_owner_username}:$OWNER_PASSWORD@postgres-rw:5432/postgres -c 'CREATE DATABASE keycloak OWNER ${var.postgres_finanzwerk_owner_username}' || true"
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

resource "helm_release" "keycloak" {
  depends_on       = [kubernetes_job_v1.create_keycloak_db]
  name             = "keycloak"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "keycloak"
  version          = "21.4.4"
  namespace        = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 600

  values = [<<-EOT
    auth:
      adminUser: admin
      adminPassword: ${var.keycloak_admin_password}

    production: false
    proxy: edge

    postgresql:
      enabled: false

    externalDatabase:
      host: postgres-rw.${var.postgres_namespace}.svc.cluster.local
      port: 5432
      user: ${var.postgres_finanzwerk_owner_username}
      password: ${var.postgres_finanzwerk_owner_password}
      database: keycloak

    resources:
      requests:
        memory: 512Mi
        cpu: 250m
      limits:
        memory: 1Gi
        cpu: 1000m

    ingress:
      enabled: true
      ingressClassName: ${var.nginx_ingress_classname}
      hostname: keycloak.127.0.0.1.nip.io
  EOT
  ]
}

# Configure realm, clients, roles, and users via kcadm.sh
resource "kubernetes_job_v1" "keycloak_realm_setup" {
  depends_on = [helm_release.keycloak]
  metadata {
    name      = "keycloak-realm-setup"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "kcadm"
          image = "bitnami/keycloak:latest"
          command = [
            "/bin/bash", "-c",
            <<-EOT
              KC=http://keycloak.${kubernetes_namespace_v1.data_tools_namespace.metadata[0].name}.svc.cluster.local:80

              until curl -sf $KC/health/ready; do echo "waiting for keycloak..."; sleep 5; done

              kcadm.sh config credentials --server $KC --realm master \
                --user admin --password $KEYCLOAK_ADMIN_PASSWORD

              kcadm.sh create realms -s realm=finanzwerk -s enabled=true -s displayName="FinanzWerk" || true

              # Roles
              for role in data-engineer compliance-analyst auditor; do
                kcadm.sh create roles -r finanzwerk -s name=$role || true
              done

              # OIDC clients
              kcadm.sh create clients -r finanzwerk \
                -s clientId=airflow -s enabled=true \
                -s 'redirectUris=["http://airflow.127.0.0.1.nip.io/*"]' \
                -s publicClient=false -s clientAuthenticatorType=client-secret || true

              kcadm.sh create clients -r finanzwerk \
                -s clientId=trino -s enabled=true \
                -s 'redirectUris=["http://trino.127.0.0.1.nip.io/*"]' \
                -s publicClient=true || true

              # Users
              kcadm.sh create users -r finanzwerk \
                -s username=iyad -s enabled=true \
                -s 'email=iyad@finanzwerk.local' || true
              kcadm.sh set-password -r finanzwerk --username iyad --new-password 'Admin123!'
              kcadm.sh add-roles -r finanzwerk --uusername iyad --rolename data-engineer

              kcadm.sh create users -r finanzwerk \
                -s username=compliance-officer -s enabled=true \
                -s 'email=compliance@finanzwerk.local' || true
              kcadm.sh set-password -r finanzwerk --username compliance-officer --new-password 'Comply123!'
              kcadm.sh add-roles -r finanzwerk --uusername compliance-officer --rolename compliance-analyst

              echo "realm setup complete"
            EOT
          ]
          env {
            name  = "KEYCLOAK_ADMIN_PASSWORD"
            value = var.keycloak_admin_password
          }
        }
      }
    }
    backoff_limit = 5
  }
  timeouts { create = "10m" }
}
