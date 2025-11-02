terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
  }

  backend "s3" {
    bucket         = "aws-terraform-state-bucket-devops"
    key            = "aws-k8s-cluster/terraform.tfstate"
    region         = "eu-north-1" # Variables not allowed in backend block
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

