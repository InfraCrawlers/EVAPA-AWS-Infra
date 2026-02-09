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

  user_data = <<-EOF
#!/bin/bash
systemctl stop unattended-upgrades
systemctl disable unattended-upgrades
sed -i 's/"1"/"0"/g' /etc/apt/apt.conf.d/20auto-upgrades
apt-mark hold linux-generic
apt update
apt install -y apache2 vsftpd samba mysql-server telnetd rsh-server snmpd php
EOF

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
  user_data = <<-EOF
<powershell>
# Disable Windows Update service
Stop-Service -Name wuauserv -Force
Set-Service -Name wuauserv -StartupType Disabled

# Disable automatic updates via registry
New-Item -Path "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU" -Force
Set-ItemProperty -Path "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU" `
  -Name NoAutoUpdate -Value 1 -Type DWord

# Log intentional vulnerable state
"Intentional vulnerable state configured" | Out-File C:\\vuln-lab.txt
</powershell>
EOF

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
  instance_type          = "t3.small"
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.key_name
  user_data = <<-EOF
#!/bin/bash
apt update && apt upgrade -y
EOF
  tags = {
    Name    = "OpenVAS-Scanner"
    Role    = "VulnerabilityScanner"
    Project = var.project_name
  }
}