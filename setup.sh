#!/bin/bash
# ============================================================
# setup.sh — All-in-one Arch Linux Install
# Hardware : i5-6400T / 8GB RAM / sda4 30GB / UEFI Dual Boot
# Software : Sway + Brave + FreeRDP
# ============================================================
# curl -L https://is.gd/ueJOTU -o setup.sh
# chmod +x setup.sh && ./setup.sh
# ============================================================

# ============================================================
# CONFIG — แก้ค่าในส่วนนี้ก่อนรัน
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
LOG="/tmp/arch-install.log"

# ============================================================
# HELPERS
# ============================================================
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLU}>>>${NC} $*" | tee -a "$LOG"; }
ok()   { echo -e "    ${GRN}OK${NC}" | tee -a "$LOG"; }
warn() { echo -e "    ${YLW}WARN${NC} $*" | tee -a "$LOG"; }
die()  { echo -e "${RED}ERROR${NC} $*" | tee -a "$LOG"; exit 1; }

run() {
  "$@" >> "$LOG" 2>&1 || die "ล้มเหลวที่: $*"
}

echo "" > "$LOG"
echo "============================================================"
echo " Arch Linux Install — $(date)"
echo " Log: $LOG"
echo "============================================================"
echo ""

# ============================================================
log "[1/9] ตรวจสอบ UEFI"
# ============================================================
[ -d /sys/firmware/efi/efivars ] || die "ไม่ได้ boot แบบ UEFI"
ok

# ============================================================
log "[2/9] เชื่อมต่อ Internet"
# ============================================================
if ping -c 1 -W 2 archlinux.org &>/dev/null; then
  echo "    LAN: ใช้งานได้แล้ว"
else
  echo "    ลอง WiFi: ${WIFI_SSID}"
  # start iwd ถ้ายังไม่ได้ start
  systemctl start iwd 2>/dev/null || true
  sleep 1
  iwctl --passphrase "${WIFI_PASS}" station wlan0 connect "${WIFI_SSID}" 2>>"$LOG" || true
  sleep 5
  ping -c 1 -W 5 archlinux.org &>/dev/null || die "ไม่มี Internet — ตรวจสอบ SSID/password หรือเสียบสาย LAN"
fi
ok

# ============================================================
log "[3/9] Clock + Mirror"
# ============================================================
run timedatectl set-ntp true
run reflector --country Thailand,Singapore --latest 10 --sort rate \
  --save /etc/pacman.d/mirrorlist
ok

# ============================================================
log "[4/9] Format + Mount (${ROOT_PART})"
# ============================================================
echo ""
echo -e "  ${YLW}WARNING${NC}: จะ format ${ROOT_PART} — ข้อมูลจะหายถาวร"
lsblk "${EFI_DISK}"
echo ""
echo -n "  กด Enter เพื่อยืนยัน / Ctrl+C เพื่อยกเลิก: "
read -r

# unmount ถ้ามีค้างอยู่จาก attempt ก่อน
umount -R /mnt 2>/dev/null || true

run mkfs.ext4 -F "${ROOT_PART}"
run mount "${ROOT_PART}" /mnt
run mkdir -p /mnt/boot
run mount "${EFI_PART}" /mnt/boot
ok
lsblk "${EFI_DISK}"

# ============================================================
log "[5/9] pacstrap — ติดตั้ง base system"
# ============================================================
# ลบไฟล์ที่ขัดแย้งจาก attempt ก่อน
rm -f /mnt/boot/intel-ucode.img \
      /mnt/boot/initramfs-linux.img \
      /mnt/boot/vmlinuz-linux \
      /mnt/boot/initramfs-linux-fallback.img

pacstrap -K /mnt \
  base linux linux-firmware linux-headers \
  base-devel \
  intel-ucode \
  networkmanager iwd \
  vim git sudo \
  man-db \
  pipewire pipewire-pulse wireplumber \
  mesa intel-media-driver vulkan-intel libva-utils \
  sway swaybg swaylock \
  foot \
  wofi \
  waybar \
  xdg-desktop-portal-wlr xdg-utils \
  polkit wl-clipboard \
  grim slurp \
  dunst libnotify \
  freerdp \
  efibootmgr \
  ttf-dejavu \
  >> "$LOG" 2>&1 || die "pacstrap ล้มเหลว ดู $LOG"
ok

# ============================================================
log "[6/9] fstab"
# ============================================================
# ล้าง fstab ก่อนในกรณีที่ attempt ก่อนเขียนไว้แล้ว
: > /mnt/etc/fstab
run genfstab -U /mnt >> /mnt/etc/fstab
echo "    fstab:"
cat /mnt/etc/fstab | tee -a "$LOG"
ok

