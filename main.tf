terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.41.0"
    }
  }
  required_version = ">= 1.4"
}

provider "aws" {
  region  = "us-east-1"
  profile = "dev"
  default_tags {
    tags = {
      "org" = "finanzwerk"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_nat_gateway" "main" {
  subnet_id     = aws_subnet.public.id
  allocation_id = aws_eip.nat_gateway.id
}

resource "aws_eip" "nat_gateway" {
}


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
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.cloudtrail_log_storage.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_cloudtrail" "main" {
  name                  = "main"
  s3_bucket_name        = aws_s3_bucket.cloudtrail_log_storage.id
  is_multi_region_trail = true
}


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


resource "aws_config_config_rule" "s3_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder.main]
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
