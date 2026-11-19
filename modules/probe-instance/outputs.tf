output "instance_id" {
  description = "Instance ID. Use it with Session Manager and Reachability Analyzer."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance."
  value       = aws_instance.this.private_ip
}
