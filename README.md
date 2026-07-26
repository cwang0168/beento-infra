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

## Security posture

SSH (port 22) and every port listed in `app_ports` are opened to `0.0.0.0/0`
by design for this initial setup — there is no bastion host, VPN, or CIDR
allowlist in front of the instance. Access control relies entirely on which
SSH public keys are listed in `ssh_public_keys`; password authentication is
not configured. A CIDR allowlist or moving to SSM Session Manager are
natural follow-ups if/when tighter access control is needed.

## Out of scope (for now)

Multiple environments, a database, a domain/TLS/load balancer, autoscaling,
SSM Session Manager, deploy automation. Add these as separate, focused specs
when needed.
