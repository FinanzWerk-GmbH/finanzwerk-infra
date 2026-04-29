resource "helm_release" "redpanda" {
  name             = "redpanda"
  repository       = "https://charts.redpanda.com/"
  chart            = "redpanda"
  version          = "5.8.14"
  namespace        = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 600

  values = [<<-EOT
    statefulset:
      replicas: 1
    config:
      cluster:
        auto_create_topics_enabled: false
    resources:
      cpu:
        cores: 1
      memory:
        container:
          max: 1500Mi
    tls:
      enabled: false
    auth:
      sasl:
        enabled: false
    storage:
      persistentVolume:
        size: 5Gi
    console:
      enabled: true
    external:
      enabled: false
  EOT
  ]
}

resource "kubernetes_secret_v1" "streaming_minio_credentials" {
  metadata {
    name      = "streaming-minio-credentials"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
  data = {
    access_key = var.minio_root_username
    secret_key = var.minio_root_password
  }
}

resource "kubernetes_job_v1" "redpanda_topics" {
  metadata {
    name      = "redpanda-create-topics"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "rpk"
          image = "docker.redpanda.com/redpandadata/redpanda:v23.2.1"
          command = [
            "bash", "-c",
            <<-EOT
              BROKERS="redpanda.${kubernetes_namespace_v1.data_tools_namespace.metadata[0].name}.svc.cluster.local:9093"
              rpk topic create ict-events-raw       -X brokers=$BROKERS -p 3 -r 1 -c retention.ms=604800000
              rpk topic create ict-events-classified -X brokers=$BROKERS -p 3 -r 1 -c retention.ms=604800000
              rpk topic create ict-alerts            -X brokers=$BROKERS -p 1 -r 1 -c retention.ms=2592000000
              rpk topic create cdc.public.ict_incidents -X brokers=$BROKERS -p 3 -r 1 -c retention.ms=2592000000
              rpk topic create cdc.public.vendors    -X brokers=$BROKERS -p 1 -r 1 -c retention.ms=2592000000
              rpk topic create debezium.configs      -X brokers=$BROKERS -p 1 -r 1
              rpk topic create debezium.offsets      -X brokers=$BROKERS -p 25 -r 1
              rpk topic create debezium.status       -X brokers=$BROKERS -p 5 -r 1
            EOT
          ]
        }
      }
    }
    backoff_limit = 5
  }
  depends_on = [helm_release.redpanda]
}

resource "kubernetes_ingress_v1" "redpanda_console" {
  metadata {
    name      = "redpanda-console"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = "nginx"
    rule {
      host = "redpanda.127.0.0.1.nip.io"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "redpanda-console"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.redpanda]
}
