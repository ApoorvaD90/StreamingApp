terraform {
  # Pinned: laptop and Jenkins must run the same version, or one cannot read the S3 state the other wrote
  required_version = "= 1.15.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "streamingapp-tfstate"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "streamingapp-tflock"
  }
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "StreamingApp"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
