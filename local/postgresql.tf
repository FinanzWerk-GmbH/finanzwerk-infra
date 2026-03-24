resource "helm_release" "postgres-cnpg-operator" {
  name       = "postgres"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cnpg"
  namespace  = var.postgres_namespace
}

resource "kubernetes_manifest" "postgres_cluster" {
  depends_on = [
    helm_release.postgres-cnpg-operator,
    kubernetes_secret_v1.postgres_owner_credentials,
    kubernetes_secret_v1.readonly_user,
    kubernetes_secret_v1.readwrite_user,
    kubernetes_secret_v1.minio_credentials,
  ]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = "postgres"
      namespace = var.postgres_namespace
    }
    spec = {
      instances = 1
      storage = {
        size         = "5Gi"
        storageClass = var.minikube_storage_class
      }
      bootstrap = {
        initdb = {
          database = var.postgres_finanzwerk_db
          owner    = var.postgres_finanzwerk_owner_username
          secret = {
            name = "postgres-credentials"
          }
        }
      }
      managed = {
        roles = [
          {
            name           = var.postgres_finanzwerk_readonly_username
            ensure         = "present"
            login          = true
            passwordSecret = { name = "readonly-user-secret" }
          },
          {
            name           = var.postgres_finanzwerk_readwrite_username
            ensure         = "present"
            login          = true
            passwordSecret = { name = "readwrite-user-secret" }
          }
        ]
      }
      backup = {
        barmanObjectStore = {
          destinationPath = var.postgres_backup_s3_destination
          endpointURL     = "http://${var.minio_api_host}"
          s3Credentials = {
            accessKeyId = {
              name = "minio-credentials"
              key  = "accessKeyId"
            }
            secretAccessKey = {
              name = "minio-credentials"
              key  = "secretAccessKey"
            }
          }
        }
        retentionPolicy = "7d"
      }
    }
  }
}


resource "kubernetes_secret_v1" "minio_credentials" {
  metadata {
    name      = "minio-credentials"
    namespace = var.postgres_namespace
  }
  data = {
    accessKeyId     = var.minio_root_username
    secretAccessKey = var.minio_root_password
  }
}

resource "kubernetes_secret_v1" "postgres_owner_credentials" {
  metadata {
    name      = "postgres-credentials"
    namespace = var.postgres_namespace
  }
  data = {
    username = var.postgres_finanzwerk_owner_username
    password = var.postgres_finanzwerk_owner_password
  }
}

resource "kubernetes_secret_v1" "readonly_user" {
  metadata {
    name      = "readonly-user-secret"
    namespace = var.postgres_namespace
  }
  data = {
    username = var.postgres_finanzwerk_readonly_username
    password = var.postgres_finanzwerk_readonly_password
  }
}

resource "kubernetes_secret_v1" "readwrite_user" {
  metadata {
    name      = "readwrite-user-secret"
    namespace = var.postgres_namespace
  }
  data = {
    username = var.postgres_finanzwerk_readwrite_username
    password = var.postgres_finanzwerk_readwrite_password
  }
}


resource "kubernetes_job_v1" "grant_permissions" {
  depends_on = [kubernetes_manifest.postgres_cluster]
  metadata {
    name      = "grant-permissions"
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
            <<-EOT
              until psql "$CONNECTION_STRING" -c '\q' 2>/dev/null; do
                echo "Waiting for postgres..."
                sleep 3
              done

              psql "$CONNECTION_STRING" <<SQL
                -- readonly
                GRANT CONNECT ON DATABASE ${var.postgres_finanzwerk_db} TO ${var.postgres_finanzwerk_readonly_username};
                GRANT USAGE ON SCHEMA public TO ${var.postgres_finanzwerk_readonly_username};
                GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${var.postgres_finanzwerk_readonly_username};
                ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${var.postgres_finanzwerk_readonly_username};

                -- readwrite
                GRANT CONNECT ON DATABASE ${var.postgres_finanzwerk_db} TO ${var.postgres_finanzwerk_readwrite_username};
                GRANT USAGE ON SCHEMA public TO ${var.postgres_finanzwerk_readwrite_username};
                GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${var.postgres_finanzwerk_readwrite_username};
                ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${var.postgres_finanzwerk_readwrite_username};
              SQL
            EOT
          ]
          env {
            name  = "CONNECTION_STRING"
            value = "postgresql://${var.postgres_finanzwerk_owner_username}:$$(OWNER_PASSWORD)@postgres-rw:5432/${var.postgres_finanzwerk_db}"
          }
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
}

resource "kubernetes_manifest" "postgres_scheduled_backup" {
  depends_on = [kubernetes_manifest.postgres_cluster]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "ScheduledBackup"
    metadata = {
      name      = "postgres-daily-backup"
      namespace = var.postgres_namespace
    }
    spec = {
      schedule = "0 0 2 * * *" # every day at 2am (seconds minutes hours...)
      cluster = {
        name = "postgres"
      }
      backupOwnerReference = "cluster"
    }
  }
}
