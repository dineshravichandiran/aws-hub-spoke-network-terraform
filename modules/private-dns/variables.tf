variable "zone_name" {
  description = "Private DNS zone, for example corp.internal."
  type        = string
}

variable "primary_vpc_id" {
  description = "VPC the zone is created with."
  type        = string
}

variable "additional_vpc_ids" {
  description = "Every other VPC that should resolve names in the zone."
  type        = list(string)
  default     = []
}

variable "records" {
  description = "A records as name => private IP address. The name is relative to the zone, for example app."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}
