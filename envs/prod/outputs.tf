output "public_ip" {
  description = "Public IP address of the prod instance"
  value       = module.ec2_app.public_ip
}

output "instance_id" {
  description = "Instance ID of the prod instance"
  value       = module.ec2_app.instance_id
}
