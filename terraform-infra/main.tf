# main.tf

# This Terraform configuration sets up a basic infrastructure for a vulnerability management lab on AWS.
# It includes IAM roles for SSM, security groups, and EC2 instances running Amazon Linux, Ubuntu, and Windows Server.
# The EC2 instances are configured with various vulnerable services to provide a realistic environment for testing and learning about vulnerabilities and their management.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS provider to use the us-east-1 region
provider "aws" {
  region = "us-east-1"
  access_key = "AKIAVOAK3JRMIFDIXNVJ"
  secret_key = "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"

}

resource "aws_s3_bucket" "s3_openvas_reports" {
  bucket = "${var.project_name}-openvas-reports"

  tags = {
    Name    = "s3-openvas-reports"
    Project = var.project_name
  }
}

# Creates the logical "folders" in your existing bucket
resource "aws_s3_object" "windows_folder" {
  bucket = "${var.project_name}-openvas-reports"
  key    = "windows/"
}

resource "aws_s3_object" "linux_folder" {
  bucket = "${var.project_name}-openvas-reports"
  key    = "linux/"
}

# Include the IAM role and instance profile for SSM, security group, and EC2 instance definitions
resource "aws_iam_role" "ssm_role" {
  name = "${var.project_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach the AmazonSSMManagedInstanceCore policy to the SSM role to allow EC2 instances to communicate with SSM
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# This allows the OpenVAS VM to put objects specifically into your bucket
resource "aws_iam_policy" "openvas_s3_upload" {
  name        = "${var.project_name}-openvas-s3-upload"
  description = "Allows OpenVAS VM to upload reports to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        # Replace 'your-bucket-name' with your actual bucket variable
        Resource = ["arn:aws:s3:::${var.project_name}-openvas-reports/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.project_name}-openvas-reports"]
      }
    ]
  })
}

# Attach the new S3 policy to the existing role
resource "aws_iam_role_policy_attachment" "openvas_s3_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.openvas_s3_upload.arn
}

# Create an instance profile for the SSM role to be attached to EC2 instances
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.project_name}-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Using Ubuntu 20.04 as the Linux target for better package management and vulnerability demonstration
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Windows Server 2019 is chosen for the Windows target to provide a modern environment with relevant vulnerabilities
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }
}
