# Terraform AWS Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a single-environment (`prod`) Terraform configuration that provisions one Docker-capable EC2 instance in the default VPC, reachable via SSH by multiple people using a shared OS user, with remote state in S3.

**Architecture:** A one-time `bootstrap/` root module creates the S3 state bucket + DynamoDB lock table using local state. A reusable `modules/ec2_app` module encapsulates the security group, EC2 instance, Elastic IP, and cloud-init user-data (Docker install + multi-key SSH). An `envs/prod` root module wires the module together with an S3 backend and prod-specific variables.

**Tech Stack:** Terraform >= 1.5.0, AWS provider `~> 5.0`, target region `us-east-1`, Amazon Linux 2023, cloud-init (`user_data`) for bootstrapping the instance.

## Global Constraints

- Terraform version: `>= 1.5.0` (local install is 1.10.3 — confirmed compatible)
- AWS provider version: `~> 5.0`
- Region: `us-east-1`
- Single environment only: `prod` (no dev/staging)
- No database, no domain/TLS, no autoscaling — out of scope per spec
- SSH: shared `ec2-user`, multiple public keys via `authorized_keys`, security group open to `0.0.0.0/0` on port 22
- Networking: AWS account's default VPC (no VPC module)
- `terraform.tfvars` must never be committed (gitignored); `terraform.tfvars.example` is committed
- All `.tf` files must pass `terraform fmt -check -recursive`
- `terraform plan`/`apply` require valid AWS credentials, which were confirmed **not currently valid** in this environment (`aws sts get-caller-identity` returned `InvalidClientTokenId`). Every task's testing step uses `terraform validate` (no AWS API calls) as the pass/fail gate. `terraform plan` is documented as a manual step to run once credentials are fixed — it is not a blocking gate in these tasks.

---

### Task 1: Repo scaffolding

**Files:**
- Create: `.gitignore`

