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
  botocore \
  pyyaml \
  python-gvm \
  lxml

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
python3 -c "import yaml; print('PyYAML OK')" || exit 1
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
    sync_script_url: "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPOSITORY/main/sync_script.py"

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

    - name: Dynamically inject Nginx configuration fix into YAML
      shell: |
        python3 -c "
        import yaml

        with open('docker-compose.yml', 'r') as f:
            doc = yaml.safe_load(f)
            
        # 1. Fix PyYAML boolean conversion bug (Converts False back to 'no')
        for svc in doc.get('services', {}).values():
            if 'restart' in svc and isinstance(svc['restart'], bool):
                svc['restart'] = 'no' if svc['restart'] is False else 'always'
        
        # 2. Inject GVM-Config Environment Variables
        env = doc['services']['gvm-config'].setdefault('environment', {})
        env['ENABLE_NGINX_CONFIG'] = True
        env['ENABLE_TLS_GENERATION'] = True
        env['NGINX_HOST'] = '{{ public_ip }}'
        env['NGINX_HTTP_PORT'] = 80
        env['NGINX_ACCESS_CONTROL_ALLOW_ORIGIN_HEADER'] = 'http://{{ public_ip }}'
        
        # 3. Override Nginx Port Bindings to standard web ports
        doc['services']['nginx']['ports'] = ['80:80', '443:443']
        
        with open('docker-compose.yml', 'w') as f:
            yaml.safe_dump(doc, f, default_flow_style=False, sort_keys=False)
        "
      args:
        chdir: "{{ gvm_install_dir }}"

    - name: Pull Greenbone Docker images (with auto-resume for flaky registry)
      command: docker compose -f {{ gvm_install_dir }}/docker-compose.yml -p greenbone-community-edition pull
      args:
        chdir: "{{ gvm_install_dir }}"
      register: pull_result
      until: pull_result.rc == 0
      retries: 15
      delay: 10

    - name: Start Greenbone stack (Patiently waits for heavy SCAP extraction)
      command: docker compose -f docker-compose.yml -p greenbone-community-edition up -d
      args:
        chdir: "{{ gvm_install_dir }}"
      register: compose_up
      until: compose_up.rc == 0
      retries: 30
      delay: 60

    # ---------------------------------------------------------
    # Download Python Script & Setup Cron
    # ---------------------------------------------------------
    - name: Create directory for OpenVAS custom scripts
      file:
        path: /opt/openvas_scripts
        state: directory
        mode: '0755'

    - name: Download S3 Sync script from GitHub
      get_url:
        url: "{{ sync_script_url }}"
        dest: /opt/openvas_scripts/s3_sync.py
        mode: '0755' # Makes the script executable

    - name: Setup Cron Job to run S3 sync script hourly
      cron:
        name: "OpenVAS to S3 Report Sync"
        minute: "*/5"
        job: "/usr/bin/python3 /opt/openvas_scripts/s3_sync.py >> /var/log/openvas-s3-sync.log 2>&1"
EOF

# -------------------------------
# STEP 8: Run Playbook with Dynamic IP Injection
# -------------------------------
echo "Fetching EC2 Public IP via IMDSv2..."
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "Running Ansible Playbook for IP: $PUBLIC_IP..."
ansible-playbook /root/install_openvas_docker.yml -e "public_ip=$PUBLIC_IP"

echo "Provisioning complete! Greenbone containers are running."