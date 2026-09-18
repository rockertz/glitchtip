terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # S3 backend for remote state management
  backend "s3" {
    bucket  = "adisoc-vpn-terraform-state"
    key     = "glitchtip/terraform.tfstate"
    region  = "ap-southeast-1"
    profile = "adisoc"
  }
}

