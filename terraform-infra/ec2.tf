# ec2.tf

# resource "aws_instance" "linux_amazon" {
#   ami                    = data.aws_ami.amazon_linux.id
#   instance_type          = var.instance_type
#   iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
#   vpc_security_group_ids = [aws_security_group.ec2_sg.id]
#   key_name               = var.key_name

#   tags = {
#     Name             = "Amazon-Linux-Vuln-Target"
#     OS               = "AmazonLinux2"
#     AssetCriticality = "High"
#     Project          = var.project_name
#   }
# }

# Using Ubuntu 20.04 as the Linux target for better package management and vulnerability demonstration
# The user data script disables automatic updates and installs a variety of services that are commonly found in vulnerable environments, such as Apache, vsftpd, Samba, MySQL, telnetd, rsh-server, snmpd, and PHP. This setup provides a rich environment for vulnerability management exercises.
resource "aws_instance" "linux_ubuntu" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.key_name
  user_data              = file("${path.module}/scripts/linux.sh")
  tags = {
    Name             = "Ubuntu-Vuln-Target"
    OS               = "Ubuntu20.04"
    AssetCriticality = "Medium"
    Project          = var.project_name
  }
}

# Windows Server 2019 is chosen for the Windows target to provide a modern environment with relevant vulnerabilities
# The user data script disables Windows Update and logs the intentional vulnerable state to a file. This setup allows for vulnerability management exercises focused on Windows environments, including patch management and configuration hardening.
resource "aws_instance" "windows" {
  ami                    = data.aws_ami.windows.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.key_name
  user_data              = file("${path.module}/scripts/windows.ps1")

  tags = {
    Name             = "Windows-Vuln-Target"
    OS               = "Windows2019"
    AssetCriticality = "High"
    Project          = var.project_name
  }
}

# The OpenVAS scanner instance is configured with a user data script that installs and sets up OpenVAS (Greenbone Vulnerability Manager) on an Ubuntu instance. The script ensures the system is fully patched, installs the necessary packages, and starts the OpenVAS services. This instance serves as the vulnerability scanner in the lab environment.
resource "aws_instance" "openvas" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.openvas_sg.id]
  key_name               = var.key_name
  user_data              = file("${path.module}/scripts/openvas.sh")
  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }
  tags = {
    Name    = "OpenVAS-Scanner"
    Role    = "VulnerabilityScanner"
    Project = var.project_name
  }

  lifecycle {
    ignore_changes  = all
    prevent_destroy = true
  }
}