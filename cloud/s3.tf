resource "aws_s3_bucket" "raw_ingestion_data" {
  bucket = "finanzwerk-raw-ingestion-data"
}

resource "aws_s3_bucket_versioning" "raw_ingestion_data" {
  bucket = aws_s3_bucket.raw_ingestion_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_ingestion_data" {
  bucket = aws_s3_bucket.raw_ingestion_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


resource "aws_s3_bucket" "processed_data" {
  bucket = "finanzwerk-processed-data"
}


resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
