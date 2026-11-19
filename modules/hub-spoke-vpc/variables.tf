variable "name" {
  description = "Name prefix for every resource in this VPC."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the VPC."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR, for example 10.1.0.0/16."
  }
}

variable "azs" {
  description = "Availability zones. Every subnet list below has one CIDR per zone (or is empty)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Use at least two availability zones."
  }
}

variable "attachment_subnet_cidrs" {
  description = "Small dedicated subnets (a /28 per zone is enough) that hold the Transit Gateway attachment network interfaces."
  type        = list(string)
}

variable "workload_subnet_cidrs" {
  description = "Private subnets for workloads. Their default route goes to the Transit Gateway. Leave empty for the hub."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "Public subnets holding the NAT gateways. Setting these makes this VPC the egress hub: it gets an internet gateway and NAT."
  type        = list(string)
  default     = []
}

variable "transit_gateway_id" {
  description = "Transit Gateway to attach to."
  type        = string
}

variable "private_summary_cidr" {
  description = "Summary of every attached network. In the hub, return traffic from the internet is sent to the Transit Gateway for this range."
  type        = string
  default     = "10.0.0.0/8"
}

variable "single_nat_gateway" {
  description = "Hub only. One shared NAT gateway (cheap, one point of failure) or one per zone."
  type        = bool
  default     = true
}

variable "workload_inbound_cidrs" {
  description = "Source ranges the workload subnets accept connections from, on the ports in workload_inbound_tcp_ports (and ping)."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "workload_inbound_tcp_ports" {
  description = "TCP ports the workload subnets accept from workload_inbound_cidrs. Everything else inbound is denied except return traffic."
  type        = list(number)
  default     = [8080]
}

variable "flow_log_retention_days" {
  description = "How long VPC flow logs are kept."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}
