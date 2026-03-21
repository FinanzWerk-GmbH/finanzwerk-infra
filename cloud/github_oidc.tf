resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com‍"]
}

data "aws_iam_policy_document" "github_oidc" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      values   = ["sts.amazonaws.com"]
      variable = "token.actions.githubusercontent.com:aud"
    }
    condition {
      test     = "StringLike"
      values   = ["repo:FinanzWerk-GmbH/*"]
      variable = "token.actions.githubusercontent.com:sub"
    }
  }
}

resource "aws_iam_role" "github_oidc" {
  name               = "github-oidc-role"
  assume_role_policy = data.aws_iam_policy_document.github_oidc.json
}

data "aws_iam_policy_document" "cicd_terraform" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cicd_terraform" {
  name   = "cicd-terraform"
  policy = data.aws_iam_policy_document.cicd_terraform.json
}

resource "aws_iam_role_policy_attachment" "cicd_terraform" {
  role       = aws_iam_role.github_oidc.name
  policy_arn = aws_iam_policy.cicd_terraform.arn
}

output "oidc_github_role_arn" {
  description = "The arn of the oidc github iam role"
  value       = aws_iam_role.github_oidc.arn
}
