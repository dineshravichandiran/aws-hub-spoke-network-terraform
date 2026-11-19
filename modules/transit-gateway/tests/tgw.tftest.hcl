mock_provider "aws" {}

variables {
  name = "test"
}

run "nothing_connects_by_default" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_association == "disable" && aws_ec2_transit_gateway.this.default_route_table_propagation == "disable"
    error_message = "Default association and propagation must be off."
  }

  assert {
    condition     = aws_ec2_transit_gateway.this.auto_accept_shared_attachments == "disable"
    error_message = "Shared attachments must not be accepted automatically."
  }
}
