terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block: state is stored locally in terraform.tfstate
  # (gitignored). Migrate to a remote backend later if this ever needs
  # multiple contributors or CI access.
}

provider "aws" {
  region = var.region
}

module "ec2_app" {
  source = "../../modules/ec2_app"

  name            = "beento-prod"
  instance_type   = var.instance_type
  ami_id          = var.ami_id
  ssh_public_keys = var.ssh_public_keys
  app_ports       = var.app_ports
}
