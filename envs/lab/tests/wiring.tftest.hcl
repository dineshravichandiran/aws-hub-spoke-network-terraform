# Plans the whole lab against a mocked AWS provider.
# This proves the modules are wired together correctly. It does not prove anything about a real account.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }
}

run "default_lab_plans" {
  command = plan

  assert {
    condition     = length(module.spoke) == 2 && length(module.probe) == 2
    error_message = "Two spokes with one probe each."
  }

  assert {
    condition     = module.hub.nat_gateway_count == 1
    error_message = "One shared NAT gateway in the hub."
  }

  assert {
    condition     = alltrue([for k, m in module.spoke : m.nat_gateway_count == 0])
    error_message = "Spokes have no NAT gateway: their only way out is the Transit Gateway."
  }

  assert {
    condition     = length(aws_ec2_network_insights_path.spoke_to_spoke) == 2 && length(aws_ec2_network_insights_path.spoke_to_internet) == 2
    error_message = "Paths in both directions between the spokes, and one to the internet per spoke."
  }
}

run "app_and_data_are_connected_by_default" {
  command = plan

  assert {
    condition     = join(",", module.routing.learned_between_spokes) == "app-learns-data,data-learns-app"
    error_message = "The default lab lets app and data talk to each other."
  }
}

run "emptying_allowed_flows_isolates_the_spokes" {
  command = plan

  variables {
    allowed_flows = []
  }

  assert {
    condition     = length(module.routing.learned_between_spokes) == 0
    error_message = "With no allowed flows the spokes must not learn each other's routes."
  }
}

run "a_third_spoke_joins_without_touching_the_others" {
  command = plan

  variables {
    spokes = {
      app  = { cidr = "10.1.0.0/16" }
      data = { cidr = "10.2.0.0/16" }
      ops  = { cidr = "10.3.0.0/16" }
    }
  }

  assert {
    condition     = length(module.spoke) == 3
    error_message = "A new entry in the spokes map adds a spoke."
  }

  assert {
    condition     = join(",", module.routing.learned_between_spokes) == "app-learns-data,data-learns-app"
    error_message = "The new spoke is isolated: only the listed pair learns each other."
  }
}

run "needs_exactly_two_zones" {
  command = plan

  variables {
    availability_zones = ["ap-south-1a"]
  }

  expect_failures = [var.availability_zones]
}
