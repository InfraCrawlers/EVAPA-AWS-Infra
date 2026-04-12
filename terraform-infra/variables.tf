# variables.tf

variable "project_name" {
  default = "capstone-vuln-mgmt"
}

variable "instance_type" {
  default = "t3.medium"
}

variable "key_name" {
  description = "Optional EC2 key pair name (can be left empty if using SSM only)"
  default     = null
}

# variables.tf
variable "gmp_user" {
  type    = string
  default = "admin"
}

variable "gmp_password" {
  type      = string
  default   = "admin"
  sensitive = true
}