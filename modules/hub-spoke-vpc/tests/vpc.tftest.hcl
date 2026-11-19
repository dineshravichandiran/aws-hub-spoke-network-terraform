mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name                    = "test"
  cidr_block              = "10.1.0.0/16"
  azs                     = ["ap-south-1a", "ap-south-1b"]
  attachment_subnet_cidrs = ["10.1.255.0/28", "10.1.255.16/28"]
  transit_gateway_id      = "tgw-0123456789abcdef0"
}

run "spoke_has_no_internet_gateway_and_no_nat" {
  command = plan

  variables {
    workload_subnet_cidrs = ["10.1.0.0/24", "10.1.1.0/24"]
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_nat_gateway.this) == 0
    error_message = "A spoke must have no internet gateway and no NAT gateway."
  }

  assert {
    condition     = length(aws_route.workload_default) == 2
    error_message = "Each workload route table sends its default route to the Transit Gateway."
  }

  assert {
    condition     = length(aws_network_acl.workload) == 1
    error_message = "Workload subnets get a network ACL."
  }
}

run "hub_has_internet_and_one_shared_nat" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 1 && length(aws_nat_gateway.this) == 1
    error_message = "The hub has one internet gateway and, by default, one shared NAT gateway."
  }

  assert {
    condition     = length(aws_route.public_to_attached) == 1
    error_message = "Return traffic for the attached networks must route back to the Transit Gateway."
  }

  assert {
    condition     = length(aws_route.attachment_nat) == 2
    error_message = "Traffic arriving from the Transit Gateway must go out through NAT in both zones."
  }
}

run "hub_can_have_a_nat_per_zone" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
    single_nat_gateway  = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "single_nat_gateway = false must create one NAT gateway per zone."
  }
}

run "attachment_does_not_join_a_route_table_on_its_own" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.this.transit_gateway_default_route_table_association == false && aws_ec2_transit_gateway_vpc_attachment.this.transit_gateway_default_route_table_propagation == false
    error_message = "Association and propagation are managed in tgw-routing, never by default."
  }
}

run "rejects_workload_subnets_that_do_not_match_the_zones" {
  command = plan

  variables {
    workload_subnet_cidrs = ["10.1.0.0/24"]
  }

  expect_failures = [aws_subnet.workload]
}

run "rejects_a_single_zone" {
  command = plan

  variables {
    azs                     = ["ap-south-1a"]
    attachment_subnet_cidrs = ["10.1.255.0/28"]
  }

  expect_failures = [var.azs]
}
