# backend.tf

# Configure the Terraform backend to use Amazon S3 for state storage
# This configuration ensures that the Terraform state is stored remotely,
# enabling collaboration and state locking using DynamoDB.

terraform {
  backend "s3" {
    bucket         = "capstone-terraform-state-vulnmgmt-7f3a"
    key            = "vuln-management/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
