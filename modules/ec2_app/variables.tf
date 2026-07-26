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
