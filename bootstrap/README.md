# Bootstrap

Run this once, manually, before anything in `envs/`. It creates the S3 bucket
and DynamoDB table that `envs/prod` uses as its remote state backend. It uses
**local** state itself (chicken-and-egg problem: the backend can't store its
own creation state).

## Usage

    cd bootstrap
    terraform init
    terraform apply -var="state_bucket_name=<your-globally-unique-bucket-name>"

Uncomment and copy the `state_bucket_name` and `lock_table_name` outputs into
the `backend "s3"` block in `envs/prod/main.tf`, then run `terraform init`
there.

This only needs to be run once per AWS account. Keep `bootstrap/terraform.tfstate`
safe (it is local state, not backed up anywhere by this setup).
