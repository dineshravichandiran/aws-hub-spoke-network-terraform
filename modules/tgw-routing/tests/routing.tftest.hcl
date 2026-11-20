mock_provider "aws" {}

variables {
  name               = "test"
  transit_gateway_id = "tgw-0123456789abcdef0"
  hub_attachment_id  = "tgw-attach-hub0000000000000"
  spokes = {
    app  = { attachment_id = "tgw-attach-app0000000000000" }
    data = { attachment_id = "tgw-attach-data000000000000" }
  }
}

run "spokes_are_isolated_by_default" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_propagation.spoke_learns_spoke) == 0
    error_message = "With no allowed flows, no spoke may learn another spoke's routes."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table.spoke) == 2
    error_message = "Each spoke gets its own route table."
  }
}

run "every_spoke_defaults_to_the_hub" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_route.spoke_default) == 2
    error_message = "Each spoke needs a default route to the hub."
  }

  assert {
    condition     = alltrue([for r in aws_ec2_transit_gateway_route.spoke_default : r.destination_cidr_block == "0.0.0.0/0"])
    error_message = "The default route is 0.0.0.0/0."
  }
}

run "the_hub_learns_every_spoke" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_propagation.hub_learns_spoke) == 2
    error_message = "The hub table must learn every spoke so return traffic finds its way back."
  }
}

run "an_allowed_pair_learns_each_other_both_ways" {
  command = plan

  variables {
    allowed_flows = [["app", "data"]]
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_propagation.spoke_learns_spoke) == 2
    error_message = "One allowed pair means two propagations, one in each direction."
  }

  assert {
    condition     = join(",", output.learned_between_spokes) == "app-learns-data,data-learns-app"
    error_message = "The output should list who learns whom."
  }
}

run "rejects_an_unknown_spoke_name" {
  command = plan

  variables {
    allowed_flows = [["app", "typo"]]
  }

  expect_failures = [var.allowed_flows]
}

run "rejects_a_flow_that_is_not_a_pair" {
  command = plan

  variables {
    allowed_flows = [["app"]]
  }

  expect_failures = [var.allowed_flows]
}

run "no_blackhole_unless_a_summary_range_is_given" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_route.spoke_private_blackhole) == 0
    error_message = "Without private_summary_cidr there is no blackhole route."
  }
}

run "each_spoke_blackholes_the_private_supernet" {
  command = plan

  variables {
    private_summary_cidr = "10.0.0.0/8"
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.spoke_private_blackhole) == 2
    error_message = "Each spoke table needs a blackhole for the private supernet."
  }

  assert {
    condition     = alltrue([for r in aws_ec2_transit_gateway_route.spoke_private_blackhole : r.blackhole && r.destination_cidr_block == "10.0.0.0/8"])
    error_message = "The route must be a blackhole for the supernet."
  }
}
