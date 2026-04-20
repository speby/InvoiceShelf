#!/bin/bash
# Creates the S3 bucket and DynamoDB table that Terraform uses as its remote backend.
# Run this ONCE before `terraform init`. Idempotent — safe to re-run.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="invoiceshelf-terraform-state"
TABLE_NAME="invoiceshelf-terraform-locks"

echo "==> Bootstrapping Terraform backend in $AWS_REGION"
echo "    Bucket : $BUCKET_NAME"
echo "    Table  : $TABLE_NAME"
echo ""

# ── S3 bucket ────────────────────────────────────────────────────────────────
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "[skip] Bucket $BUCKET_NAME already exists"
else
  echo "[create] S3 bucket $BUCKET_NAME"
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
  fi
fi

echo "[config] Enabling versioning on $BUCKET_NAME"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "[config] Enabling AES-256 encryption on $BUCKET_NAME"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
      "BucketKeyEnabled": true
    }]
  }'

echo "[config] Blocking public access on $BUCKET_NAME"
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# ── DynamoDB table ───────────────────────────────────────────────────────────
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" 2>/dev/null; then
  echo "[skip] DynamoDB table $TABLE_NAME already exists"
else
  echo "[create] DynamoDB table $TABLE_NAME"
  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"

  echo "[wait] Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$AWS_REGION"
fi

echo ""
echo "==> Backend ready. Now run:"
echo "    cd infrastructure/terraform"
echo "    terraform init"
