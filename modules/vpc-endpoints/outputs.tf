output "s3_endpoint_id" {
  description = "ID of the S3 gateway endpoint."
  value       = aws_vpc_endpoint.s3.id
}

output "interface_endpoint_count" {
  description = "Number of interface endpoints created."
  value       = length(aws_vpc_endpoint.interface)
}
