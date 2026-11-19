output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "attachment_id" {
  description = "ID of the Transit Gateway VPC attachment."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}

output "workload_subnet_ids" {
  description = "Workload subnet IDs, one per zone. Empty for the hub."
  value       = aws_subnet.workload[*].id
}

output "workload_route_table_ids" {
  description = "Route tables of the workload subnets. Gateway endpoints attach to these."
  value       = aws_route_table.workload[*].id
}

output "internet_gateway_id" {
  description = "Internet gateway ID. Null in a spoke."
  value       = local.is_hub ? aws_internet_gateway.this[0].id : null
}

output "nat_gateway_count" {
  description = "Number of NAT gateways. Zero in a spoke."
  value       = length(aws_nat_gateway.this)
}
