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
      variable = "${module.eks.cluster_oidc_issuer_url}:sub"
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
      variable = "${module.eks.cluster_oidc_issuer_url}:sub"
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

  values = [
    yamlencode({
      executor = "KubernetesExecutor"
      workers = {
        serviceAccount = {
          create = false
          name   = kubernetes_service_account.airflow_worker.metadata[0].name
        }
      }
    })
  ]
}

# ── Helm: Spark operator ───────────────────────────────────────────────────────

resource "helm_release" "spark_operator" {
  name       = "spark-operator"
  repository = "https://kubeflow.github.io/spark-operator"
  chart      = "spark-operator"
  version    = "2.5.0"
  namespace  = kubernetes_namespace.spark.metadata[0].name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", "dev"]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", "dev"]
    }
  }
}
