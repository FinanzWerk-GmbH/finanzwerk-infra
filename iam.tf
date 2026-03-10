resource "aws_iam_role" "read_only" {
  name               = "read-only"
  assume_role_policy = data.aws_iam_policy_document.read_only_assume_role.json
}

data "aws_iam_policy_document" "read_only_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["some-user"]
    }
  }
}

data "aws_iam_policy" "read_only" {
  arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.read_only.name
  policy_arn = data.aws_iam_policy.read_only.arn
}



resource "aws_iam_role" "data_pipeline" {
  name               = "data-pipeline"
  assume_role_policy = data.aws_iam_policy_document.data_pipeline_assume_role.json
}

data "aws_iam_policy_document" "data_pipeline_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "data_pipeline" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
    resources = [aws_s3_bucket.processed_data.arn, aws_s3_bucket.raw_ingestion_data.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["#TODO"]
  }
}

resource "aws_iam_policy" "data_pipeline" {
  name   = "data-pipeline-permissions"
  policy = data.aws_iam_policy_document.data_pipeline.json
}

resource "aws_iam_role_policy_attachment" "data_pipeline" {
  role       = aws_iam_role.data_pipeline.name
  policy_arn = aws_iam_policy.data_pipeline.arn
}
