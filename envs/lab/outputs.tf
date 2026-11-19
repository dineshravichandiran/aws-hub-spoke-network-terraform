output "transit_gateway_id" {
  description = "Transit Gateway ID."
  value       = module.tgw.id
}

output "probe_instance_ids" {
  description = "Probe instance per spoke. Open a Session Manager session to one and curl the others."
  value       = { for k, p in module.probe : k => p.instance_id }
}

output "probe_private_ips" {
  description = "Private IP of each probe."
  value       = { for k, p in module.probe : k => p.private_ip }
}

output "dns_names" {
  description = "Private names that resolve in every VPC."
  value       = module.dns.fqdns
}

output "spokes_that_learn_each_other" {
  description = "Which spoke has routes to which. Empty means the spokes are fully isolated."
  value       = module.routing.learned_between_spokes
}

output "spoke_to_spoke_path_ids" {
  description = "Reachability Analyzer paths between spokes. Start an analysis with aws ec2 start-network-insights-analysis."
  value       = { for k, p in aws_ec2_network_insights_path.spoke_to_spoke : k => p.id }
}

output "spoke_to_internet_path_ids" {
  description = "Reachability Analyzer paths from each spoke to the internet through the hub."
  value       = { for k, p in aws_ec2_network_insights_path.spoke_to_internet : k => p.id }
}
