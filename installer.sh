#!/bin/bash

# ==============================================================================
# Auto Installer Home Server ZTE B860H v1 (Armbian)
# Optimized for Armbian Trixie (Debian 13) - arm64
# Features: NGINX, PHP-FPM, MariaDB, FileBrowser, Cloudflare Tunnel, ZRAM, Swap
# Dashboard: Premium Dark Mode with Glassmorphism & AJAX Real-time Network Monitor
# ==============================================================================

# Definisi warna untuk output terminal
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}   STARTING HOME SERVER AUTO INSTALLER (B860H v1)     ${NC}"
echo -e "${CYAN}======================================================${NC}"

# 0. Pengecekan akses Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Harap jalankan skrip ini sebagai root atau gunakan sudo!${NC}"
  exit 1
fi

# 1. Update & Upgrade Sistem
echo -e "\n${YELLOW}[1/8] Memperbarui repositori dan paket sistem...${NC}"
apt update && apt upgrade -y

# 2. Setup dan Mount SDCARD
echo -e "\n${YELLOW}[2/8] Mendeteksi dan mengonfigurasi SDCARD...${NC}"
SD_DRIVE="/dev/mmcblk1"

if blockdev --getsize64 "$SD_DRIVE" > /dev/null 2>&1; then
    FSTYPE=$(blkid -o value -s TYPE $SD_DRIVE)
    if [ "$FSTYPE" != "ext4" ]; then
        echo -e "${GREEN}Memformat $SD_DRIVE ke ext4...${NC}"
        mkfs.ext4 -F $SD_DRIVE
    else
        echo -e "${GREEN}SDCARD terdeteksi dan sudah berformat ext4.${NC}"
    fi

    mkdir -p /mnt/sdcard
    
    if ! grep -q "$SD_DRIVE" /etc/fstab; then
        echo "$SD_DRIVE /mnt/sdcard ext4 defaults,noatime 0 2" >> /etc/fstab
    fi
    mount -a
    echo -e "${GREEN}SDCARD Berhasil di-mount ke /mnt/sdcard${NC}"
else
    echo -e "${RED}Peringatan: SDCARD ($SD_DRIVE) tidak ditemukan! Melanjutkan tanpa SDCARD.${NC}"
    mkdir -p /mnt/sdcard
fi

# 3. Optimasi RAM (ZRAM 512MB & Swapfile 1GB di SDCARD)
echo -e "\n${YELLOW}[3/8] Mengonfigurasi ZRAM dan Swapfile...${NC}"
if [ -d "/mnt/sdcard" ] && [ blockdev --getsize64 "$SD_DRIVE" > /dev/null 2>&1 ]; then
    if [ ! -f "/mnt/sdcard/swapfile" ]; then
        fallocate -l 1G /mnt/sdcard/swapfile
        chmod 600 /mnt/sdcard/swapfile
        mkswap /mnt/sdcard/swapfile
        swapon /mnt/sdcard/swapfile
        if ! grep -q "/mnt/sdcard/swapfile" /etc/fstab; then
            echo "/mnt/sdcard/swapfile none swap sw 0 0" >> /etc/fstab
        fi
        echo -e "${GREEN}Swapfile 1GB berhasil dibuat di SDCARD.${NC}"
    else
        echo -e "${GREEN}Swapfile sudah ada.${NC}"
    fi
fi

apt install zram-tools -y
echo -e "ALGO=lz4\nALLOCATION=512" > /etc/default/zramswap
systemctl restart zramswap
echo -e "${GREEN}ZRAM 512MB berhasil diaktifkan.${NC}"

# 4. Install Web Server (LEMP Stack)
echo -e "\n${YELLOW}[4/8] Menginstal NGINX, MariaDB, dan PHP-FPM...${NC}"
apt install nginx mariadb-server php-fpm php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip -y

mkdir -p /mnt/sdcard/www
rm -rf /var/www/html
ln -s /mnt/sdcard/www /var/www/html

chown -R www-data:www-data /mnt/sdcard/www
chmod -R 755 /mnt/sdcard/www
chmod o+x /mnt/sdcard

# 5. Konfigurasi NGINX & PHP-FPM
echo -e "\n${YELLOW}[5/8] Mengonfigurasi Virtual Host NGINX...${NC}"
PHP_SOCK=$(ls /run/php/php*-fpm.sock | head -n 1)

cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;
    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:__PHP_SOCKET_PLACEHOLDER__;
    }
}
EOF

sed -i "s|__PHP_SOCKET_PLACEHOLDER__|$PHP_SOCK|g" /etc/nginx/sites-available/default