# ============================================================
log "[7/9] chroot — ตั้งค่าระบบ"
# ============================================================
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
echo "    Root UUID: ${ROOT_UUID}"

arch-chroot /mnt /bin/bash <<CHROOT_EOF
set -e

# ---- Timezone ----
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo "    Timezone: OK"

# ---- Locale ----
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen > /dev/null
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "    Locale: OK"

# ---- Hostname ----
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS
echo "    Hostname: OK"

# ---- Passwords (chpasswd — ไม่ต้องการ TTY) ----
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USER_PASS}" | chpasswd
echo "    Passwords: OK"

# ---- sudo ----
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo "    sudo: OK"

# ---- systemd-boot ----
bootctl install --force 2>/dev/null || bootctl update
echo "    bootctl: OK"

# ---- Boot entry ----
cat > /boot/loader/entries/arch.conf <<BOOT
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw quiet loglevel=3
BOOT

cat > /boot/loader/loader.conf <<LOADER
default  arch.conf
timeout  3
console-mode max
editor   no
LOADER
echo "    Boot entries: OK"

# ---- BIOS workaround ----
# BIOS รุ่นนี้ hardcode boot จาก \EFI\Microsoft\Boot\bootmgfw.efi เสมอ
# แก้โดย copy systemd-boot ไปแทนที่ไฟล์นั้น
mkdir -p /boot/EFI/Microsoft/Boot
if [ -f /boot/EFI/Microsoft/Boot/bootmgfw.efi ]; then
  cp /boot/EFI/Microsoft/Boot/bootmgfw.efi \
     /boot/EFI/Microsoft/Boot/bootmgfw.efi.bak
fi
cp /boot/EFI/systemd/systemd-bootx64.efi \
   /boot/EFI/Microsoft/Boot/bootmgfw.efi
echo "    BIOS workaround: OK"

# ---- efibootmgr ----
# ลบ Linux entry เก่าที่อาจ disabled
for num in \$(efibootmgr 2>/dev/null | grep -i "linux boot manager" | grep -oP 'Boot\K[0-9A-F]+'); do
  efibootmgr --delete-bootnum --bootnum "\$num" &>/dev/null || true
done

# สร้าง entry ใหม่
efibootmgr \
  --create \
  --disk ${EFI_DISK} \
  --part ${EFI_PARTNUM} \
  --label "Linux Boot Manager" \
  --loader "\EFI\systemd\systemd-bootx64.efi" \
  &>/dev/null

NEW_ENTRY=\$(efibootmgr | grep "Linux Boot Manager" | grep -oP 'Boot\K[0-9A-F]+' | head -1)
WIN_ENTRY=\$(efibootmgr | grep -i "windows" | grep -oP 'Boot\K[0-9A-F]+' | head -1)

efibootmgr --bootnum "\$NEW_ENTRY" --active &>/dev/null
if [ -n "\$WIN_ENTRY" ]; then
  efibootmgr --bootorder "\${NEW_ENTRY},\${WIN_ENTRY}" &>/dev/null
else
  efibootmgr --bootorder "\${NEW_ENTRY}" &>/dev/null
fi
echo "    efibootmgr: OK"
efibootmgr | grep -E "BootOrder|Boot[0-9A-F]{4}\*"

# ---- NetworkManager — pre-config WiFi ----
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
echo "    WiFi profile: OK"

# ---- Services ----
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
echo "    Services: OK"

echo ""
echo "    chroot: DONE"
CHROOT_EOF

ok

# ============================================================
log "[8/9] dotfiles + scripts สำหรับ user ${USERNAME}"
# ============================================================
U="/mnt/home/${USERNAME}"

mkdir -p \
  "${U}/.config/sway" \
  "${U}/.config/waybar" \
  "${U}/.config/foot" \
  "${U}/.config/environment.d" \
  "${U}/bin" \
  "${U}/Pictures"

# ---- Sway config ----
cat > "${U}/.config/sway/config" <<'SWAYEOF'
set $mod Mod4
set $term foot
set $menu wofi --show drun

# Output
output * bg #1d1f21 solid_color

# Input
input type:keyboard {
    repeat_delay 300
    repeat_rate 50
}
input type:touchpad {
    tap enabled
    natural_scroll enabled
}

# ---- Keybindings ----
bindsym $mod+Return      exec $term
bindsym $mod+d           exec $menu
bindsym $mod+b           exec brave --ozone-platform=wayland
bindsym $mod+r           exec ~/bin/rdp
bindsym $mod+Shift+c     kill
bindsym $mod+Shift+q     exit
bindsym $mod+f           fullscreen
bindsym $mod+space       floating toggle
bindsym $mod+Shift+space focus mode_toggle

