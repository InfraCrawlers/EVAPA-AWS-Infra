#!/bin/bash

echo "Updating system..."
sudo apt update -y

echo "Installing dependencies..."
sudo apt install -y \
build-essential \
wget curl unzip git \
libssl-dev libxml2-dev \
libpcre3-dev zlib1g-dev \
libncurses5-dev \
openjdk-8-jdk \
php php-mysql mysql-server \
apache2

WORKDIR=/opt/vulnapps

echo "Creating working directory..."
sudo mkdir -p $WORKDIR
sudo chown $USER:$USER $WORKDIR

cd $WORKDIR

echo "Installing ProFTPD 1.3.5"

wget https://ftp.proftpd.org/distrib/source/proftpd-1.3.5.tar.gz
tar -xzf proftpd-1.3.5.tar.gz
cd proftpd-1.3.5

./configure --prefix=$WORKDIR/proftpd
make
make install

cd ..

echo "Installing vsftpd 2.3.4"

wget https://security.appspot.com/downloads/vsftpd-2.3.4.tar.gz
tar -xzf vsftpd-2.3.4.tar.gz
cd vsftpd-2.3.4

make
mkdir -p $WORKDIR/vsftpd
cp vsftpd $WORKDIR/vsftpd/

cd ..

echo "Downloading Struts 2.3.1"

wget https://archive.apache.org/dist/struts/2.3.1/struts-2.3.1-all.zip
unzip struts-2.3.1-all.zip -d $WORKDIR/struts

echo "Installing Drupal 7.31"

wget https://ftp.drupal.org/files/projects/drupal-7.31.tar.gz
tar -xzf drupal-7.31.tar.gz

sudo mv drupal-7.31 /var/www/html/drupal

echo "Installing WordPress 4.7.1"

wget https://wordpress.org/wordpress-4.7.1.tar.gz
tar -xzf wordpress-4.7.1.tar.gz

sudo mv wordpress /var/www/html/wordpress

echo "Installing OpenSSL 1.0.1"

wget https://www.openssl.org/source/old/1.0.1/openssl-1.0.1.tar.gz
tar -xzf openssl-1.0.1.tar.gz

cd openssl-1.0.1

./config --prefix=$WORKDIR/openssl
make
make install

cd ..

echo "Installing Samba 3.5.0"

wget https://download.samba.org/pub/samba/stable/samba-3.5.0.tar.gz
tar -xzf samba-3.5.0.tar.gz

cd samba-3.5.0

./configure --prefix=$WORKDIR/samba
make
make install

cd ..

echo "Installing Elasticsearch 1.1.1"

wget https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.1.1.tar.gz
tar -xzf elasticsearch-1.1.1.tar.gz

mv elasticsearch-1.1.1 $WORKDIR/elasticsearch

echo "Installing Tomcat 8.5.15"

wget https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.15/bin/apache-tomcat-8.5.15.tar.gz
tar -xzf apache-tomcat-8.5.15.tar.gz

mv apache-tomcat-8.5.15 $WORKDIR/tomcat

echo "Installing Exim 4.89"

wget https://ftp.exim.org/pub/exim/exim4/exim-4.89.tar.xz

tar -xf exim-4.89.tar.xz

cd exim-4.89

make -j$(nproc)

mkdir -p $WORKDIR/exim
cp -r build-Linux-/ $WORKDIR/exim/ 2>/dev/null || true

cd ..

echo "================================"
echo "Installation finished"
echo "Apps installed in $WORKDIR"
echo "================================"