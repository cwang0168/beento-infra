# envs/prod

## First-time setup

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in real SSH
   public keys (and any `app_ports` your service needs). `terraform.tfvars`
   is gitignored — never commit real keys through it.
2. `terraform init`
3. `terraform plan` (requires valid AWS credentials)
4. `terraform apply`

State is stored locally in `terraform.tfstate` (gitignored, not backed up
anywhere by this setup) — there's no bootstrap step and no remote backend.
Keep that file safe; losing it means Terraform loses track of what it
created.

## After apply

SSH in as: `ssh ec2-user@$(terraform output -raw public_ip)`

Anyone whose public key is listed in `ssh_public_keys` can log in this way.
Deploying containers on the box is not automated by this Terraform setup.
For the `beento` backend specifically, see that repo's `DEPLOY_EC2.md` for
first-time setup and redeploys; it currently expects the app on port 3000,
mapped to this instance's `app_ports` entry `8080`.

Changing `ssh_public_keys` (or any other input that affects the cloud-init
user-data) replaces the instance rather than updating it in place —
cloud-init only runs its user-data script once per instance, so an in-place
update would silently fail to install the new keys. The Elastic IP and
public address stay the same across a replacement, but anything on the old
box that isn't in Terraform state (files written to disk, running
containers) does not survive.
