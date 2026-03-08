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
  tags = {
    "Name" = "main_vpc"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = {
    "Name" = "priv_subnet"
  }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  tags = {
    "Name" = "pub_subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    "Name" = "public_route_table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "main_internet_gateway"
  }
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = {
    "Name" = "private_route_table"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_nat_gateway" "main" {
  subnet_id     = aws_subnet.public.id
  allocation_id = aws_eip.nat_gateway.id
  tags = {
    "Name" = "main_nat_gateway"
  }
}

resource "aws_eip" "nat_gateway" {
  tags = {
    "Name" = "nat_gateway_eip"
  }
}


resource "aws_s3_bucket" "log_storage" {
  bucket = "log_storage"
  tags = {
    Name = "Log Storage"
  }
}

resource "aws_s3_bucket_versioning" "log_storage" {
  bucket = aws_s3_bucket.log_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_storage" {
  bucket = aws_s3_bucket.log_storage.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


resource "aws_cloudtrail" "main" {
  name                  = "main"
  s3_bucket_name        = aws_s3_bucket.log_storage.id
  is_multi_region_trail = true
  tags = {
    "Name" = "Main Cloudtrail"
  }
}
