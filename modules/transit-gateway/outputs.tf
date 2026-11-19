output "id" {
  description = "Transit Gateway ID."
  value       = aws_ec2_transit_gateway.this.id
}

output "arn" {
  description = "Transit Gateway ARN."
  value       = aws_ec2_transit_gateway.this.arn
}