if nginx -t > /dev/null 2>&1; then
    systemctl restart nginx
    echo -e "${GREEN}NGINX berhasil dikonfigurasi.${NC}"
else
    echo -e "${RED}Error: NGINX gagal restart, cek konfigurasi.${NC}"
fi

# 6. Install FileBrowser
echo -e "\n${YELLOW}[6/8] Menginstal FileBrowser...${NC}"
curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

rm -f /etc/filebrowser.db
filebrowser config init -a '0.0.0.0' -p 8080 -d /etc/filebrowser.db -r /mnt/sdcard
filebrowser users add admin admin12345678 --perm.admin -d /etc/filebrowser.db

cat << 'EOF' > /etc/systemd/system/filebrowser.service
[Unit]
Description=FileBrowser Manager
After=network.target

[Service]
ExecStart=/usr/local/bin/filebrowser -d /etc/filebrowser.db
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now filebrowser
echo -e "${GREEN}FileBrowser berjalan pada port 8080.${NC}"

# 7. Install Cloudflare Tunnel
echo -e "\n${YELLOW}[7/8] Menginstal Cloudflare Tunnel (arm64)...${NC}"
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -O cloudflared.deb
dpkg -i cloudflared.deb
rm cloudflared.deb

# 8. Setup Premium Dashboard Monitor
echo -e "\n${YELLOW}[8/8] Membangun Dashboard Monitor (AJAX)...${NC}"
rm -f /var/www/html/index.nginx-debian.html

