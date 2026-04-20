resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-harness-artifacts"
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter { prefix = "logs/" }
    expiration { days = 90 }
  }
}

resource "aws_s3_bucket" "lambda_packages" {
  bucket = "${var.project_name}-lambda-packages"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_packages" {
  bucket = aws_s3_bucket.lambda_packages.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_packages" {
  bucket                  = aws_s3_bucket.lambda_packages.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "lambda_dispatcher" {
  bucket = aws_s3_bucket.lambda_packages.id
  key    = "dispatcher/${data.archive_file.lambda_dispatcher.output_md5}.zip"
  source = data.archive_file.lambda_dispatcher.output_path
  etag   = data.archive_file.lambda_dispatcher.output_md5
}
