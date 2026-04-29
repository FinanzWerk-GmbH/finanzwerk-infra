resource "helm_release" "spark_operator" {
  name             = "spark-operator"
  repository       = "https://kubeflow.github.io/spark-operator"
  chart            = "spark-operator"
  version          = "1.1.27"
  namespace        = "spark-operator"
  create_namespace = true
  wait             = true

  values = [<<-EOT
    sparkJobNamespace: data-tools
    webhook:
      enable: true
    metrics:
      enable: false
  EOT
  ]
}

resource "kubernetes_service_account_v1" "spark_driver" {
  metadata {
    name      = "spark-driver"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding_v1" "spark_driver" {
  metadata {
    name = "spark-driver-role-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "spark-driver"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
}

resource "kubernetes_secret_v1" "spark_minio_credentials" {
  metadata {
    name      = "spark-minio-credentials"
    namespace = kubernetes_namespace_v1.data_tools_namespace.metadata[0].name
  }
  data = {
    accessKeyId     = var.minio_root_username
    secretAccessKey = var.minio_root_password
  }
}
