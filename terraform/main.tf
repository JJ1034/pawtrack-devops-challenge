terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # The state bucket and lock table must be bootstrapped out-of-band.
  # See bootstrap notes in DECISIONS.md.
  backend "s3" {
    bucket         = "pawtrack-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "pawtrack-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "pawtrack"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
