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
