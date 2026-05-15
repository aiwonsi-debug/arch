#!/bin/bash
# ============================================================
# setup.sh — All-in-one Arch Linux Install
# Hardware : i5-6400T / 8GB RAM / sda4 30GB / UEFI
# Software : Sway + Brave + FreeRDP
# ============================================================
# วิธีใช้ (ใน Arch Live USB):
#   curl -O https://raw.githubusercontent.com/aiwonsi-debug/arch/main/setup.sh
#   chmod +x setup.sh && ./setup.sh
# ============================================================

set -e

# ============================================================
# CONFIG
# ============================================================
WIFI_SSID="TRUE_5G"
WIFI_PASS="0969639564"
ROOT_PASS="root"
USERNAME="arch"
USER_PASS="arch"
HOSTNAME="archlinux"
ROOT_PART="/dev/sda4"
EFI_PART="/dev/sda1"
EFI_DISK="/dev/sda"
EFI_PARTNUM="1"
TIMEZONE="Asia/Bangkok"
RDP_HOST="100.123.121.34"
RDP_PORT="3389"
RDP_USER="psc-cm"

# ============================================================
echo ">>> [1/9] ตรวจสอบ UEFI"
# ============================================================
if [ ! -d /sys/firmware/efi/efivars ]; then
  echo "ERROR: ไม่ได้ boot แบบ UEFI"
  exit 1
fi
echo "    OK"

# ============================================================
echo ">>> [2/9] เชื่อมต่อ WiFi: ${WIFI_SSID}"
# ============================================================
if ! ping -c 1 -W 2 archlinux.org &>/dev/null; then
  iwctl --passphrase "${WIFI_PASS}" station wlan0 connect "${WIFI_SSID}" || true
  sleep 5
  if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
    echo "ERROR: WiFi ไม่ได้เชื่อมต่อ ตรวจสอบ SSID/password"
    exit 1
  fi
fi
echo "    OK"

# ============================================================
echo ">>> [3/9] Clock + Mirror"
# ============================================================
timedatectl set-ntp true
reflector --country Thailand,Singapore --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
echo "    OK"

# ============================================================
echo ">>> [4/9] Format + Mount"
# ============================================================
echo "    WARNING: กำลัง format ${ROOT_PART} — กด Enter ยืนยัน / Ctrl+C ยกเลิก"
read -r

# ลบไฟล์ที่ค้างจาก install ครั้งก่อน
umount -R /mnt 2>/dev/null || true
rm -f /tmp/efi_mounted

mkfs.ext4 -F "${ROOT_PART}"
mount "${ROOT_PART}" /mnt
mkdir -p /mnt/boot
mount "${EFI_PART}" /mnt/boot
echo "    OK"

# ============================================================
echo ">>> [5/9] pacstrap"
# ============================================================
# ลบไฟล์ที่อาจขัดแย้ง
rm -f /mnt/boot/intel-ucode.img
rm -f /mnt/boot/initramfs-linux.img
rm -f /mnt/boot/vmlinuz-linux

pacstrap -K /mnt \
  base linux linux-firmware linux-headers \
  base-devel \
  intel-ucode \
  networkmanager \
  iwd \
  vim git sudo \
  man-db \
  pipewire pipewire-pulse wireplumber \
  mesa intel-media-driver vulkan-intel libva-utils \
  sway swaybar swaybg swaylock \
  foot \
  wofi \
  waybar \
  xdg-desktop-portal-wlr xdg-utils \
  polkit wl-clipboard \
  grim slurp \
  dunst libnotify \
  freerdp \
  ttf-dejavu

echo "    OK"

# ============================================================
echo ">>> [6/9] fstab"
# ============================================================
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab

# ============================================================
echo ">>> [7/9] chroot — ตั้งค่าระบบ"
# ============================================================
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
echo "    Root UUID: ${ROOT_UUID}"

arch-chroot /mnt /bin/bash <<CHROOT_EOF
set -e

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

# Passwords — ใช้ chpasswd เพราะไม่มี TTY ใน heredoc
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USER_PASS}" | chpasswd

# sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# systemd-boot
bootctl install --force 2>/dev/null || bootctl update

cat > /boot/loader/entries/arch.conf <<BOOT
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw quiet
BOOT

cat > /boot/loader/loader.conf <<LOADER
default  arch.conf
timeout  3
console-mode max
editor   no
LOADER

# BIOS workaround — copy systemd-boot ไปแทน Windows Boot Manager
# เพื่อให้ BIOS ที่ hardcode path \EFI\Microsoft\Boot\bootmgfw.efi สามารถ boot ได้
mkdir -p /boot/EFI/Microsoft/Boot
if [ -f /boot/EFI/Microsoft/Boot/bootmgfw.efi ]; then
  cp /boot/EFI/Microsoft/Boot/bootmgfw.efi \
     /boot/EFI/Microsoft/Boot/bootmgfw.efi.bak
