module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "example"
  kubernetes_version = "1.33"

  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}


# IRSA: Airflow workers — read from raw ingestion bucket
resource "aws_iam_role" "airflow_worker" {
  name               = "airflow-worker"
  assume_role_policy = data.aws_iam_policy_document.airflow_worker_trust.json
}

data "aws_iam_policy_document" "airflow_worker_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:airflow:airflow-worker"]
    }
  }
}

data "aws_iam_policy_document" "airflow_worker_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "airflow_worker" {
  name   = "airflow-worker-permissions"
  policy = data.aws_iam_policy_document.airflow_worker_permissions.json
}

resource "aws_iam_role_policy_attachment" "airflow_worker" {
  role       = aws_iam_role.airflow_worker.name
  policy_arn = aws_iam_policy.airflow_worker.arn
}

# IRSA: Spark jobs — write to processed data bucket
resource "aws_iam_role" "spark" {
  name               = "spark"
  assume_role_policy = data.aws_iam_policy_document.spark_trust.json
}

data "aws_iam_policy_document" "spark_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:spark:spark"]
    }
  }
}

data "aws_iam_policy_document" "spark_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "spark" {
  name   = "spark-permissions"
  policy = data.aws_iam_policy_document.spark_permissions.json
}

resource "aws_iam_role_policy_attachment" "spark" {
  role       = aws_iam_role.spark.name
  policy_arn = aws_iam_policy.spark.arn
}

output "airflow_worker_role_arn" {
  value = aws_iam_role.airflow_worker.arn
}

output "spark_role_arn" {
  value = aws_iam_role.spark.arn
}

# ── Storage ───────────────────────────────────────────────────────────────────

resource "kubernetes_storage_class_v1" "ebs_csi" {
  metadata {
    name = "ebs-csi"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.eks.amazonaws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type = "gp3"
  }
}

# ── Airflow secrets ───────────────────────────────────────────────────────────

resource "random_password" "airflow_db" {
  length  = 32
  special = false
}

resource "random_bytes" "airflow_fernet_key" {
  length = 32
}

locals {
  # Fernet requires URL-safe base64 (- and _ instead of + and /)
  airflow_fernet_key = replace(replace(random_bytes.airflow_fernet_key.base64, "+", "-"), "/", "_")
}

resource "kubernetes_secret" "airflow_metadata" {
  metadata {
    name      = "airflow-metadata-secret"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  data = {
    connection = "postgresql+psycopg2://db_admin:${random_password.airflow_db.result}@${module.rds_postgres_operational_data_warehouse.db_instance_address}:5432/postgres"
  }
}

resource "kubernetes_secret" "airflow_fernet_key" {
  metadata {
    name      = "airflow-fernet-key"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  data = {
    fernet-key = local.airflow_fernet_key
  }
}

# ── Namespaces ────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "airflow" {
  metadata { name = "airflow" }
}

resource "kubernetes_namespace" "spark" {
  metadata { name = "spark" }
}

resource "kubernetes_namespace" "data_tools" {
  metadata { name = "data-tools" }
}

# ── Service Accounts (IRSA-annotated) ─────────────────────────────────────────

resource "kubernetes_service_account" "airflow_worker" {
  metadata {
    name      = "airflow-worker"
    namespace = kubernetes_namespace.airflow.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.airflow_worker.arn
    }
  }
}

resource "kubernetes_service_account" "spark" {
  metadata {
    name      = "spark"
    namespace = kubernetes_namespace.spark.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.spark.arn
    }
  }
}

# ── RBAC: airflow — scheduler needs pod management for KubernetesExecutor ─────

resource "kubernetes_role" "airflow_scheduler" {
  metadata {
    name      = "airflow-scheduler"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["list", "watch"]
  }
}

resource "kubernetes_role_binding" "airflow_scheduler" {
  metadata {
    name      = "airflow-scheduler"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.airflow_scheduler.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.airflow_worker.metadata[0].name
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }
}

# ── RBAC: spark — driver pod needs to create executor pods ────────────────────

resource "kubernetes_role" "spark_driver" {
  metadata {
    name      = "spark-driver"
    namespace = kubernetes_namespace.spark.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch"]
  }
}

resource "kubernetes_role_binding" "spark_driver" {
  metadata {
    name      = "spark-driver"
    namespace = kubernetes_namespace.spark.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.spark_driver.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.spark.metadata[0].name
    namespace = kubernetes_namespace.spark.metadata[0].name
  }
}

# ── RBAC: data-tools — general developer access ────────────────────────────────

resource "kubernetes_role" "data_tools_developer" {
  metadata {
    name      = "developer"
    namespace = kubernetes_namespace.data_tools.metadata[0].name
  }
  rule {
    api_groups = ["", "apps", "batch"]
    resources  = ["pods", "deployments", "jobs", "services", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

# ── Helm: Airflow ──────────────────────────────────────────────────────────────

resource "helm_release" "airflow" {
  name       = "airflow"
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  version    = "1.21.0"
  namespace  = kubernetes_namespace.airflow.metadata[0].name
  wait             = true
  timeout          = 600
  force_update     = true
  cleanup_on_fail  = true

  values = [
    templatefile("${path.module}/airflow-values.yaml.tpl", {
      worker_sa_name   = kubernetes_service_account.airflow_worker.metadata[0].name
      airflow_dag_repo = var.airflow_dag_repo
    })
  ]

  depends_on = [helm_release.aws_lbc]
}

# ── Helm: Spark operator ───────────────────────────────────────────────────────

resource "helm_release" "spark_operator" {
  name       = "spark-operator"
  repository = "https://kubeflow.github.io/spark-operator"
  chart      = "spark-operator"
  version    = "2.5.0"
  namespace  = kubernetes_namespace.spark.metadata[0].name

  depends_on = [helm_release.aws_lbc]
}

# ── AWS Load Balancer Controller ───────────────────────────────────────────────

resource "aws_iam_role" "aws_lbc" {
  name               = "aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_lbc_trust.json
}

data "aws_iam_policy_document" "aws_lbc_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

data "aws_iam_policy_document" "aws_lbc_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "aws_lbc" {
  name   = "aws-load-balancer-controller-permissions"
  policy = data.aws_iam_policy_document.aws_lbc_permissions.json
}

resource "aws_iam_role_policy_attachment" "aws_lbc" {
  role       = aws_iam_role.aws_lbc.name
  policy_arn = aws_iam_policy.aws_lbc.arn
}

resource "kubernetes_service_account" "aws_lbc" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lbc.arn
    }
  }
}

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.3.0"
  namespace  = "kube-system"

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      serviceAccount = {
        create = false
        name   = kubernetes_service_account.aws_lbc.metadata[0].name
      }
      vpcId  = aws_vpc.main.id
      region = data.aws_region.current.name
    })
  ]

  wait       = true
  depends_on = [kubernetes_service_account.aws_lbc]
}

# ── Ingress: Airflow ───────────────────────────────────────────────────────────

resource "kubernetes_ingress_v1" "airflow" {
  metadata {
    name      = "airflow"
    namespace = kubernetes_namespace.airflow.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/subnets"     = "${aws_subnet.public_a.id},${aws_subnet.public_b.id}"
    }
  }
  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "airflow-api-server"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.aws_lbc]
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}
