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

variable "ami_id" {
  description = "Optional AMI ID override; defaults to latest non-minimal Amazon Linux 2023 if null"
  type        = string
  default     = null
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
