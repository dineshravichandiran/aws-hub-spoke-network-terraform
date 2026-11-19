variable "name" {
  description = "Name of the probe instance and its role and security group."
  type        = string
}

variable "vpc_id" {
  description = "VPC the instance runs in."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the instance."
  type        = string
}

variable "allowed_cidrs" {
  description = "Ranges allowed to reach the probe on port 8080 and by ping. Keep this to the private ranges you want to test."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "instance_type" {
  description = "Instance size. t4g.nano is the cheapest Graviton type."
  type        = string
  default     = "t4g.nano"
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}
