#!/bin/bash

# Exit on error
set -e

echo "Updating system and installing build dependencies..."
sudo apt update -y

# Install and enable SSM Agent
snap install amazon-ssm-agent --classic

systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service

sudo apt install -y build-essential wget curl unzip git libssl-dev libxml2-dev \
libpcre3-dev zlib1g-dev libncurses5-dev openjdk-8-jdk php php-mysql \
mysql-server apache2 libreadline-dev libcap-dev net-tools

WORKDIR=/opt/vulnapps
sudo mkdir -p $WORKDIR
sudo chown $USER:$USER $WORKDIR
cd $WORKDIR

# --- ProFTPD 1.3.5e ---
echo "Installing ProFTPD 1.3.5e..."
wget -q https://github.com/proftpd/proftpd/archive/refs/tags/v1.3.5e.tar.gz -O proftpd-1.3.5e.tar.gz
tar -xzf proftpd-1.3.5e.tar.gz
cd proftpd-1.3.5e
./configure --prefix=$WORKDIR/proftpd CFLAGS="-fcommon"
make -j$(nproc)
sudo make install
cd .. && rm -rf proftpd-1.3.5e*

# --- Struts 2.3.20.1 (FIXED PATH LOGIC) ---
echo "Downloading Struts 2.3.20.1..."
wget -q https://archive.apache.org/dist/struts/2.3.20.1/struts-2.3.20.1-all.zip
unzip -q struts-2.3.20.1-all.zip -d struts_temp
# Move contents up one level to flatten the directory structure
mkdir -p $WORKDIR/struts
mv struts_temp/struts-2.3.20.1/* $WORKDIR/struts/
rm -rf struts_temp struts-2.3.20.1-all.zip

# --- Tomcat 8.5.15 ---
echo "Installing Tomcat 8.5.15..."
wget -q https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.15/bin/apache-tomcat-8.5.15.tar.gz
tar -xzf apache-tomcat-8.5.15.tar.gz
mv apache-tomcat-8.5.15 $WORKDIR/tomcat
rm apache-tomcat-8.5.15.tar.gz

# --- Drupal 7.31 ---
echo "Installing Drupal 7.31..."
wget -q https://ftp.drupal.org/files/projects/drupal-7.31.tar.gz
tar -xzf drupal-7.31.tar.gz
sudo mv drupal-7.31 /var/www/html/drupal
sudo chown -R www-data:www-data /var/www/html/drupal
rm drupal-7.31.tar.gz

# --- WordPress 4.7.1 ---
echo "Installing WordPress 4.7.1..."
wget -q https://wordpress.org/wordpress-4.7.1.tar.gz
tar -xzf wordpress-4.7.1.tar.gz
sudo mv wordpress /var/www/html/wordpress
sudo chown -R www-data:www-data /var/www/html/wordpress
rm wordpress-4.7.1.tar.gz

# --- Elasticsearch 1.1.1 (RCE) ---
echo "Installing Elasticsearch 1.1.1..."
wget -q https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.1.1.tar.gz
tar -xzf elasticsearch-1.1.1.tar.gz
mv elasticsearch-1.1.1 $WORKDIR/elasticsearch
rm elasticsearch-1.1.1.tar.gz

# =================================================
# SERVICE ACTIVATION & NETWORK CONFIGURATION
# =================================================
echo "Configuring network visibility and starting services..."

# 1. Start ProFTPD
sudo $WORKDIR/proftpd/sbin/proftpd -c $WORKDIR/proftpd/etc/proftpd.conf || true

# 2. Deploy Struts Sample Apps to Tomcat & Start (FIXED PATH)
cp $WORKDIR/struts/apps/*.war $WORKDIR/tomcat/webapps/
sudo $WORKDIR/tomcat/bin/startup.sh || true

# 3. Configure Elasticsearch for Network Visibility
# Force bind to 0.0.0.0 so OpenVAS can see it
echo "network.host: 0.0.0.0" >> $WORKDIR/elasticsearch/config/elasticsearch.yml
sudo $WORKDIR/elasticsearch/bin/elasticsearch -d || true

# 4. Prepare Databases
sudo systemctl start mysql
sudo mysql -e "CREATE DATABASE IF NOT EXISTS wordpress; CREATE DATABASE IF NOT EXISTS drupal;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'labuser'@'localhost' IDENTIFIED BY 'password123';"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'labuser'@'localhost'; FLUSH PRIVILEGES;"

echo "================================================="
echo "Installation finished and Fixed!"
echo "-------------------------------------------------"
echo "Check active ports: sudo netstat -tulpn | grep -E '21|80|8080|9200'"
echo "================================================="