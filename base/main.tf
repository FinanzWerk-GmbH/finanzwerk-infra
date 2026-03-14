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