fi
cp /boot/EFI/systemd/systemd-bootx64.efi \
   /boot/EFI/Microsoft/Boot/bootmgfw.efi

# efibootmgr — สร้าง entry และตั้ง boot order
pacman -S --noconfirm efibootmgr

# ลบ Linux entry เก่าที่อาจ disabled อยู่
for num in \$(efibootmgr | grep -i "linux boot manager" | grep -oP 'Boot\K[0-9A-F]+'); do
  efibootmgr --delete-bootnum --bootnum "\$num" 2>/dev/null || true
done

# สร้าง entry ใหม่
efibootmgr \
  --create \
  --disk ${EFI_DISK} \
  --part ${EFI_PARTNUM} \
  --label "Linux Boot Manager" \
  --loader "\EFI\systemd\systemd-bootx64.efi"

# ดึงเลข entry ใหม่
NEW_ENTRY=\$(efibootmgr | grep "Linux Boot Manager" | grep -oP 'Boot\K[0-9A-F]+' | head -1)
WIN_ENTRY=\$(efibootmgr | grep -i "windows" | grep -oP 'Boot\K[0-9A-F]+' | head -1)

efibootmgr --bootnum "\$NEW_ENTRY" --active
efibootmgr --bootorder "\${NEW_ENTRY},\${WIN_ENTRY}"

echo "    Boot order:"
efibootmgr

# WiFi — ตั้งค่า NetworkManager ล่วงหน้า
mkdir -p /etc/NetworkManager/system-connections
cat > /etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection <<NMCONF
[connection]
id=${WIFI_SSID}
type=wifi
autoconnect=true

[wifi]
ssid=${WIFI_SSID}
mode=infrastructure

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PASS}

[ipv4]
method=auto

[ipv6]
method=auto
NMCONF
chmod 600 /etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection

# Services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd

echo "    chroot: OK"
CHROOT_EOF

# ============================================================
echo ">>> [8/9] ตั้งค่า dotfiles สำหรับ user arch"
# ============================================================
USERHOME="/mnt/home/${USERNAME}"
mkdir -p "${USERHOME}/.config/sway"
mkdir -p "${USERHOME}/.config/waybar"
mkdir -p "${USERHOME}/.config/foot"
mkdir -p "${USERHOME}/.config/environment.d"
mkdir -p "${USERHOME}/bin"
mkdir -p "${USERHOME}/Pictures"

# ---- Sway config ----
cat > "${USERHOME}/.config/sway/config" <<'SWAYCONF'
# ---- Variables ----
set $mod Mod4
set $term foot
set $menu wofi --show drun

# ---- Output ----
output * bg #1d1f21 solid_color

# ---- Input ----
input type:keyboard {
    repeat_delay 300
    repeat_rate 50
}

# ---- Key Bindings ----
bindsym $mod+Return exec $term
bindsym $mod+d exec $menu
bindsym $mod+b exec brave --ozone-platform=wayland
bindsym $mod+r exec ~/bin/rdp
bindsym $mod+Shift+c kill
bindsym $mod+Shift+q exit
bindsym $mod+f fullscreen
bindsym $mod+space floating toggle

# Focus
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

# Move
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

# Resize
bindsym $mod+ctrl+h resize shrink width 50px
bindsym $mod+ctrl+l resize grow width 50px
bindsym $mod+ctrl+j resize grow height 50px
bindsym $mod+ctrl+k resize shrink height 50px

# Workspaces
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5

# Screenshot
bindsym $mod+Print exec grim ~/Pictures/ss-$(date +%Y%m%d-%H%M%S).png
bindsym $mod+Shift+Print exec grim -g "$(slurp)" ~/Pictures/ss-$(date +%Y%m%d-%H%M%S).png

# ---- Layout ----
default_border pixel 2
gaps inner 6
gaps outer 4

# ---- Colors ----
client.focused          #81a2be #1d1f21 #c5c8c6 #81a2be #81a2be
client.unfocused        #1d1f21 #1d1f21 #969896 #1d1f21 #1d1f21

# ---- Bar ----
bar {
    swaybar_command waybar
}

# ---- Autostart ----
exec dunst
exec /usr/lib/xdg-desktop-portal-wlr
exec sleep 0.5 && /usr/lib/xdg-desktop-portal
SWAYCONF