# Focus (vim-style)
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
mode "resize" {
    bindsym h resize shrink width 50px
    bindsym l resize grow width 50px
    bindsym j resize grow height 50px
    bindsym k resize shrink height 50px
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+ctrl+r mode "resize"

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

# Layout
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split
bindsym $mod+minus split vertical
bindsym $mod+backslash split horizontal

# Screenshot
bindsym $mod+Print exec grim ~/Pictures/ss-$(date +%Y%m%d-%H%M%S).png
bindsym $mod+Shift+Print exec grim -g "$(slurp)" ~/Pictures/ss-$(date +%Y%m%d-%H%M%S).png

# ---- Appearance ----
default_border pixel 2
smart_borders on
gaps inner 6
gaps outer 4

client.focused          #81a2be #1d1f21 #c5c8c6 #81a2be #81a2be
client.unfocused        #333333 #1d1f21 #969896 #333333 #333333
client.focused_inactive #333333 #1d1f21 #969896 #333333 #333333

# ---- Bar ----
bar {
    swaybar_command waybar
}

# ---- Autostart ----
exec dunst
exec /usr/lib/xdg-desktop-portal-wlr
exec sleep 1 && /usr/lib/xdg-desktop-portal
SWAYEOF

# ---- Waybar ----
cat > "${U}/.config/waybar/config" <<'WBEOF'
{
  "layer": "top",
  "position": "top",
  "height": 26,
  "spacing": 0,
  "modules-left":   ["sway/workspaces", "sway/mode"],
  "modules-center": ["sway/window"],
  "modules-right":  ["network", "memory", "cpu", "clock"],

  "sway/workspaces": {
    "disable-scroll": true,
    "all-outputs": true
  },
  "sway/mode": {
    "format": " {}"
  },
  "sway/window": {
    "max-length": 60
  },
  "clock": {
    "format": " {:%H:%M  %d/%m/%Y}",
    "tooltip-format": "{:%A %d %B %Y}"
  },
  "cpu": {
    "format": " {usage}%",
    "interval": 3,
    "tooltip": false
  },
  "memory": {
    "format": " {}%",
    "interval": 10,
    "tooltip": false
  },
  "network": {
    "format-ethernet": " {ipaddr}",
    "format-wifi":     " {signalStrength}%",
    "format-disconnected": "NO NET",
    "tooltip-format-wifi": "{essid} ({signalStrength}%)",
    "interval": 10
  }
}
WBEOF

cat > "${U}/.config/waybar/style.css" <<'CSSEOF'
* {
  font-family: monospace;
  font-size: 12px;
  border: none;
  border-radius: 0;
  min-height: 0;
}
window#waybar {
  background: rgba(29, 31, 33, 0.95);
  color: #c5c8c6;
  border-bottom: 1px solid #333;
}
#workspaces button {
  color: #969896;
  padding: 0 6px;
  background: transparent;
}
#workspaces button.focused {
  color: #81a2be;
  font-weight: bold;
  border-bottom: 2px solid #81a2be;
}
#workspaces button:hover {
  color: #c5c8c6;
}
#mode {
  color: #f0c674;
  padding: 0 6px;
}
#clock, #cpu, #memory, #network {
  padding: 0 10px;
  color: #c5c8c6;
}
#clock    { color: #b5bd68; }
#cpu      { color: #cc6666; }
#memory   { color: #de935f; }
#network  { color: #81a2be; }
CSSEOF

# ---- Foot terminal ----
cat > "${U}/.config/foot/foot.ini" <<'FOOTEOF'
[main]
font=monospace:size=11
pad=8x8
shell=/bin/bash

[scrollback]
lines=5000

[colors]
background=1d1f21
foreground=c5c8c6
regular0=1d1f21
regular1=cc6666
regular2=b5bd68
regular3=f0c674
regular4=81a2be
regular5=b294bb
regular6=8abeb7
regular7=c5c8c6
bright0=969896
bright1=cc6666
bright2=b5bd68
bright3=f0c674
bright4=81a2be
bright5=b294bb
bright6=8abeb7
bright7=ffffff
FOOTEOF

# ---- Wayland environment ----
cat > "${U}/.config/environment.d/wayland.conf" <<'ENVEOF'
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
SDL_VIDEODRIVER=wayland
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=sway
XDG_CURRENT_DESKTOP=sway
LIBVA_DRIVER_NAME=iHD
WLR_NO_HARDWARE_CURSORS=0
ENVEOF

