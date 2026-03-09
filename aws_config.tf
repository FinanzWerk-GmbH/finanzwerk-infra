resource "aws_s3_bucket" "config_log_storage" {
  bucket = "finanzwerk-config-log-storage"
}

resource "aws_s3_bucket_versioning" "config_log_storage" {
  bucket = aws_s3_bucket.config_log_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_log_storage" {
  bucket = aws_s3_bucket.config_log_storage.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_config_configuration_recorder" "main" {
  name     = "main"
  role_arn = aws_iam_role.config.arn
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}


resource "aws_config_delivery_channel" "main" {
  name           = "main"
  s3_bucket_name = aws_s3_bucket.config_log_storage.bucket
  depends_on     = [aws_config_configuration_recorder.main]
}


resource "aws_iam_role" "config" {
  name               = "aws_config_iam_role"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json
}


data "aws_iam_policy_document" "config_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}


resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config_log_storage.id
  policy = data.aws_iam_policy_document.config_log_bucket_policy.json
}

data "aws_iam_policy_document" "config_log_bucket_policy" {
  statement {
    sid    = "AllowConfigBucketAccess"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config_log_storage.arn]
  }
  statement {
    sid    = "AllowConfigBucketDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config_log_storage.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}


resource "aws_config_config_rule" "s3_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder.main]
}
