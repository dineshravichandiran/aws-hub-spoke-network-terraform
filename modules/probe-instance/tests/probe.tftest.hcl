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

variables {
  name      = "test"
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-aaaa1111"
}

run "instance_is_private_and_uses_imds_v2" {
  command = plan

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false
    error_message = "The probe must not have a public IP."
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true
    error_message = "The root volume must be encrypted."
  }
}

run "one_rule_per_allowed_range" {
  command = plan

  variables {
    allowed_cidrs = ["10.1.0.0/16", "10.2.0.0/16"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.http) == 2
    error_message = "One 8080 rule per allowed range."
  }
}
