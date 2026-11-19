mock_provider "aws" {}

variables {
  name            = "test"
  vpc_id          = "vpc-12345678"
  vpc_cidr_block  = "10.1.0.0/16"
  route_table_ids = ["rtb-aaaa1111", "rtb-bbbb2222"]
  subnet_ids      = ["subnet-aaaa1111", "subnet-bbbb2222"]
}

run "only_the_free_s3_endpoint_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0
    error_message = "Interface endpoints cost money and are off by default."
  }

  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway"
    error_message = "S3 uses a gateway endpoint."
  }
}

run "session_manager_endpoints_when_enabled" {
  command = plan

  variables {
    enable_interface_endpoints = true
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 3
    error_message = "ssm, ssmmessages and ec2messages."
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : e.private_dns_enabled == true])
    error_message = "Private DNS must be on so the normal service names resolve privately."
  }
}
