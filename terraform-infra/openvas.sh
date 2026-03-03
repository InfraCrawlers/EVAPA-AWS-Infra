#!/bin/bash

# Route all output to a log file so you can watch the installation process
exec > >(tee /var/log/user-data-openvas-docker.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting system bootstrap for Greenbone (Docker)..."

# 1. Update packages and install Ansible and prerequisites
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip software-properties-common curl git ansible

# 2. Generate the Ansible Playbook via heredoc
cat << 'EOF' > /root/install_openvas_docker.yml
---
- name: Install Greenbone (OpenVAS) via Docker on Ubuntu
  hosts: localhost
  connection: local
  become: yes
  vars:
    gvm_install_dir: "/opt/greenbone-community-container"
    gvm_compose_url: "https://greenbone.github.io/docs/latest/_static/docker-compose-22.4.yml"

  tasks:
    - name: Install prerequisite packages for Docker
      apt:
        name:
          - apt-transport-https
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
        state: present
        update_cache: yes

    - name: Create directory for Docker GPG key
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Download Docker GPG apt Key
      get_url:
        url: https://download.docker.com/linux/ubuntu/gpg
        dest: /etc/apt/keyrings/docker.asc
        mode: '0644'

    - name: Add Docker Repository
      apt_repository:
        repo: "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
        state: present

    - name: Install Docker and Docker Compose
      apt:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-compose-plugin
        state: present
        update_cache: yes

    - name: Ensure Docker service is started and enabled
      systemd:
        name: docker
        state: started
        enabled: yes

    - name: Create Greenbone installation directory
      file:
        path: "{{ gvm_install_dir }}"
        state: directory
        mode: '0755'

    - name: Download Greenbone docker-compose.yml
      get_url:
        url: "{{ gvm_compose_url }}"
        dest: "{{ gvm_install_dir }}/docker-compose.yml"

    - name: Modify docker-compose to bind to all external IP addresses
      replace:
        path: "{{ gvm_install_dir }}/docker-compose.yml"
        regexp: '127\.0\.0\.1:9392:80'
        replace: '0.0.0.0:9392:9392'

    - name: Pull Greenbone Docker images
      command: docker compose -f {{ gvm_install_dir }}/docker-compose.yml -p greenbone-community-edition pull
      args:
        chdir: "{{ gvm_install_dir }}"

    - name: Start Greenbone stack (Auto-recovers from SCAP feed sync timeouts)
      shell: |
        docker compose -f docker-compose.yml -p greenbone-community-edition up -d
        if [ $? -ne 0 ]; then
          echo "Startup failed, likely due to SCAP feed timeout. Tearing down to retry..."
          docker compose -f docker-compose.yml -p greenbone-community-edition down
          exit 1
        fi
      args:
        chdir: "{{ gvm_install_dir }}"
      register: compose_up
      until: compose_up.rc == 0
      retries: 10
      delay: 30
EOF

# 3. Execute the playbook locally
echo "Running Ansible Playbook to deploy Docker and Greenbone..."
ansible-playbook /root/install_openvas_docker.yml

echo "Provisioning complete! Greenbone containers are running."