output "zone_id" {
  description = "ID of the private zone."
  value       = aws_route53_zone.this.zone_id
}

output "fqdns" {
  description = "Full names of the records."
  value       = [for r in aws_route53_record.this : r.fqdn]
}
