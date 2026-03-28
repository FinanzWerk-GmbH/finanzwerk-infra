resource "helm_release" "minio" {
  depends_on = [kubernetes_namespace_v1.minio_namespace]
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  namespace  = var.minio_namespace
  set = [
    {
      name  = "rootUser",
      value = var.minio_root_username
    },
    {
      name  = "rootPassword",
      value = var.minio_root_password
    },
    {
      name  = "replicas",
      value = 3
    },
    {
      name  = "resources.requests.memory",
      value = "256Mi"
    },
    {
      name  = "consoleIngress.enabled",
      value = "true"
    },
    {
      name  = "consoleIngress.ingressClassName",
      value = var.nginx_ingress_classname
    },
    {
      name  = "persistence.storageClass",
      value = var.minikube_storage_class
    },
    {
      name  = "persistence.size",
      value = "2Gi"
    },
  ]
  set_list = [
    {
      name  = "consoleIngress.hosts",
      value = [var.minio_console_ingress_host]
    }
  ]
}


resource "kubernetes_job_v1" "create_initital_minikube_buckets" {
  depends_on = [helm_release.minio]
  metadata {
    name      = "initial-minikube-buckets"
    namespace = var.minio_namespace
  }
  spec {
    template {
      metadata {}
      spec {
        container {
          name  = "create-buckets"
          image = "minio/mc"
          command = ["/bin/sh", "-c",
            <<-EOT
                    until mc alias set finanzwerk $MINIO_ENDPOINT $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD; do
                      echo "Waiting for MinIO..."
                      sleep 3
                    done
                    ${join("\n  ", [for b in var.minio_initial_buckets : "mc mb --ignore-existing finanzwerk/${b}"])}
            EOT
          ]
          env {
            name  = "MINIO_ENDPOINT"
            value = "http://${var.minio_api_endpoint}"
          }
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