# ---- Waybar config ----
cat > "${USERHOME}/.config/waybar/config" <<'WBCONF'
{
  "layer": "top",
  "position": "top",
  "height": 26,
  "modules-left": ["sway/workspaces"],
  "modules-center": ["sway/window"],
  "modules-right": ["network","memory","cpu","clock"],
  "sway/workspaces": { "disable-scroll": true },
  "clock": { "format": "{:%H:%M  %d/%m/%Y}" },
  "cpu": { "format": "CPU {usage}%", "interval": 3 },
  "memory": { "format": "RAM {}%", "interval": 10 },
  "network": {
    "format-ethernet": "ETH {ipaddr}",
    "format-wifi": "WIFI {signalStrength}%",
    "format-disconnected": "NO NET"
  }
}
WBCONF

cat > "${USERHOME}/.config/waybar/style.css" <<'WBCSS'
* { font-family: monospace; font-size: 12px; border: none; border-radius: 0; margin: 0; padding: 0 6px; }
window#waybar { background: #1d1f21; color: #c5c8c6; }
#workspaces button { color: #969896; padding: 0 4px; }
#workspaces button.focused { color: #81a2be; font-weight: bold; }
#clock, #cpu, #memory, #network { padding: 0 8px; }
WBCSS

# ---- Foot terminal config ----
cat > "${USERHOME}/.config/foot/foot.ini" <<'FOOTCONF'
[main]
font=monospace:size=11
pad=8x8

[colors]
background=1d1f21
foreground=c5c8c6
FOOTCONF

# ---- Environment Variables ----
cat > "${USERHOME}/.config/environment.d/wayland.conf" <<'ENVCONF'
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=sway
XDG_CURRENT_DESKTOP=sway
LIBVA_DRIVER_NAME=iHD
SWAYLOCK_EFFECTS_ENABLED=0
ENVCONF

# ---- FreeRDP script ----
cat > "${USERHOME}/bin/rdp" <<RDPSCRIPT
#!/bin/bash
HOST=\${1:-${RDP_HOST}}
PORT=\${2:-${RDP_PORT}}
USER=\${3:-${RDP_USER}}
xfreerdp \
  /v:\$HOST:\$PORT \
  /u:\$USER \
  /dynamic-resolution \
  /rfx \
  /gfx \
  +clipboard \
  /cert:ignore
RDPSCRIPT
chmod +x "${USERHOME}/bin/rdp"

# ---- Auto-start Sway จาก TTY1 ----
cat >> "${USERHOME}/.bash_profile" <<'PROFILE'

export PATH="$HOME/bin:$PATH"
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
  exec sway
fi
PROFILE

cat >> "${USERHOME}/.bashrc" <<'BASHRC'
export PATH="$HOME/bin:$PATH"
BASHRC

# ---- สร้าง post-install script สำหรับติดตั้ง Brave (ต้องรันหลัง reboot) ----
cat > "${USERHOME}/install-brave.sh" <<'BRAVESCRIPT'
#!/bin/bash
# รันหลัง reboot เข้า Arch แล้ว login เป็น arch
# bash ~/install-brave.sh

set -e
echo ">>> ติดตั้ง paru"
cd /tmp
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin
makepkg -si --noconfirm
cd ~

echo ">>> ติดตั้ง Brave"
paru -S --noconfirm brave-bin

echo ""
echo "Brave ติดตั้งเสร็จแล้ว"
echo "รัน: sway   หรือ logout แล้ว login ใหม่"
BRAVESCRIPT
chmod +x "${USERHOME}/install-brave.sh"

# ---- แก้ permissions ----
arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

# ============================================================
echo ">>> [9/9] เสร็จสมบูรณ์"
# ============================================================
umount -R /mnt

echo ""
echo "============================================================"
echo " setup.sh เสร็จสมบูรณ์"
echo "============================================================"
echo ""
echo " ขั้นตอนต่อไป:"
echo "   1. reboot (ถอด USB ระหว่าง reboot)"
echo "   2. เลือก Arch Linux ใน boot menu"
echo "   3. login: arch / arch"
echo "   4. bash ~/install-brave.sh   (ติดตั้ง Brave)"
echo "   5. sway จะ start อัตโนมัติเมื่อ login ครั้งถัดไป"
echo ""
echo " Keybinding:"
echo "   Super+Enter    = terminal (foot)"
echo "   Super+D        = launcher (wofi)"
echo "   Super+B        = Brave"
echo "   Super+R        = FreeRDP -> ${RDP_HOST}:${RDP_PORT}"
echo "   Super+Shift+C  = ปิด window"
echo "   Super+Shift+Q  = ออกจาก Sway"
echo "   Super+1-5      = workspace"
echo "   Super+F        = fullscreen"
echo "============================================================"
