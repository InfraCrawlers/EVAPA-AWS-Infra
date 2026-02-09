# variables.tf

variable "project_name" {
  default = "capstone-vuln-mgmt"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "key_name" {
  description = "Optional EC2 key pair name (can be left empty if using SSM only)"
  default     = null
}
