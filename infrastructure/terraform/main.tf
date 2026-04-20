terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "invoiceshelf-terraform-state"
    key            = "claude-harness/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "invoiceshelf-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "InvoiceShelf"
      Component = "ClaudeHarness"
      ManagedBy = "Terraform"
    }
  }
}
