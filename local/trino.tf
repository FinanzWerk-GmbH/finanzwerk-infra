resource "helm_release" "trino" {
  depends_on = [kubernetes_namespace_v1.data_tools_namespace]
  name       = "trino"
  repository = "https://trinodb.github.io/charts"
  chart      = "trino"
  namespace  = "data-tools"

  values = [<<-EOT
    coordinator:
      resources:
        requests:
          memory: 1Gi
          cpu: 500m

    worker:
      replicas: 0

    additionalCatalogs:
      postgresql: |
        connector.name=postgresql
        connection-url=jdbc:postgresql://postgres-rw.${var.postgres_namespace}.svc.cluster.local:5432/${var.postgres_finanzwerk_db}
        connection-user=${var.postgres_finanzwerk_readwrite_username}
        connection-password=${var.postgres_finanzwerk_readwrite_password}

      iceberg: |
        connector.name=iceberg
        iceberg.catalog.type=nessie
        iceberg.nessie.uri=http://nessie.data-tools.svc.cluster.local:19120/api/v1
        iceberg.nessie.ref=main
        fs.native-s3.enabled=true
        s3.endpoint=http://minio.${var.minio_namespace}.svc.cluster.local:9000
        s3.aws-access-key-id=${var.minio_root_username}
        s3.aws-secret-access-key=${var.minio_root_password}
        s3.path-style-access=true
        s3.ssl.enabled=false
    EOT
  ]
}

resource "kubernetes_ingress_v1" "trino_ingress" {
  depends_on = [helm_release.trino]
  metadata {
    name      = "trino"
    namespace = "data-tools"
  }
  spec {
    ingress_class_name = var.nginx_ingress_classname
    rule {
      host = "trino.127.0.0.1.nip.io"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "trino"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
