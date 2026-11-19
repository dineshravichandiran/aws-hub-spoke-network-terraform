variable "name" {
  description = "Name prefix for the route tables."
  type        = string
}

variable "transit_gateway_id" {
  description = "Transit Gateway the route tables belong to."
  type        = string
}

variable "hub_attachment_id" {
  description = "Attachment ID of the hub (egress) VPC."
  type        = string
}

variable "spokes" {
  description = "Spoke networks by name. Each gets its own route table."
  type = map(object({
    attachment_id = string
  }))
}

variable "allowed_flows" {
  description = "Pairs of spoke names that may talk to each other, for example [[\"app\", \"data\"]]. Spokes not listed together cannot reach each other."
  type        = list(list(string))
  default     = []

  validation {
    condition     = alltrue([for p in var.allowed_flows : length(p) == 2])
    error_message = "Each allowed flow is a pair of two spoke names."
  }

  validation {
    condition     = alltrue([for p in var.allowed_flows : alltrue([for s in p : contains(keys(var.spokes), s)])])
    error_message = "Every name in allowed_flows must be a key of the spokes variable."
  }
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}
