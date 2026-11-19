mock_provider "aws" {}

variables {
  zone_name          = "corp.internal"
  primary_vpc_id     = "vpc-aaaa1111"
  additional_vpc_ids = ["vpc-bbbb2222", "vpc-cccc3333"]
  records = {
    app  = "10.1.0.10"
    data = "10.2.0.10"
  }
}

run "zone_is_shared_with_every_vpc" {
  command = plan

  assert {
    condition     = length(aws_route53_zone_association.additional) == 2
    error_message = "Every additional VPC needs a zone association."
  }
}

run "records_live_under_the_zone" {
  command = plan

  assert {
    condition     = aws_route53_record.this["app"].name == "app.corp.internal" && aws_route53_record.this["data"].name == "data.corp.internal"
    error_message = "Record names are relative to the zone."
  }
}
