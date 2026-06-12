#!/bin/bash

set -e

VERSION="3.0"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STORAGE=""

echo "====================================="
echo " Budijoi Home Server Installer v$VERSION"
echo "====================================="
echo

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Jalankan sebagai root${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/10] Update Sistem${NC}"

apt update
apt upgrade -y

echo
echo -e "${YELLOW}[2/10] Deteksi Storage${NC}"

DEVICE=$(lsblk -dpno NAME,SIZE,TYPE | grep disk | grep -v "$(findmnt -n -o SOURCE /)" | sort -k2 -h | tail -1 | awk '{print $1}')

if [ -z "$DEVICE" ]; then
    echo -e "${RED}Storage eksternal tidak ditemukan${NC}"
    exit 1
fi

echo "Storage dipilih : $DEVICE"

FSTYPE=$(blkid -o value -s TYPE ${DEVICE} 2>/dev/null)

if [ "$FSTYPE" != "ext4" ]; then
    echo "Format ext4..."
    mkfs.ext4 -F $DEVICE
fi

mkdir -p /mnt/storage

UUID=$(blkid -s UUID -o value $DEVICE)

grep -q "$UUID" /etc/fstab || \
echo "UUID=$UUID /mnt/storage ext4 defaults,noatime,nodiratime 0 2" >> /etc/fstab

mount -a

df -h /mnt/storage

echo
echo -e "${YELLOW}[3/10] Setup Swap${NC}"

if [ ! -f /mnt/storage/swapfile ]; then

    fallocate -l 1G /mnt/storage/swapfile

    chmod 600 /mnt/storage/swapfile

    mkswap /mnt/storage/swapfile

    echo "/mnt/storage/swapfile none swap sw 0 0" >> /etc/fstab

fi

swapon -a

echo
echo -e "${YELLOW}[4/10] Install ZRAM${NC}"

apt install -y zram-tools

cat > /etc/default/zramswap <<EOF
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

systemctl restart zramswap

echo
echo -e "${YELLOW}[5/10] Install LEMP${NC}"

apt install -y \
nginx \
mariadb-server \
php-fpm \
php-cli \
php-mysql \
php-curl \
php-gd \
php-mbstring \
php-xml \
php-zip \
curl \
wget \
jq \
unzip

mkdir -p /mnt/storage/www

rm -rf /var/www/html

ln -s /mnt/storage/www /var/www/html

chown -R www-data:www-data /mnt/storage/www

echo
echo -e "${YELLOW}[6/10] Pindah MariaDB ke Storage${NC}"

systemctl stop mariadb

mkdir -p /mnt/storage/mysql

rsync -a /var/lib/mysql/ /mnt/storage/mysql/

mv /var/lib/mysql /var/lib/mysql.bak

ln -s /mnt/storage/mysql /var/lib/mysql

chown -R mysql:mysql /mnt/storage/mysql

systemctl start mariadb

echo
echo -e "${YELLOW}[7/10] Install FileBrowser${NC}"

curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

filebrowser config init \
-a 0.0.0.0 \
-p 8080 \
-d /mnt/storage/filebrowser.db \
-r /mnt/storage

filebrowser users add admin admin123456 \
--perm.admin \
-d /mnt/storage/filebrowser.db

cat > /etc/systemd/system/filebrowser.service <<EOF
[Unit]
Description=FileBrowser

[Service]
ExecStart=/usr/local/bin/filebrowser \
-d /mnt/storage/filebrowser.db

Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now filebrowser

mkdir -p /mnt/storage/log/nginx

systemctl stop nginx

rm -rf /var/log/nginx

ln -s /mnt/storage/log/nginx /var/log/nginx

systemctl start nginx

echo
echo -e "${YELLOW}[8/10] Cloudflared${NC}"

wget -q \
https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb \
-O cloudflared.deb

dpkg -i cloudflared.deb

rm cloudflared.deb

mkdir -p /mnt/storage/cloudflared

echo
echo "====================================="
echo " INSTALLATION COMPLETE"
echo "====================================="
echo
echo "Storage : /mnt/storage"
echo "WebRoot : /mnt/storage/www"
echo "MariaDB : /mnt/storage/mysql"
echo "FileBrowser : http://IP:8080"
echo
