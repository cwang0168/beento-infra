terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "app" {
  name        = "${var.name}-sg"
  description = "Security group for ${var.name}"
  vpc_id      = data.aws_vpc.default.id

  # SSH is intentionally open to the entire internet: this setup has no
  # bastion host or VPN, so 0.0.0.0/0 is how anyone actually reaches the box.
  # This is a deliberate design choice (not an oversight) made with the user
  # during design — see docs/superpowers/specs/2026-07-26-terraform-aws-setup-design.md.
  # Access control relies entirely on key-based auth (password auth is not
  # configured) and on which public keys are listed in var.ssh_public_keys.
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.app_ports
    content {
      description = "App port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_instance" "app" {
  ami                    = coalesce(var.ami_id, data.aws_ami.amazon_linux_2023.id)
  instance_type          = var.instance_type
  subnet_id              = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    ssh_public_keys = var.ssh_public_keys
  })

  # cloud-init's user-data script only runs once per instance, on first boot.
  # Without this, changing ssh_public_keys (or anything else baked into
  # user_data) causes Terraform to do an in-place Stop/Modify/Start of the
  # existing instance instead of replacing it — the new keys are never
  # actually installed, even though Terraform reports success. Forcing
  # replacement on user_data change makes cloud-init actually re-run with the
  # updated key list.
  user_data_replace_on_change = true

  tags = {
    Name = var.name
  }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.name}-eip"
  }
}
