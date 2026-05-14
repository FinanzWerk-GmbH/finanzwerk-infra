resource "helm_release" "clickhouse" {
  name             = "clickhouse"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "clickhouse"
  version          = "5.2.1"
  namespace        = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 600

  values = [<<-EOT
    replicaCount: 1
    shards: 1
    auth:
      username: admin
      password: ${var.clickhouse_admin_password}
    persistence:
      size: 5Gi
    resources:
      requests:
        memory: 512Mi
        cpu: 250m
      limits:
        memory: 2Gi
        cpu: 1000m
    zookeeper:
      enabled: false
  EOT
  ]
}

resource "kubernetes_ingress_v1" "clickhouse_http" {
  metadata {
    name      = "clickhouse-http"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = "nginx"
    rule {
      host = "clickhouse.127.0.0.1.nip.io"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "clickhouse"
              port {
                number = 8123
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.clickhouse]
}
