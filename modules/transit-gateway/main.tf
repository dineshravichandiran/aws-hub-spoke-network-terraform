resource "aws_ec2_transit_gateway" "this" {
  description     = var.name
  amazon_side_asn = var.amazon_side_asn

  # Nothing joins a route table, and no attachment is accepted, unless the code says so.
  # Default association and propagation are what make a Transit Gateway quietly connect everything to everything.
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, { Name = var.name })
}
