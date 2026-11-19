provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name = "${var.project}-${var.environment}"

  # /16 carved into /24 workload subnets and tiny /28 attachment subnets at the very end of the range.
  hub_public_cidrs = [for i in range(2) : cidrsubnet(var.hub_cidr, 8, i)]
  hub_attach_cidrs = [for i in range(2) : cidrsubnet(var.hub_cidr, 12, 4080 + i)]

  spoke_workload_cidrs = { for k, v in var.spokes : k => [for i in range(2) : cidrsubnet(v.cidr, 8, i)] }
  spoke_attach_cidrs   = { for k, v in var.spokes : k => [for i in range(2) : cidrsubnet(v.cidr, 12, 4080 + i)] }

  # Ordered pairs of spokes, for the Reachability Analyzer paths.
  spoke_pairs = {
    for p in setproduct(keys(var.spokes), keys(var.spokes)) : "${p[0]}-to-${p[1]}" => { from = p[0], to = p[1] }
    if p[0] != p[1]
  }
}

module "tgw" {
  source = "../../modules/transit-gateway"

  name = local.name
}

# The hub: internet gateway and NAT live here, once, for everyone.
module "hub" {
  source = "../../modules/hub-spoke-vpc"

  name                    = "${local.name}-hub"
  cidr_block              = var.hub_cidr
  azs                     = var.availability_zones
  public_subnet_cidrs     = local.hub_public_cidrs
  attachment_subnet_cidrs = local.hub_attach_cidrs
  transit_gateway_id      = module.tgw.id
  private_summary_cidr    = var.supernet
  single_nat_gateway      = var.single_nat_gateway
}

# The spokes: no internet gateway, no NAT. Their only way out is the Transit Gateway.
module "spoke" {
  source   = "../../modules/hub-spoke-vpc"
  for_each = var.spokes

  name                    = "${local.name}-${each.key}"
  cidr_block              = each.value.cidr
  azs                     = var.availability_zones
  workload_subnet_cidrs   = local.spoke_workload_cidrs[each.key]
  attachment_subnet_cidrs = local.spoke_attach_cidrs[each.key]
  transit_gateway_id      = module.tgw.id
  workload_inbound_cidrs  = [var.supernet]
}

module "routing" {
  source = "../../modules/tgw-routing"

  name               = local.name
  transit_gateway_id = module.tgw.id
  hub_attachment_id  = module.hub.attachment_id
  spokes             = { for k, m in module.spoke : k => { attachment_id = m.attachment_id } }
  allowed_flows      = var.allowed_flows
}

module "endpoints" {
  source   = "../../modules/vpc-endpoints"
  for_each = var.spokes

  name                       = "${local.name}-${each.key}"
  vpc_id                     = module.spoke[each.key].vpc_id
  vpc_cidr_block             = module.spoke[each.key].vpc_cidr_block
  route_table_ids            = module.spoke[each.key].workload_route_table_ids
  subnet_ids                 = module.spoke[each.key].workload_subnet_ids
  enable_interface_endpoints = var.enable_interface_endpoints
}

module "probe" {
  source   = "../../modules/probe-instance"
  for_each = var.spokes

  name          = "${local.name}-${each.key}-probe"
  vpc_id        = module.spoke[each.key].vpc_id
  subnet_id     = module.spoke[each.key].workload_subnet_ids[0]
  allowed_cidrs = [var.supernet]

  # The Transit Gateway routes must exist before the instance boots and tries to reach Session Manager.
  depends_on = [module.routing]
}

module "dns" {
  source = "../../modules/private-dns"

  zone_name          = var.zone_name
  primary_vpc_id     = module.hub.vpc_id
  additional_vpc_ids = [for k in sort(keys(var.spokes)) : module.spoke[k].vpc_id]
  records            = { for k, p in module.probe : k => p.private_ip }
}

# ---- Reachability Analyzer: asks AWS whether a path exists, by reading the configuration ----
# Paths are defined here. Analyses are started from the runbook (each costs a few cents).

resource "aws_ec2_network_insights_path" "spoke_to_spoke" {
  for_each = local.spoke_pairs

  source           = module.probe[each.value.from].instance_id
  destination      = module.probe[each.value.to].instance_id
  protocol         = "tcp"
  destination_port = 8080

  tags = { Name = "${local.name}-${each.key}" }

  depends_on = [module.routing]
}

resource "aws_ec2_network_insights_path" "spoke_to_internet" {
  for_each = var.spokes

  source           = module.probe[each.key].instance_id
  destination      = module.hub.internet_gateway_id
  destination_ip   = "1.1.1.1"
  protocol         = "tcp"
  destination_port = 443

  tags = { Name = "${local.name}-${each.key}-to-internet" }

  depends_on = [module.routing]
}
