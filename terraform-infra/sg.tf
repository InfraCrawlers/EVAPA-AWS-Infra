# sg.tf

# This Terraform configuration defines a security group for the EC2 instances in the vulnerability management lab.
# The security group allows all outbound traffic to ensure that the instances can communicate with the internet for
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-sg"
  description = "Minimal SG for EC2 vulnerability lab"
  
  ingress {
    description     = "Allow OpenVAS full TCP scan"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
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

  # Allow native OpenVAS Web UI access
  ingress {
    from_port   = 9392
    to_port     = 9392
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH access so Ansible can connect and configure the server
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    # Note: For better security, replace 0.0.0.0/0 with your actual local public IP
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

