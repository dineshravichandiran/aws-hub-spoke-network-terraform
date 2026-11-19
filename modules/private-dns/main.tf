# One private zone associated with every VPC, so a name resolves the same way from all of them
# without any resolver in between. The addresses it returns are only reachable if the Transit
# Gateway routes allow it: DNS answering is not the same as being allowed to connect.

resource "aws_route53_zone" "this" {
  name    = var.zone_name
  comment = "Private zone shared by the hub and the spokes"

  vpc {
    vpc_id = var.primary_vpc_id
  }

  # Additional associations are managed below. Without this, Terraform would remove them.
  lifecycle {
    ignore_changes = [vpc]
  }

  tags = var.tags
}

resource "aws_route53_zone_association" "additional" {
  count = length(var.additional_vpc_ids)

  zone_id = aws_route53_zone.this.zone_id
  vpc_id  = var.additional_vpc_ids[count.index]
}

resource "aws_route53_record" "this" {
  #checkov:skip=CKV2_AWS_23:Records point at private addresses passed in from the instances in another module; the scanner cannot see that link.
  for_each = var.records

  zone_id = aws_route53_zone.this.zone_id
  name    = "${each.key}.${var.zone_name}"
  type    = "A"
  ttl     = 60
  records = [each.value]
}
