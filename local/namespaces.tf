resource "kubernetes_namespace_v1" "namespaces" {
  metadata {
    name = var.data_core_namespace
  }
}
