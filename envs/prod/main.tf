terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Fill these in after running `bootstrap/` once, then run `terraform init`.
  # backend "s3" {
  #   bucket         = "<state_bucket_name from bootstrap output>"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "<lock_table_name from bootstrap output>"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
}

module "ec2_app" {
  source = "../../modules/ec2_app"

  name            = "beento-prod"
  instance_type   = var.instance_type
  ssh_public_keys = var.ssh_public_keys
  app_ports       = var.app_ports
}
