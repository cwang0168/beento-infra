# Terraform AWS Setup — Design

## Purpose

Stand up a minimal, single-environment Terraform configuration in `beento-infra` to provision AWS infrastructure for backend API/microservices. This is the initial infra setup — no app code lives here.

## Scope

- Single environment: `prod` only (no dev/staging split for now)
- Region: `us-east-1`
- Compute: one self-managed EC2 instance running Docker containers
- Networking: AWS account's default VPC
- Database: none yet
- Domain/TLS: none yet — reachable via public IP + port
- SSH: shared OS user (`ec2-user`), multiple authorized public keys, security group open to `0.0.0.0/0` on port 22

Explicitly out of scope for this round (can be added later as separate specs): multiple environments, RDS/other databases, ALB + ACM + Route53 domain, autoscaling/ASG, SSM Session Manager, per-user OS accounts, deploy tooling/CI.

## Architecture

```
beento-infra/
├── bootstrap/              # one-time, local state: creates the remote state backend
│   ├── main.tf             # S3 bucket (versioned, encrypted) + DynamoDB lock table
│   ├── variables.tf
│   └── outputs.tf
├── envs/
│   └── prod/
│       ├── main.tf              # backend "s3" config, provider, calls modules/ec2_app
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── modules/
    └── ec2_app/
        ├── main.tf           # security group, EC2 instance, Elastic IP
        ├── variables.tf
        ├── outputs.tf
        └── user_data.sh.tpl  # cloud-init template: installs Docker, writes authorized_keys
```

### bootstrap/

Run once, manually, with local Terraform state (chicken-and-egg: the state backend can't store its own state). Creates:
- An S3 bucket for Terraform state, with versioning and server-side encryption enabled, public access blocked.
- A DynamoDB table for state locking (`LockID` as the hash key, `PAY_PER_REQUEST` billing).

Outputs the bucket name and table name, which get hand-copied into `envs/prod/main.tf`'s `backend "s3"` block (Terraform backend config can't use variables, so this is a manual one-time step, documented in a README).

### modules/ec2_app

Reusable module, inputs:
- `instance_type` (default `t3.micro`)
- `ami_id` (default: latest Amazon Linux 2023 via data source, overridable)
- `ssh_public_keys` (list of strings — one per person who needs access)
- `app_ports` (list of numbers — additional TCP ports to open to `0.0.0.0/0`, e.g. `[8080]`)
- `key_name` (for the AWS key pair resource — required by EC2 launch even though real auth happens via authorized_keys)

Resources:
- `aws_security_group`: inbound 22/tcp from `0.0.0.0/0`, inbound each port in `app_ports` from `0.0.0.0/0`, all egress allowed.
- `aws_instance`: Amazon Linux 2023, in the default VPC/subnet, with the security group attached, an Elastic IP association, and `user_data` rendered from `user_data.sh.tpl`.
- `aws_eip`: allocated and associated to the instance, so the public IP is stable across instance replacement.
- `user_data.sh.tpl`: cloud-init script that (a) installs Docker and enables/starts the service, adds `ec2-user` to the `docker` group, and (b) appends each key in `ssh_public_keys` to `/home/ec2-user/.ssh/authorized_keys`.

Outputs: `public_ip`, `instance_id`.

### envs/prod

- `main.tf`: configures the `aws` provider (region `us-east-1`), configures the `s3` backend (bucket/table filled in after bootstrap), instantiates `modules/ec2_app` with prod-specific variable values.
- `variables.tf`: declares `ssh_public_keys`, `app_ports`, `instance_type` (with a sensible default), etc.
- `terraform.tfvars.example`: example values, especially `ssh_public_keys`, committed to the repo so it's obvious what to fill in. Real `terraform.tfvars` is gitignored.
- `outputs.tf`: re-exports the module's `public_ip` and `instance_id`.

## Data Flow / Operational Flow

1. One-time: `cd bootstrap && terraform init && terraform apply` → creates S3 bucket + DynamoDB table. Note the outputs.
2. Fill in the backend config in `envs/prod/main.tf` with the bucket/table names.
3. Copy `terraform.tfvars.example` to `terraform.tfvars`, fill in real SSH public keys and any app ports.
4. `cd envs/prod && terraform init && terraform apply` → provisions the security group, EC2 instance, and EIP.
5. Anyone whose public key is in `ssh_public_keys` can `ssh ec2-user@<public_ip>`.
6. Deploying/running containers on the box is a manual `docker run`/`docker compose` step for now — not automated by this setup.

## Error Handling / Constraints

- Terraform backend configuration cannot reference variables, so the bootstrap → prod wiring step is manual and documented in each directory's README.
- `terraform.tfvars` (containing real SSH keys) is gitignored; `.example` file is committed as a template.
- No secrets stored in Terraform state beyond what AWS resources naturally expose (no DB credentials, since there's no database yet).

## Testing / Validation

- `terraform validate` and `terraform plan` in both `bootstrap/` and `envs/prod/` before applying.
- After apply, manually verify SSH access works for at least one key in the list, and that Docker is installed and running (`docker --version`, `systemctl status docker`).
- No automated test suite — this is infra-as-code for a single instance, validated via plan/apply and manual smoke checks.

## Prerequisites (not part of this spec's implementation, but required to execute it)

- Valid AWS credentials configured locally (the `default` profile currently present in `~/.aws/credentials` returned an invalid-token error during setup — needs to be refreshed/fixed before `terraform apply` will work).
- Terraform CLI installed (confirmed: v1.10.3 present locally).
