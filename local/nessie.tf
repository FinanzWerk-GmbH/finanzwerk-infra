resource "kubernetes_namespace_v1" "data_tools_namespace" {
  metadata {
    name = "data-tools"
  }
}

resource "helm_release" "nessie" {
  depends_on = [kubernetes_namespace_v1.data_tools_namespace]
  name       = "nessie"
  repository = "https://charts.projectnessie.org"
  chart      = "nessie"
  namespace  = "data-tools"

  values = [<<-EOT
    versionStoreType: IN_MEMORY
    EOT
  ]
}

resource "kubernetes_ingress_v1" "nessie_ingress" {
  depends_on = [helm_release.nessie]
  metadata {
    name      = "nessie"
    namespace = "data-tools"
  }
  spec {
    ingress_class_name = var.nginx_ingress_classname
    rule {
      host = "nessie.127.0.0.1.nip.io"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "nessie"
              port {
                number = 19120
              }
            }
          }
        }
      }
    }
  }
}
