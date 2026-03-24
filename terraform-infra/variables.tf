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

variable "common_env_vars" {
  type = map(string)
  default = {
    OPENVAS_IP   = "10.0.x.x"
    GMP_USER     = "admin"
    GMP_PASSWORD = "yourpassword"
  }
}