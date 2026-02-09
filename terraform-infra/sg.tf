# sg.tf

# This Terraform configuration defines a security group for the EC2 instances in the vulnerability management lab.
# The security group allows all outbound traffic to ensure that the instances can communicate with the internet for
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-sg"
  description = "Minimal SG for EC2 vulnerability lab"

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
