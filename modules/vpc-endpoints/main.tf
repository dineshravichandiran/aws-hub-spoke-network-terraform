data "aws_region" "current" {}

# Gateway endpoint: free. S3 traffic stays on the AWS network instead of going out through NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-s3" })
}

resource "aws_security_group" "endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name_prefix = "${var.name}-endpoints-"
  description = "Interface endpoints: HTTPS from inside the VPC"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr_block
}

# Interface endpoints: a private network interface per subnet. With private DNS on, the normal
# service name (ssm.<region>.amazonaws.com) resolves to the private address, so nothing in the
# application changes.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_interface_endpoints ? var.interface_services : toset([])

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-${each.value}" })
}
