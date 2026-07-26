output "public_ip" {
  description = "Stable public IP (Elastic IP) of the instance"
  value       = aws_eip.app.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}
