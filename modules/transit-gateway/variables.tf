variable "name" {
  description = "Name of the Transit Gateway."
  type        = string
}

variable "amazon_side_asn" {
  description = "Private ASN for the AWS side of any future VPN or Direct Connect attachment."
  type        = number
  default     = 64512
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}
