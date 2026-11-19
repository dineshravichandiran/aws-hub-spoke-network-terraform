# Segmentation lives here. A Transit Gateway route table decides what an attachment can reach:
#   - the HUB table learns every spoke (so return traffic from the internet finds its way back)
#   - each SPOKE table has a default route to the hub (internet through the shared NAT), knows the
#     hub's own range, and knows another spoke only if the pair is listed in allowed_flows.
# A spoke that is not in the other's table has no route to it. That is the isolation.

locals {
  # [["app","data"]] becomes: app learns data's routes, and data learns app's routes.
  flows = {
    for pair in flatten([for p in var.allowed_flows : [
      { into = p[0], from = p[1] },
      { into = p[1], from = p[0] },
    ]]) : "${pair.into}-learns-${pair.from}" => pair
  }
}

resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = var.transit_gateway_id

  tags = merge(var.tags, { Name = "${var.name}-hub" })
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = var.hub_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "hub_learns_spoke" {
  for_each = var.spokes

  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  for_each = var.spokes

  transit_gateway_id = var.transit_gateway_id

  tags = merge(var.tags, { Name = "${var.name}-spoke-${each.key}" })
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = var.spokes

  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
}

# Default route: anything the spoke does not know goes to the hub.
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  for_each = var.spokes

  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = var.hub_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
}

# The hub's own range, learned from its attachment.
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_learns_hub" {
  for_each = var.spokes

  transit_gateway_attachment_id  = var.hub_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
}

# Only the listed spoke pairs learn each other.
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_learns_spoke" {
  for_each = local.flows

  transit_gateway_attachment_id  = var.spokes[each.value.from].attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.value.into].id
}
