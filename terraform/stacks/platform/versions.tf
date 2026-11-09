terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.75"
    }
  }

  # Partial config: `terraform init -backend-config=backend.hcl` (see backend.hcl.example).
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "shared"
      Stack       = "platform"
      ManagedBy   = "terraform"
      Repository  = "Delivery-Plus0/delivery-plus-infra"
    }
  }
}
