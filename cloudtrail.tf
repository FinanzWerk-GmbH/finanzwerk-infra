
resource "aws_s3_bucket" "cloudtrail_log_storage" {
  bucket = "finanzwerk-cloudtrail-log-storage"
}

resource "aws_s3_bucket_versioning" "cloudtrail_log_storage" {
  bucket = aws_s3_bucket.cloudtrail_log_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_log_storage" {
  bucket = aws_s3_bucket.cloudtrail_log_storage.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_s3_log_storage" {
  bucket = aws_s3_bucket.cloudtrail_log_storage.id
  policy = data.aws_iam_policy_document.cloudtrail_s3_log_storage_policy.json
}

data "aws_iam_policy_document" "cloudtrail_s3_log_storage_policy" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.cloudtrail_log_storage.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/main"]
    }
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.cloudtrail_log_storage.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/main"]
    }
  }
}

resource "aws_cloudtrail" "main" {
  name                  = "main"
  s3_bucket_name        = aws_s3_bucket.cloudtrail_log_storage.id
  is_multi_region_trail = true
  depends_on            = [aws_s3_bucket_policy.cloudtrail_s3_log_storage]
}
