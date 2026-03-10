resource "aws_iam_openid_connect_provider" "default" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com‍"]
}

data "aws_iam_policy_document" "oicd" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.default.arn]
    }
    condition {
      test     = "StringEquals"
      values   = ["sts.amazon.com"]
      variable = "token.actions.githubusercontent.com:aud"
    }
    condition {
      test     = ["StringLike"]
      values   = ["repo:FinanzWerk-GmbH/*"]
      variable = "token.actions.githubusercontent.com:sub"
    }
  }
}

resource "aws_iam_role" "github_oicd" {
  name               = "github-oicd-role"
  assume_role_policy = data.aws_iam_policy_document.oicd.json
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
  role       = aws_iam_role.github_oicd.name
  policy_arn = aws_iam_policy.cicd_terraform.arn
}

output "oicd_github_role_arn" {
  description = "The arn of the oicd github iam role"
  value       = aws_iam_role.github_oicd.arn
}
