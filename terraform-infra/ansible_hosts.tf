# Generate the hosts.ini file for Ansible
resource "local_file" "ansible_inventory" {
  content  = <<EOT
[ubuntu_nodes]
${aws_instance.linux_ubuntu.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=./ssh_key.pem

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOT
  filename = "${path.module}/hosts.ini"
}