cat << 'EOF' > /var/www/html/index.php
<?php
if (isset($_GET['ajax'])) {
    header('Content-Type: application/json');

    $uptime_str = 'N/A';
    if (file_exists('/proc/uptime')) {
        $uptime_seconds = (int) explode('.', file_get_contents('/proc/uptime'))[0];
        $days = floor($uptime_seconds / 86400);
        $hours = floor(($uptime_seconds % 86400) / 3600);
        $minutes = floor(($uptime_seconds % 3600) / 60);
        $uptime_str = "{$days}d {$hours}h {$minutes}m";
    }

    $load = sys_getloadavg();
    $cpu_usage_raw = shell_exec("top -bn1 | awk '/Cpu\(s\):/ {print $2 + $4}'");
    $cpu_usage = $cpu_usage_raw ? round((float)$cpu_usage_raw, 1) : 0;

    $cpu_temp = 'N/A';
    if (file_exists('/sys/class/thermal/thermal_zone0/temp')) {
        $temp_raw = file_get_contents('/sys/class/thermal/thermal_zone0/temp');
        $cpu_temp = round($temp_raw / 1000, 1);
    }

    $free_output = shell_exec('free -m');
    $free_lines = explode("\n", trim($free_output));
    
    $mem_data = preg_split('/\s+/', $free_lines[1]);
    $ram_total = isset($mem_data[1]) ? $mem_data[1] : 0;
    $ram_used = isset($mem_data[2]) ? $mem_data[2] : 0;
    $ram_percent = $ram_total > 0 ? round(($ram_used / $ram_total) * 100) : 0;

    $swap_data = preg_split('/\s+/', $free_lines[2]);
    $swap_total = isset($swap_data[1]) ? $swap_data[1] : 0;
    $swap_used = isset($swap_data[2]) ? $swap_data[2] : 0;
    $swap_percent = $swap_total > 0 ? round(($swap_used / $swap_total) * 100) : 0;

    $zram_total_mb = 0; $zram_used_mb = 0;
    if (file_exists('/sys/block/zram0/disksize')) {
        $zram_total_mb = round(trim(file_get_contents('/sys/block/zram0/disksize')) / 1048576);
    }
    if (file_exists('/sys/block/zram0/mm_stat')) {
        $mm_stat = preg_split('/\s+/', trim(file_get_contents('/sys/block/zram0/mm_stat')));
        $zram_used_mb = round($mm_stat[0] / 1048576);
    }
    $zram_percent = $zram_total_mb > 0 ? round(($zram_used_mb / $zram_total_mb) * 100) : 0;

    function getDiskData($path) {
        if (!is_dir($path)) return ['used' => '0 GB', 'total' => '0 GB', 'percent' => 0];
        $total = disk_total_space($path);
        $free = disk_free_space($path);
        $used = $total - $free;
        $percent = $total > 0 ? round(($used / $total) * 100) : 0;
        return [
            'used' => round($used / 1073741824, 2) . ' GB',
            'total' => round($total / 1073741824, 2) . ' GB',
            'percent' => $percent
        ];
    }
    $emmc = getDiskData('/');
    $sdcard = getDiskData('/mnt/sdcard');

    $net_iface = trim(shell_exec("ip route get 1.1.1.1 | awk '{print $5; exit}'"));
    if (!$net_iface) $net_iface = 'eth0'; 

    $local_ip = trim(shell_exec("ip -4 addr show $net_iface | grep -oP '(?<=inet\s)\d+(\.\d+){3}'"));
    $rx_bytes = (float) @file_get_contents("/sys/class/net/$net_iface/statistics/rx_bytes");
    $tx_bytes = (float) @file_get_contents("/sys/class/net/$net_iface/statistics/tx_bytes");

    $ping_raw = shell_exec("ping -c 1 -W 1 1.1.1.1 | grep time= | awk -F'time=' '{print $2}' | awk '{print $1}'");
    $ping = $ping_raw ? round((float)$ping_raw) . ' ms' : 'Offline';

    echo json_encode([
        'uptime' => $uptime_str, 'cpu_usage' => $cpu_usage, 'cpu_temp' => $cpu_temp,
        'load_0' => round($load[0], 2), 'load_1' => round($load[1], 2), 'load_2' => round($load[2], 2),
        'ram_used' => $ram_used, 'ram_total' => $ram_total, 'ram_percent' => $ram_percent,
        'zram_used' => $zram_used_mb, 'zram_total' => $zram_total_mb, 'zram_percent' => $zram_percent,
        'swap_used' => $swap_used, 'swap_total' => $swap_total, 'swap_percent' => $swap_percent,
        'emmc' => $emmc, 'sdcard' => $sdcard, 'net_iface' => $net_iface,
        'local_ip' => $local_ip ? $local_ip : 'Disconnected', 'ping' => $ping,
        'rx_bytes' => $rx_bytes, 'tx_bytes' => $tx_bytes
    ]);
    exit;
}
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>B860H HomeServer</title>
    <style>
        :root { --bg-color: #0d0f12; --glass-bg: rgba(25, 27, 31, 0.6); --glass-border: rgba(255, 255, 255, 0.08); --accent: #3b82f6; --accent-hover: #60a5fa; --text-main: #f3f4f6; --text-muted: #9ca3af; --live-dot: #10b981; }
        body { font-family: 'Inter', -apple-system, sans-serif; background: linear-gradient(135deg, var(--bg-color) 0%, #1a1c23 100%); color: var(--text-main); margin: 0; padding: 40px 20px; text-align: center; min-height: 100vh; }
        .header-container { margin-bottom: 40px; }
        h1 { color: #ffffff; font-weight: 600; letter-spacing: -0.5px; margin-bottom: 5px; display: inline-flex; align-items: center; justify-content: center; gap: 10px; }
        .live-indicator { width: 10px; height: 10px; background-color: var(--live-dot); border-radius: 50%; box-shadow: 0 0 10px var(--live-dot); animation: pulse 2s infinite; }
        @keyframes pulse { 0% { opacity: 1; transform: scale(1); } 50% { opacity: 0.5; transform: scale(1.2); } 100% { opacity: 1; transform: scale(1); } }
        .subtitle { color: var(--text-muted); font-size: 0.95em; margin-bottom: 8px; }
        .uptime { font-size: 0.85em; background: rgba(255,255,255,0.05); padding: 4px 12px; border-radius: 20px; display: inline-block; color: #cbd5e1; border: 1px solid var(--glass-border); }
        .container { max-width: 1000px; margin: 0 auto; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 24px; }
        .card { background: var(--glass-bg); backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px); border: 1px solid var(--glass-border); padding: 24px; border-radius: 16px; box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3); transition: transform 0.3s ease; }
        .card:hover { transform: translateY(-5px); border-color: rgba(255,255,255,0.15); }
        .card h3 { margin: 0 0 15px 0; font-size: 1.1em; color: var(--text-muted); font-weight: 500; display: flex; justify-content: space-between; align-items: center;}
        .card.wide { grid-column: 1 / -1; }
        .net-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; text-align: left; }
        .net-box { padding: 15px; background: rgba(0,0,0,0.2); border-radius: 12px; border: 1px solid rgba(255,255,255,0.05); }
        .value-large { font-size: 2.2em; font-weight: 700; margin: 5px 0; background: -webkit-linear-gradient(#fff, #cbd5e1); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .value-unit { font-size: 0.4em; color: #9ca3af; -webkit-text-fill-color: initial; }
        .bar-bg { width: 100%; background: rgba(0,0,0,0.4); border-radius: 8px; overflow: hidden; margin-top: 15px; height: 8px; box-shadow: inset 0 1px 2px rgba(0,0,0,0.5); }
        .bar-fill { height: 100%; background: linear-gradient(90deg, #3b82f6, #8b5cf6); border-radius: 8px; transition: width 0.8s cubic-bezier(0.4, 0, 0.2, 1); }
        .bar-fill.warn { background: linear-gradient(90deg, #f59e0b, #ef4444); }
        .sub-text { margin-top:8px; font-size: 0.85em; color: var(--text-muted); }
        .btn { display: inline-block; margin-top: 50px; padding: 14px 32px; background: rgba(59, 130, 246, 0.1); color: var(--accent-hover); text-decoration: none; font-weight: 600; border-radius: 12px; border: 1px solid var(--accent); box-shadow: 0 4px 15px rgba(59, 130, 246, 0.2); transition: all 0.3s ease; }
        .btn:hover { background: var(--accent); color: #fff; box-shadow: 0 8px 25px rgba(59, 130, 246, 0.4); }
        .footer-info { margin-top: 40px; font-size: 0.85em; color: #4b5563; }
    </style>
</head>
<body>
<div class="container">
    <div class="header-container">
        <h1>System Monitor <div class="live-indicator" title="Live Update Active"></div></h1>
        <div class="subtitle">ZTE B860H &bull; Armbian &bull; Amlogic S905X</div>
        <div class="uptime">Uptime: <span id="val-uptime">Loading...</span></div>
    </div>
    <div class="grid">
        <div class="card">
            <h3><span>CPU Usage</span> <span id="val-temp" style="color:#f87171; font-size:0.9em;">-- °C</span></h3>
            <div class="value-large"><span id="val-cpu">--</span><span class="value-unit">%</span></div>
            <div class="sub-text" id="val-load">Load: -- &bull; -- &bull; --</div>
        </div>
        <div class="card">
            <h3>RAM Usage</h3>
            <div class="value-large"><span id="val-ram-u">--</span><span class="value-unit"> / <span id="val-ram-t">--</span> MB</span></div>
            <div class="bar-bg"><div class="bar-fill" id="bar-ram" style="width: 0%;"></div></div>
            <div class="sub-text"><span id="pct-ram">--</span>% Used</div>
        </div>
        <div class="card">
            <h3>ZRAM (Compression)</h3>
            <div class="value-large"><span id="val-zram-u">--</span><span class="value-unit"> / <span id="val-zram-t">--</span> MB</span></div>
            <div class="bar-bg"><div class="bar-fill" id="bar-zram" style="width: 0%;"></div></div>
            <div class="sub-text"><span id="pct-zram">--</span>% Used</div>
        </div>
        <div class="card">
            <h3>SWAP Usage</h3>
            <div class="value-large"><span id="val-swap-u">--</span><span class="value-unit"> / <span id="val-swap-t">--</span> MB</span></div>
            <div class="bar-bg"><div class="bar-fill" id="bar-swap" style="width: 0%;"></div></div>
            <div class="sub-text"><span id="pct-swap">--</span>% Used</div>
        </div>
        <div class="card">
            <h3>Storage (EMMC / Root)</h3>
            <div class="value-large" id="val-emmc-u">-- GB</div>
            <div class="bar-bg"><div class="bar-fill" id="bar-emmc" style="width: 0%;"></div></div>
            <div class="sub-text"><span id="pct-emmc">--</span>% of <span id="val-emmc-t">-- GB</span> Used</div>
        </div>
        <div class="card">
            <h3>Storage (SDCARD)</h3>
            <div class="value-large" id="val-sd-u">-- GB</div>
            <div class="bar-bg"><div class="bar-fill" id="bar-sd" style="width: 0%;"></div></div>
            <div class="sub-text"><span id="pct-sd">--</span>% of <span id="val-sd-t">-- GB</span> Used</div>
        </div>
        <div class="card wide">
            <h3><span>Network Status (<span id="val-net-iface">--</span>)</span> <span id="val-ping" style="color:var(--live-dot); font-size:0.9em;">-- ms</span></h3>
            <div class="net-grid">
                <div class="net-box">
                    <div class="sub-text" style="margin-top:0;">Local IP Address</div>
                    <div class="value-large" style="font-size: 1.6em;" id="val-ip">--</div>
                </div>
                <div class="net-box">
                    <div class="sub-text" style="margin-top:0;">Download (RX)</div>
                    <div class="value-large" style="font-size: 1.6em; background: -webkit-linear-gradient(#34d399, #10b981); -webkit-background-clip: text; -webkit-text-fill-color: transparent;" id="val-rx-speed">0.0 KB/s</div>
                    <div class="sub-text">Total: <span id="val-rx-total">--</span></div>
                </div>
                <div class="net-box">
                    <div class="sub-text" style="margin-top:0;">Upload (TX)</div>
                    <div class="value-large" style="font-size: 1.6em; background: -webkit-linear-gradient(#60a5fa, #3b82f6); -webkit-background-clip: text; -webkit-text-fill-color: transparent;" id="val-tx-speed">0.0 KB/s</div>
                    <div class="sub-text">Total: <span id="val-tx-total">--</span></div>
                </div>
            </div>
        </div>
    </div>
    <a href="http://<?= $_SERVER['SERVER_ADDR'] ?>:8080" class="btn" target="_blank">Launch FileBrowser</a>
    <div class="footer-info">PHP <?= phpversion() ?> &bull; <?= $_SERVER['SERVER_SOFTWARE'] ?> &bull; Auto-refresh: 3s</div>
</div>
<script>
    let lastRx = 0, lastTx = 0, lastTime = 0;
    function formatBytes(bytes) { if (bytes === 0) return '0 B'; const k = 1024, sizes = ['B', 'KB', 'MB', 'GB', 'TB'], i = Math.floor(Math.log(bytes) / Math.log(k)); return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]; }
    function formatSpeed(bytesPerSec) { if (bytesPerSec === 0) return '0.0 KB/s'; if (bytesPerSec < 1048576) return (bytesPerSec / 1024).toFixed(1) + ' KB/s'; return (bytesPerSec / 1048576).toFixed(1) + ' MB/s'; }
    function updateMetrics() {
        fetch('?ajax=1').then(r => r.json()).then(data => {
            document.getElementById('val-uptime').innerText = data.uptime; document.getElementById('val-cpu').innerText = data.cpu_usage; document.getElementById('val-temp').innerText = data.cpu_temp + ' °C'; document.getElementById('val-load').innerHTML = `Load: ${data.load_0} &bull; ${data.load_1} &bull; ${data.load_2}`;
            const setCard = (prefix, used, total, pct) => { document.getElementById(`val-${prefix}-u`).innerText = used; if(document.getElementById(`val-${prefix}-t`)) document.getElementById(`val-${prefix}-t`).innerText = total; document.getElementById(`pct-${prefix}`).innerText = pct; const bar = document.getElementById(`bar-${prefix}`); bar.style.width = pct + '%'; if(pct > 85) bar.classList.add('warn'); else bar.classList.remove('warn'); };
            setCard('ram', data.ram_used, data.ram_total, data.ram_percent); setCard('zram', data.zram_used, data.zram_total, data.zram_percent); setCard('swap', data.swap_used, data.swap_total, data.swap_percent); setCard('emmc', data.emmc.used, data.emmc.total, data.emmc.percent); setCard('sd', data.sdcard.used, data.sdcard.total, data.sdcard.percent);
            document.getElementById('val-net-iface').innerText = data.net_iface; document.getElementById('val-ip').innerText = data.local_ip; document.getElementById('val-ping').innerText = 'Ping: ' + data.ping; document.getElementById('val-rx-total').innerText = formatBytes(data.rx_bytes); document.getElementById('val-tx-total').innerText = formatBytes(data.tx_bytes);
            const now = Date.now();
            if (lastTime > 0) { const timeDiff = (now - lastTime) / 1000; document.getElementById('val-rx-speed').innerText = formatSpeed(Math.max(0, (data.rx_bytes - lastRx) / timeDiff)); document.getElementById('val-tx-speed').innerText = formatSpeed(Math.max(0, (data.tx_bytes - lastTx) / timeDiff)); }
            lastRx = data.rx_bytes; lastTx = data.tx_bytes; lastTime = now;
        }).catch(e => console.error('Error fetching data:', e));
    }
    updateMetrics(); setInterval(updateMetrics, 3000);
</script>
</body>
</html>
EOF

echo -e "\n${CYAN}======================================================${NC}"
echo -e "${GREEN}   INSTALASI BERHASIL DAN SELESAI!                    ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "1. ${YELLOW}Dashboard Monitor:${NC} Akses http://<IP>"
echo -e "2. ${YELLOW}FileBrowser:${NC} Akses http://<IP>:8080 (Login: admin / admin12345678)"
echo -e "3. ${YELLOW}Cloudflare Tunnel:${NC} Ketik 'cloudflared tunnel login' di terminal."
echo -e "======================================================\n"
