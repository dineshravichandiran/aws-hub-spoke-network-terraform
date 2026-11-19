output "hub_route_table_id" {
  description = "Transit Gateway route table of the hub."
  value       = aws_ec2_transit_gateway_route_table.hub.id
}

output "spoke_route_table_ids" {
  description = "Transit Gateway route table of each spoke, by name."
  value       = { for k, rt in aws_ec2_transit_gateway_route_table.spoke : k => rt.id }
}

output "learned_between_spokes" {
  description = "Which spoke learns which other spoke's routes."
  value       = sort(keys(local.flows))
}
