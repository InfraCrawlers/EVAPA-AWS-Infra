# sg.tf

# This Terraform configuration defines a security group for the EC2 instances in the vulnerability management lab.
# The security group allows all outbound traffic to ensure that the instances can communicate with the internet for
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-sg"
  description = "Minimal SG for EC2 vulnerability lab"

  ingress {
    description = "Allow OpenVAS full TCP scan"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    # This points to the other SG resource in your file
    security_groups = [aws_security_group.openvas_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

#Openvas sg
# OpenVAS Security Group
resource "aws_security_group" "openvas_sg" {
  name        = "${var.project_name}-openvas-sg"
  description = "SG for OpenVAS Scanner allowing Web UI and Ansible SSH access"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    from_port   = 9390
    to_port     = 9390
    protocol    = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "lambda_sg" {
  name   = "openvas-lambda-sg"
  vpc_id = data.aws_vpc.selected.id

  egress {
    from_port   = 9390
    to_port     = 9390
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
}