**Interfaces:**
- Produces: gitignore rules that all later tasks rely on to avoid committing `.terraform/`, state files, and real `terraform.tfvars`.

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Real variable files (keep .example committed)
terraform.tfvars
*.auto.tfvars
!*.tfvars.example
```

- [ ] **Step 2: Verify git respects it**

Run: `cd /Users/charleswang/projects/beento/beento-infra && git check-ignore -v .terraform/foo 2>&1; git check-ignore -v terraform.tfvars 2>&1`
Expected: both lines print a match against `.gitignore` (e.g. `.gitignore:2:**/.terraform/*	.terraform/foo`)

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "Add gitignore for Terraform state and local var files"
```

---

### Task 2: Bootstrap — remote state backend

**Files:**
- Create: `bootstrap/main.tf`
- Create: `bootstrap/variables.tf`
- Create: `bootstrap/outputs.tf`
- Create: `bootstrap/README.md`

**Interfaces:**
- Produces: an S3 bucket and DynamoDB table whose names (chosen by the operator via `-var` at apply time) get manually copied into `envs/prod/main.tf`'s `backend "s3"` block in Task 4.

- [ ] **Step 1: Write `bootstrap/main.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

- [ ] **Step 2: Write `bootstrap/variables.tf`**

```hcl
variable "region" {
  description = "AWS region to create the state bucket and lock table in"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "beento-infra-terraform-locks"
}
```

- [ ] **Step 3: Write `bootstrap/outputs.tf`**

```hcl
output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking"
  value       = aws_dynamodb_table.terraform_lock.name
}
```

- [ ] **Step 4: Write `bootstrap/README.md`**

```markdown
# Bootstrap

Run this once, manually, before anything in `envs/`. It creates the S3 bucket
and DynamoDB table that `envs/prod` uses as its remote state backend. It uses
**local** state itself (chicken-and-egg problem: the backend can't store its
own creation state).

## Usage

    cd bootstrap
    terraform init
    terraform apply -var="state_bucket_name=<your-globally-unique-bucket-name>"

Copy the `state_bucket_name` and `lock_table_name` outputs into the
`backend "s3"` block in `envs/prod/main.tf`, then run `terraform init` there.

This only needs to be run once per AWS account. Keep `bootstrap/terraform.tfstate`
safe (it is local state, not backed up anywhere by this setup).
```

- [ ] **Step 5: Format and validate**

Run: `cd /Users/charleswang/projects/beento/beento-infra/bootstrap && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `fmt` prints nothing (already canonical); `init` succeeds (downloads the `aws` provider); `validate` prints `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
cd /Users/charleswang/projects/beento/beento-infra
git add bootstrap/
git commit -m "Add bootstrap module for Terraform remote state backend"
```

---

### Task 3: `modules/ec2_app` — security group, instance, EIP, user-data

**Files:**
- Create: `modules/ec2_app/main.tf`
- Create: `modules/ec2_app/variables.tf`
- Create: `modules/ec2_app/outputs.tf`
- Create: `modules/ec2_app/user_data.sh.tpl`

**Interfaces:**
- Consumes: nothing from other tasks (self-contained module).
- Produces (for Task 4 to consume as `module.ec2_app.*`):
  - Input variables: `name` (string, default `"beento-app"`), `instance_type` (string, default `"t3.micro"`), `ami_id` (string, default `null`), `ssh_public_keys` (list(string), required, min length 1), `app_ports` (list(number), default `[]`)
  - Outputs: `public_ip` (string), `instance_id` (string)

- [ ] **Step 1: Write `modules/ec2_app/variables.tf`**

```hcl
variable "name" {
  description = "Name prefix used to tag resources"
  type        = string
  default     = "beento-app"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID to launch. If null, defaults to the latest Amazon Linux 2023 AMI."
  type        = string
  default     = null
}

variable "ssh_public_keys" {
  description = "List of SSH public keys authorized to log in as ec2-user"
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "At least one SSH public key must be provided."
  }
}

variable "app_ports" {
  description = "List of additional TCP ports to open to 0.0.0.0/0 for the application"
  type        = list(number)
  default     = []
}
```

- [ ] **Step 2: Write `modules/ec2_app/user_data.sh.tpl`**

```bash
#!/bin/bash
set -euo pipefail

dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh
touch /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/authorized_keys

%{ for key in ssh_public_keys ~}
echo "${key}" >> /home/ec2-user/.ssh/authorized_keys
%{ endfor ~}

chown -R ec2-user:ec2-user /home/ec2-user/.ssh
```

- [ ] **Step 3: Write `modules/ec2_app/main.tf`**

```hcl
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
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
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
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    ssh_public_keys = var.ssh_public_keys
  })

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
```

Note: there is deliberately no `aws_key_pair`/`key_name` on the instance — SSH auth is handled entirely by the `authorized_keys` lines the user-data script writes, for every key in `ssh_public_keys`. Adding an AWS key pair would only support one key and isn't needed.

- [ ] **Step 4: Write `modules/ec2_app/outputs.tf`**

```hcl
output "public_ip" {
  description = "Stable public IP (Elastic IP) of the instance"
  value       = aws_eip.app.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}
```

- [ ] **Step 5: Format and validate**

Run: `cd /Users/charleswang/projects/beento/beento-infra/modules/ec2_app && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `fmt` prints nothing; `init` succeeds; `validate` prints `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
cd /Users/charleswang/projects/beento/beento-infra
git add modules/ec2_app/
git commit -m "Add ec2_app module: security group, instance, EIP, multi-key SSH user-data"
```

---

### Task 4: `envs/prod` — wire up the module with S3 backend

**Files:**
- Create: `envs/prod/main.tf`
- Create: `envs/prod/variables.tf`
- Create: `envs/prod/outputs.tf`
- Create: `envs/prod/terraform.tfvars.example`
- Create: `envs/prod/README.md`

**Interfaces:**
- Consumes: `modules/ec2_app` from Task 3 — variables `name`, `instance_type`, `ssh_public_keys`, `app_ports`; outputs `public_ip`, `instance_id`.
- Produces: root-level outputs `public_ip`, `instance_id` for the prod environment.

- [ ] **Step 1: Write `envs/prod/main.tf`**

```hcl
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
```

- [ ] **Step 2: Write `envs/prod/variables.tf`**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for the app instance"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_keys" {
  description = "List of SSH public keys authorized to log in as ec2-user"
  type        = list(string)
}

variable "app_ports" {
  description = "List of additional TCP ports to open to 0.0.0.0/0 for the application"
  type        = list(number)
  default     = []
}
```

- [ ] **Step 3: Write `envs/prod/outputs.tf`**

```hcl
output "public_ip" {
  description = "Public IP address of the prod instance"
  value       = module.ec2_app.public_ip
}

output "instance_id" {
  description = "Instance ID of the prod instance"
  value       = module.ec2_app.instance_id
}
```

- [ ] **Step 4: Write `envs/prod/terraform.tfvars.example`**

```hcl
ssh_public_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user1@example.com",
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user2@example.com",
]

app_ports = [8080]
```

- [ ] **Step 5: Write `envs/prod/README.md`**

```markdown
# envs/prod

## First-time setup

1. Run `bootstrap/` once (see `bootstrap/README.md`) and note its outputs.
2. Uncomment and fill in the `backend "s3"` block in `main.tf` with those outputs.
3. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in real SSH
   public keys (and any `app_ports` your service needs). `terraform.tfvars`
   is gitignored — never commit real keys through it.
4. `terraform init`
5. `terraform plan` (requires valid AWS credentials)
6. `terraform apply`

## After apply

SSH in as: `ssh ec2-user@$(terraform output -raw public_ip)`

Anyone whose public key is listed in `ssh_public_keys` can log in this way.
Deploying containers (`docker run` / `docker compose`) on the box is a manual
step, not automated by this Terraform setup.
```

- [ ] **Step 6: Format and validate**

Run: `cd /Users/charleswang/projects/beento/beento-infra/envs/prod && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `fmt` prints nothing; `init` succeeds (downloads `aws` provider, resolves the local `modules/ec2_app` source); `validate` prints `Success! The configuration is valid.`

- [ ] **Step 7: Commit**

```bash
cd /Users/charleswang/projects/beento/beento-infra
git add envs/prod/
git commit -m "Add prod environment wiring ec2_app module with S3 backend"
```

---

### Task 5: Root README and full-repo validation

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: the complete repo structure from Tasks 1-4 (describes it end to end).

- [ ] **Step 1: Write root `README.md`**

```markdown
# beento-infra

Terraform for beento's AWS infrastructure. Currently provisions a single
`prod` environment: one Docker-capable EC2 instance in the default VPC,
reachable over SSH by multiple people via a shared `ec2-user` account.

## Layout

- `bootstrap/` — one-time setup: creates the S3 bucket + DynamoDB table used
  as the Terraform remote state backend. Run this first, manually. See
  `bootstrap/README.md`.
- `modules/ec2_app/` — reusable module: security group, EC2 instance,
  Elastic IP, and cloud-init user-data (installs Docker, authorizes SSH keys).
- `envs/prod/` — the only environment right now. Wires `modules/ec2_app`
  together with prod-specific variables and the S3 backend. See
  `envs/prod/README.md` for the full first-time setup and day-to-day usage.

## Quick start

1. `cd bootstrap && terraform init && terraform apply -var="state_bucket_name=<unique-name>"`
2. Copy the outputs into `envs/prod/main.tf`'s `backend "s3"` block.
3. `cd envs/prod`, copy `terraform.tfvars.example` to `terraform.tfvars`,
   fill in real SSH public keys.
4. `terraform init && terraform plan && terraform apply`

## Out of scope (for now)

Multiple environments, a database, a domain/TLS/load balancer, autoscaling,
SSM Session Manager, deploy automation. Add these as separate, focused specs
when needed.
```

- [ ] **Step 2: Validate every directory in one pass**

Run:
```bash
cd /Users/charleswang/projects/beento/beento-infra
terraform fmt -check -recursive
for d in bootstrap modules/ec2_app envs/prod; do
  echo "== $d =="
  (cd "$d" && terraform init -backend=false -input=false >/dev/null && terraform validate)
done
```
Expected: `fmt -check -recursive` prints nothing (no diffs); each of the three `terraform validate` calls prints `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
cd /Users/charleswang/projects/beento/beento-infra
git add README.md
git commit -m "Add root README documenting repo layout and quick start"
```

---

## After this plan

`terraform plan`/`apply` in `bootstrap/` and `envs/prod/` need valid AWS
credentials — confirm with `aws sts get-caller-identity` before running them
(this environment's `default` profile was returning `InvalidClientTokenId`
at spec time and needs to be refreshed).
