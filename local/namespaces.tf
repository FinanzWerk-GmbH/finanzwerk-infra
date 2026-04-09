resource "kubernetes_namespace_v1" "data_core_namespace" {
  metadata {
    name = var.data_core_namespace
  }
}
resource "kubernetes_namespace_v1" "postgres_namespace" {
  metadata {
    name = var.postgres_namespace
  }
}
resource "kubernetes_namespace_v1" "minio_namespace" {
  metadata {
    name = var.minio_namespace
  }
}
resource "kubernetes_namespace_v1" "vault_namespace" {
  metadata {
    name = var.vault_namespace
  }
}
resource "kubernetes_namespace_v1" "airflow_namespace" {
  metadata {
    name = var.airflow_namespace
  }
}
