locals {
  az_count    = length(var.azs)
  is_hub      = length(var.public_subnet_cidrs) > 0
  has_workers = length(var.workload_subnet_cidrs) > 0
  nat_count   = local.is_hub ? (var.single_nat_gateway ? 1 : local.az_count) : 0
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-default-unused" })
}

# ---- Subnets ----

resource "aws_subnet" "attachment" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.attachment_subnet_cidrs[count.index]

  tags = merge(var.tags, { Name = "${var.name}-attach-${var.azs[count.index]}", Tier = "attachment" })

  lifecycle {
    precondition {
      condition     = length(var.attachment_subnet_cidrs) == local.az_count
      error_message = "attachment_subnet_cidrs needs one CIDR per availability zone."
    }
  }
}

resource "aws_subnet" "workload" {
  count = length(var.workload_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.workload_subnet_cidrs[count.index]

  tags = merge(var.tags, { Name = "${var.name}-workload-${var.azs[count.index]}", Tier = "workload" })

  lifecycle {
    precondition {
      condition     = length(var.workload_subnet_cidrs) == local.az_count
      error_message = "workload_subnet_cidrs needs one CIDR per availability zone, or be empty."
    }
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name}-public-${var.azs[count.index]}", Tier = "public" })

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) == local.az_count
      error_message = "public_subnet_cidrs needs one CIDR per availability zone, or be empty."
    }
  }
}

# ---- Transit Gateway attachment ----

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = aws_subnet.attachment[*].id
  dns_support        = "enable"

  # Route table association and propagation are managed in modules/tgw-routing,
  # so a new attachment never joins a route table by accident.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, { Name = var.name })
}

# ---- Internet egress (hub only) ----

resource "aws_internet_gateway" "this" {
  count = local.is_hub ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_eip" "nat" {
  count = local.nat_count

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-nat-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, { Name = "${var.name}-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

# ---- Route tables ----

# Public (hub): out to the internet, and return traffic for the attached networks back to the Transit Gateway.
resource "aws_route_table" "public" {
  count = local.is_hub ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  count = local.is_hub ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route" "public_to_attached" {
  count = local.is_hub ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = var.private_summary_cidr
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# Attachment subnets (hub): traffic arriving from the Transit Gateway goes out through NAT.
resource "aws_route_table" "attachment" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-attach-${var.azs[count.index]}" })
}

resource "aws_route" "attachment_nat" {
  count = local.is_hub ? local.az_count : 0

  route_table_id         = aws_route_table.attachment[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "attachment" {
  count = local.az_count

  subnet_id      = aws_subnet.attachment[count.index].id
  route_table_id = aws_route_table.attachment[count.index].id
}

# Workload subnets (spokes): everything that is not local goes to the Transit Gateway.
resource "aws_route_table" "workload" {
  count = length(var.workload_subnet_cidrs)

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-workload-${var.azs[count.index]}" })
}

resource "aws_route" "workload_default" {
  count = length(var.workload_subnet_cidrs)

  route_table_id         = aws_route_table.workload[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route_table_association" "workload" {
  count = length(var.workload_subnet_cidrs)

  subnet_id      = aws_subnet.workload[count.index].id
  route_table_id = aws_route_table.workload[count.index].id
}

# ---- Network ACL on the workload subnets: a second layer next to security groups ----
# Stateless, so return traffic must be allowed explicitly.

resource "aws_network_acl" "workload" {
  count = local.has_workers ? 1 : 0

  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.workload[*].id

  tags = merge(var.tags, { Name = "${var.name}-workload" })
}

locals {
  # One NACL rule per (source range, port) pair.
  nacl_inbound = local.has_workers ? {
    for pair in setproduct(var.workload_inbound_cidrs, var.workload_inbound_tcp_ports) :
    "${pair[0]}-${pair[1]}" => { cidr = pair[0], port = pair[1] }
  } : {}
  nacl_inbound_keys = sort(keys(local.nacl_inbound))
}

resource "aws_network_acl_rule" "in_from_allowed" {
  count = length(local.nacl_inbound_keys)

  network_acl_id = aws_network_acl.workload[0].id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.nacl_inbound[local.nacl_inbound_keys[count.index]].cidr
  from_port      = local.nacl_inbound[local.nacl_inbound_keys[count.index]].port
  to_port        = local.nacl_inbound[local.nacl_inbound_keys[count.index]].port
}

resource "aws_network_acl_rule" "in_icmp_from_allowed" {
  #checkov:skip=CKV_AWS_352:ICMP has no ports. Only echo request (ping) is allowed, and only from the internal ranges, for troubleshooting.
  count = local.has_workers ? length(var.workload_inbound_cidrs) : 0

  network_acl_id = aws_network_acl.workload[0].id
  rule_number    = 500 + count.index
  egress         = false
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = var.workload_inbound_cidrs[count.index]
  icmp_type      = 8 # echo request: ping
  icmp_code      = -1
}

# The TCP and UDP return rules below do not cover ICMP, and the ACL is stateless, so the echo REPLY
# (type 0) needs its own inbound rule. The first real apply showed 100% packet loss on ping between the
# spokes until this existed, although the Reachability Analyzer path (TCP 8080) was fine.
resource "aws_network_acl_rule" "in_icmp_reply_from_allowed" {
  #checkov:skip=CKV_AWS_352:ICMP has no ports. Only echo reply (type 0) is allowed, and only from the internal ranges.
  count = local.has_workers ? length(var.workload_inbound_cidrs) : 0

  network_acl_id = aws_network_acl.workload[0].id
  rule_number    = 600 + count.index
  egress         = false
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = var.workload_inbound_cidrs[count.index]
  icmp_type      = 0 # echo reply
  icmp_code      = -1
}

# A network ACL is stateless: replies to connections the workloads start must be allowed in.
# Replies arrive on random high ports, so the range has to be wide. Security groups, which are
# stateful and tight, do the fine-grained work.
resource "aws_network_acl_rule" "in_return_tcp" {
  #checkov:skip=CKV_AWS_231:Return traffic arrives on ephemeral ports (1024-65535). The range is a stateless-ACL necessity and 3389 inside it is not open to new connections: security groups decide that.
  count = local.has_workers ? 1 : 0

  network_acl_id = aws_network_acl.workload[0].id
  rule_number    = 900
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "in_return_udp" {
  #checkov:skip=CKV_AWS_231:Return traffic arrives on ephemeral ports (1024-65535). The range is a stateless-ACL necessity and 3389 inside it is not open to new connections: security groups decide that.
  count = local.has_workers ? 1 : 0

  network_acl_id = aws_network_acl.workload[0].id
  rule_number    = 910
  egress         = false
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "out_all" {
  count = local.has_workers ? 1 : 0

  network_acl_id = aws_network_acl.workload[0].id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# ---- Flow logs ----

resource "aws_cloudwatch_log_group" "flow" {
  #checkov:skip=CKV_AWS_158:Log group uses the default AWS-managed encryption. A customer-managed KMS key costs about $1 a month; listed in README as a next step.
  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = var.tags
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_write" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role" "flow" {
  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "flow" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.flow_write.json
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow.arn
  iam_role_arn    = aws_iam_role.flow.arn

  tags = var.tags
}