# ---- FreeRDP helper ----
cat > "${U}/bin/rdp" <<RDPEOF
#!/bin/bash
# ใช้งาน: rdp [IP:PORT] [USER]
# ตัวอย่าง: rdp 192.168.1.1:3389 Administrator
TARGET=\${1:-${RDP_HOST}:${RDP_PORT}}
RDPUSER=\${2:-${RDP_USER}}
xfreerdp \
  /v:\$TARGET \
  /u:\$RDPUSER \
  /dynamic-resolution \
  /rfx \
  /gfx \
  +clipboard \
  /cert:ignore \
  /log-level:ERROR
RDPEOF
chmod +x "${U}/bin/rdp"

# ---- Auto-start Sway จาก TTY1 ----
cat >> "${U}/.bash_profile" <<'PROFEOF'

# PATH
export PATH="$HOME/bin:$PATH"

# Start Sway เมื่อ login ที่ TTY1
if [ -z "$WAYLAND_DISPLAY" ] && [ "${XDG_VTNR:-0}" -eq 1 ]; then
  exec sway 2>/tmp/sway.log
fi
PROFEOF

cat >> "${U}/.bashrc" <<'RCEOF'
export PATH="$HOME/bin:$PATH"
alias ll='ls -lah --color=auto'
alias gs='git status'
RCEOF

# ---- install-brave.sh (รันหลัง reboot) ----
cat > "${U}/install-brave.sh" <<'BRAVEEOF'
#!/bin/bash
# ============================================================
# install-brave.sh — รันหลัง reboot เข้า Arch
# login เป็น arch แล้วรัน: bash ~/install-brave.sh
# ============================================================
set -e

RED='\033[0;31m'; GRN='\033[0;32m'; BLU='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLU}>>>${NC} $*"; }
ok()  { echo -e "    ${GRN}OK${NC}"; }
die() { echo -e "${RED}ERROR${NC} $*"; exit 1; }

# ตรวจสอบ internet
log "ตรวจสอบ Internet"
ping -c 1 -W 5 archlinux.org &>/dev/null || die "ไม่มี Internet"
ok

# Update ก่อน
log "Update system"
sudo pacman -Syu --noconfirm
ok

# paru (AUR helper)
log "ติดตั้ง paru"
if ! command -v paru &>/dev/null; then
  cd /tmp
  rm -rf paru-bin
  git clone https://aur.archlinux.org/paru-bin.git
  cd paru-bin
  makepkg -si --noconfirm
  cd ~
fi
ok

# Brave
log "ติดตั้ง Brave"
paru -S --noconfirm brave-bin
ok

# ตรวจสอบ VA-API
log "ตรวจสอบ GPU driver"
vainfo 2>/dev/null | grep -i "VAProfile" | head -3 || echo "    vainfo: อาจต้อง reboot ก่อน"

echo ""
echo "============================================================"
echo " ติดตั้งเสร็จสมบูรณ์"
echo "============================================================"
echo " Brave: $(brave --version 2>/dev/null || echo 'ติดตั้งแล้ว')"
echo " FreeRDP: $(xfreerdp --version 2>/dev/null | head -1)"
echo ""
echo " logout แล้ว login ใหม่ — Sway จะ start อัตโนมัติ"
echo " หรือรัน: sway"
echo "============================================================"
BRAVEEOF
chmod +x "${U}/install-brave.sh"

# ---- แก้ ownership ----
arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

ok

# ============================================================
log "[9/9] Unmount + เสร็จสมบูรณ์"
# ============================================================
sync
umount -R /mnt

echo ""
echo "============================================================"
echo -e " ${GRN}setup.sh เสร็จสมบูรณ์${NC}"
echo "============================================================"
echo ""
echo " ขั้นตอนต่อไป:"
echo "   1.  reboot  (ถอด USB ระหว่าง reboot)"
echo "   2.  login: ${USERNAME} / ${USER_PASS}"
echo "   3.  bash ~/install-brave.sh"
echo "   4.  logout แล้ว login ใหม่ — Sway start อัตโนมัติ"
echo ""
echo " Keybinding หลัก:"
echo "   Super+Enter      terminal (foot)"
echo "   Super+D          launcher (wofi)"
echo "   Super+B          Brave"
echo "   Super+R          RDP -> ${RDP_HOST}:${RDP_PORT} (${RDP_USER})"
echo "   Super+H/J/K/L    เปลี่ยน focus"
echo "   Super+Shift+H/J/K/L  ย้าย window"
echo "   Super+Ctrl+R     resize mode"
echo "   Super+1-5        workspace"
echo "   Super+F          fullscreen"
echo "   Super+Space      float toggle"
echo "   Super+Print      screenshot"
echo "   Super+Shift+C    ปิด window"
echo "   Super+Shift+Q    ออกจาก Sway"
echo ""
echo " Log: $LOG"
echo "============================================================"