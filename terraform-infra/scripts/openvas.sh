#!/bin/bash

# Route logs
exec > >(tee /var/log/user-data-openvas-docker.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting system bootstrap for Greenbone (Docker)..."

export DEBIAN_FRONTEND=noninteractive

# -------------------------------
# STEP 1: Base dependencies
# -------------------------------
apt-get update -y
apt-get install -y python3 python3-pip software-properties-common curl git unzip

# Wait for network stability (IMPORTANT)
sleep 30

# -------------------------------
# STEP 2: Python + Ansible setup
# -------------------------------
python3 -m pip install --upgrade pip

# Install everything system-wide (no user/local conflicts)
python3 -m pip install --break-system-packages \
  ansible \
  boto3 \
  botocore

# -------------------------------
# STEP 3: Install AWS CLI v2
# -------------------------------
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Fix PATH (CRITICAL)
export PATH=/usr/local/bin:$PATH

# -------------------------------
# STEP 4: Install Session Manager Plugin
# -------------------------------
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
dpkg -i session-manager-plugin.deb

# -------------------------------
# STEP 5: Install Ansible AWS Collection
# -------------------------------
ansible-galaxy collection install amazon.aws

# -------------------------------
# STEP 6: VALIDATION (VERY IMPORTANT)
# -------------------------------
echo "Validating environment..."

python3 -c "import boto3; import botocore; print('BOTO3 OK')" || exit 1
aws --version || exit 1
aws sts get-caller-identity || exit 1
session-manager-plugin --version || exit 1
ansible --version || exit 1

echo "Environment validation complete."

# -------------------------------
# STEP 7: Generate Ansible Playbook
# -------------------------------
cat << 'EOF' > /root/install_openvas_docker.yml
---
- name: Install Greenbone (OpenVAS) via Docker on Ubuntu
  hosts: localhost
  connection: local
  become: yes
  vars:
    gvm_install_dir: "/opt/greenbone-community-container"
    gvm_compose_url: "https://greenbone.github.io/docs/latest/_static/compose.yaml"

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

# -------------------------------
# STEP 8: Run Playbook
# -------------------------------
echo "Running Ansible Playbook..."
ansible-playbook /root/install_openvas_docker.yml

echo "Provisioning complete! Greenbone containers are running."