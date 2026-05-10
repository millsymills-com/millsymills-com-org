terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.4"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.74"
    }
  }
}
