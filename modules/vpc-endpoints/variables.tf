variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC the endpoints are created in."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR. Interface endpoints accept HTTPS from inside it."
  type        = string
}

variable "route_table_ids" {
  description = "Route tables that get a route to the S3 gateway endpoint."
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subnets for the interface endpoints (one network interface per subnet)."
  type        = list(string)
}

variable "enable_interface_endpoints" {
  description = "Create interface endpoints (private path to AWS APIs). Each costs money per zone per hour, so this is off by default. The S3 gateway endpoint is free and always created."
  type        = bool
  default     = false
}

variable "interface_services" {
  description = "Service short names for the interface endpoints. The defaults are what Systems Manager Session Manager needs."
  type        = set(string)
  default     = ["ssm", "ssmmessages", "ec2messages"]
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}
