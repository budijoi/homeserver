# ZTE B860H v1 Home Server Auto Installer
[![Platform: Linux arm64](https://img.shields.io/badge/Platform-Linux%20%7C%20arm64%20%2F%20aarch64-orange.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Skrip otomasi untuk mengubah Set-Top Box (STB) **ZTE B860H v1** (RAM 1GB, eMMC 8GB) menjadi *lightweight Home Server* yang tangguh menggunakan OS **Armbian Trixie (Debian 13) dengan Linux Kernel 6.x / arm64**.

## 🚀 Fitur Utama
- **LEMP Stack Teroptimasi:** NGINX Web Server terintegrasi mulus dengan PHP-FPM via Unix Socket, serta MariaDB Server.
- **Optimasi Memori Rendah (RAM 1GB):** - Alokasi otomatis **ZRAM 512MB** (kompresi RAM berbasis algoritma `lz4`).
  - Alokasi **Swapfile 1GB** di SDCARD untuk mengurangi siklus baca/tulis (*wear-tear*) pada eMMC internal.
- **Manajemen Berkas:** Otomatisasi instalasi **FileBrowser** pada port `8080` dengan isolasi *root directory* langsung ke SDCARD.
- **Akses Global (Tanpa Port Forwarding):** Terintegrasi dengan **Cloudflare Tunnel (`cloudflared` arm64)**.
- **Premium Command Center Dashboard (`index.php`):**
  - Desain modern *Premium Dark Mode* dengan sentuhan *Glassmorphism* (efek *backdrop-blur*).
  - Sinkronisasi data sistem secara *real-time* (Uptime, Suhu CPU, Load CPU, RAM, ZRAM, Swap, eMMC, SDCARD) via AJAX Fetch API tanpa *refresh* halaman (interval 5 detik).
  - **Live Network Monitor:** Menampilkan info IP lokal, ping latency ke internet, serta grafik teks kecepatan Download (RX) & Upload (TX) secara aktual.

## 🛠️ Persyaratan Perangkat
- Perangkat: ZTE B860H v1 (Amlogic S905X).
- OS Terinstal: [Armbian trixie](https://github.com/ophub/amlogic-s9xxx-armbian/releases/download/Armbian_trixie_arm64_server_2026.06/Armbian_26.05.0_amlogic_s905x-b860h_trixie_6.12.91_server_2026.06.01.img.gz) di Internal MMC
- Media Tambahan: MicroSD Card (SDCARD) sudah terpasang (akan otomatis diformat ke `ext4` oleh skrip jika tipenya tidak sesuai).

## 💻 Cara Instalasi

Hubungkan STB Anda melalui SSH, kemudian jalankan baris perintah berikut untuk mengunduh dan mengeksekusi skrip:

```bash
curl -O (https://raw.githubusercontent.com/budijoi/homeserver/main/installer.sh)
chmod +x installer.sh
sudo ./installer.sh
```

Tunggu hingga proses instalasi selesai.

## Konfigurasi Cloudflare Tunnel (Opsional)
Untuk menghubungkan server lokal Anda ke domain publik luar tanpa perlu IP Publik statis atau port forwarding, jalankan perintah ini via terminal setelah instalasi:
# 1. Login ke akun Cloudflare Anda
```cloudflared tunnel login```

# 2. Buat tunnel baru
```cloudflared tunnel create homeserver-b860h```

# 3. Hubungkan domain/subdomain Anda melalui Cloudflare Zero Trust Dashboard.

## 📂 Struktur Direktori Setelah Instalasi
/mnt/sdcard : Lokasi utama mounting SDCARD.

/var/www/html -> Symbolic Link ke /mnt/sdcard/www (Semua file web hosting disimpan aman di SDCARD).

/etc/filebrowser.db : Berkas basis data pengaturan user FileBrowser.

Dikembangkan khusus untuk efisiensi maksimum di atas arsitektur Amlogic S905X dengan memori terbatas.

## Screenshot

### Landing Page

Tambahkan screenshot di sini.

### File Browser

Tambahkan screenshot di sini.

## Lisensi

MIT License

---

## Author

B860H HomeServer Project
Powered by Armbian Linux
