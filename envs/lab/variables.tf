variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "availability_zones" {
  description = "Two zones, pinned by name so a new zone in the region never changes the plan."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Give exactly two availability zones: the subnet layout is built for two."
  }
}

variable "project" {
  description = "Project name, used as a prefix on every resource."
  type        = string
  default     = "hub-spoke"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "lab"
}

variable "supernet" {
  description = "One range that covers the hub and every spoke. Used for return routes and for the allow rules on the instances."
  type        = string
  default     = "10.0.0.0/8"
}

variable "hub_cidr" {
  description = "CIDR of the hub (egress) VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "spokes" {
  description = "Spoke VPCs by name. Each is isolated from the others unless a pair is listed in allowed_flows."
  type = map(object({
    cidr = string
  }))
  default = {
    app  = { cidr = "10.1.0.0/16" }
    data = { cidr = "10.2.0.0/16" }
  }
}

variable "allowed_flows" {
  description = "Pairs of spokes that may reach each other. Set to [] to cut the spokes off from each other and watch Reachability Analyzer report it."
  type        = list(list(string))
  default     = [["app", "data"]]
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway in the hub (cheap) or one per zone (resilient)."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create the Systems Manager interface endpoints in each spoke. Costs more, keeps AWS API traffic off the NAT path."
  type        = bool
  default     = false
}

variable "zone_name" {
  description = "Private DNS zone shared by every VPC."
  type        = string
  default     = "corp.internal"
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag."
  type        = string
  default     = "dineshravichandiran"
}
