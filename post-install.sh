#!/bin/bash
# ============================================================
# post-install.sh — รันหลัง reboot เข้า Arch Linux
# login เป็น user ปกติ (ไม่ใช่ root) แล้วรัน:
#   bash ~/post-install.sh
# ============================================================

set -e

# ---- ตัวแปรที่ต้องแก้ก่อนรัน ----
# แก้ IP และ USERNAME ของ Windows machine ที่จะเชื่อม FreeRDP
RDP_HOST="100.123.121.34"
RDP_USER="psc-cm"

# ============================================================
echo ">>> [1/7] Update ระบบ"
# ============================================================
sudo pacman -Syu --noconfirm
echo "    OK"

# ============================================================
echo ">>> [2/7] ติดตั้ง Intel GPU Driver"
# ============================================================
sudo pacman -S --noconfirm \
  mesa \
  intel-media-driver \
  vulkan-intel \
  libva-utils
echo "    OK"
echo "    ตรวจสอบ VA-API (hardware video acceleration):"
vainfo || echo "    vainfo error — อาจต้อง reboot ก่อน"

# ============================================================
echo ">>> [3/7] ติดตั้ง River WM และ Wayland Stack"
# ============================================================
sudo pacman -S --noconfirm \
  river \
  foot \
  waybar \
  wofi \
  xdg-desktop-portal-wlr \
  xdg-utils \
  polkit \
  wl-clipboard \
  grim \
  slurp \
  brightnessctl \
  playerctl \
  libnotify \
  dunst
echo "    OK"

# ============================================================
echo ">>> [4/7] ติดตั้ง FreeRDP"
# ============================================================
sudo pacman -S --noconfirm freerdp
echo "    OK"
xfreerdp --version

# ============================================================
echo ">>> [5/7] ติดตั้ง paru (AUR helper) และ Brave"
# ============================================================
# paru
cd /tmp
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin
makepkg -si --noconfirm
cd ~
echo "    paru: OK"

# Brave
paru -S --noconfirm brave-bin
echo "    Brave: OK"

# ============================================================
echo ">>> [6/7] ตั้งค่า River WM"
# ============================================================
mkdir -p ~/.config/river
mkdir -p ~/.config/environment.d
mkdir -p ~/.config/waybar
mkdir -p ~/.config/foot

# ---- River init ----
cat > ~/.config/river/init <<'RIVER_EOF'
#!/bin/sh

mod="Super"

# ---- ออกจาก River ----
riverctl map normal $mod+Shift Q exit

# ---- Terminal ----
riverctl map normal $mod Return spawn foot

# ---- App Launcher ----
riverctl map normal $mod D spawn "wofi --show drun"

# ---- Brave Browser ----
riverctl map normal $mod B spawn "brave --ozone-platform=wayland"

# ---- ปิด Window ----
riverctl map normal $mod+Shift C close

# ---- Focus Window ----
riverctl map normal $mod J focus-view next
riverctl map normal $mod K focus-view previous

# ---- Swap Window ----
riverctl map normal $mod+Shift J swap next
riverctl map normal $mod+Shift K swap previous

# ---- ปรับสัดส่วน Main Window ----
riverctl map normal $mod H send-layout-cmd rivertile "main-ratio -0.05"
riverctl map normal $mod L send-layout-cmd rivertile "main-ratio +0.05"

# ---- Tags (Workspace) 1-9 ----
for i in $(seq 1 9); do
  tags=$((1 << ($i - 1)))
  riverctl map normal $mod $i set-focused-tags $tags
  riverctl map normal $mod+Shift $i set-view-tags $tags
done

# ---- Float / Fullscreen ----
riverctl map normal $mod Space toggle-float
riverctl map normal $mod F toggle-fullscreen

# ---- Screenshot ----
# Super+Print = fullscreen, Super+Shift+Print = select area
riverctl map normal $mod Print spawn "grim ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"
riverctl map normal $mod+Shift Print spawn "grim -g \"\$(slurp)\" ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"

# ---- Keyboard repeat rate ----
# delay 300ms, repeat 50 ครั้ง/วินาที
riverctl set-repeat 50 300

# ---- Cursor ----
riverctl set-cursor-warp on-output-change
riverctl hide-cursor when-typing enabled

# ---- เริ่ม Services ----
dunst &
waybar &
/usr/lib/xdg-desktop-portal-wlr &
sleep 0.5
/usr/lib/xdg-desktop-portal &

# ---- Layout ----
rivertile -view-padding 6 -outer-padding 6 &
riverctl default-layout rivertile

RIVER_EOF

chmod +x ~/.config/river/init
echo "    River init: OK"

# ---- Environment Variables ----
cat > ~/.config/environment.d/wayland.conf <<'ENV_EOF'
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
SDL_VIDEODRIVER=wayland
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=river
XDG_CURRENT_DESKTOP=river
LIBVA_DRIVER_NAME=iHD
ENV_EOF
echo "    Environment: OK"

# ---- Foot Terminal config ----
cat > ~/.config/foot/foot.ini <<'FOOT_EOF'
[main]
font=monospace:size=11
pad=8x8

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

[scrollback]
lines=5000
FOOT_EOF
echo "    foot config: OK"

# ---- สร้าง script เรียก FreeRDP ----
mkdir -p ~/bin
cat > ~/bin/rdp <<RDPSCRIPT_EOF
#!/bin/bash
# ใช้งาน: rdp [IP] [USERNAME]
# ตัวอย่าง: rdp 192.168.1.100 Administrator
HOST=\${1:-${RDP_HOST}}
USER=\${2:-${RDP_USER}}
xfreerdp \
  /v:\$HOST \
  /u:\$USER \
  /dynamic-resolution \
  /rfx \
  /gfx \
  /sound \
  /microphone \
  +clipboard \
  /cert:ignore
RDPSCRIPT_EOF
chmod +x ~/bin/rdp
mkdir -p ~/Pictures
echo "    FreeRDP script: ~/bin/rdp"

# ---- Auto-start River จาก TTY1 ----
if ! grep -q "exec river" ~/.bash_profile 2>/dev/null; then
  cat >> ~/.bash_profile <<'PROFILE_EOF'

# Auto-start River WM เมื่อ login ที่ TTY1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
  export PATH="$HOME/bin:$PATH"
  exec river
fi
PROFILE_EOF
  echo "    bash_profile: OK"
else
  echo "    bash_profile: มี entry อยู่แล้ว"
fi

# ---- เพิ่ม ~/bin ใน PATH สำหรับ session ปกติด้วย ----
if ! grep -q 'HOME/bin' ~/.bashrc 2>/dev/null; then
  echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
fi

# ============================================================
echo ">>> [7/7] ตั้งค่า Waybar พื้นฐาน"
# ============================================================
cat > ~/.config/waybar/config <<'WAYBAR_EOF'
{
  "layer": "top",
  "position": "top",
  "height": 28,
  "modules-left": ["river/tags"],
  "modules-center": ["river/window"],
  "modules-right": [
    "network",
    "memory",
    "cpu",
    "battery",
    "clock"
  ],
  "river/tags": {
    "num-tags": 9
  },
  "clock": {
    "format": "{:%H:%M  %d/%m/%Y}"
  },
  "cpu": {
    "format": "CPU {usage}%",
    "interval": 3
  },
  "memory": {
    "format": "RAM {}%",
    "interval": 10
  },
  "network": {
    "format-ethernet": "ETH {ipaddr}",
    "format-wifi": "WIFI {signalStrength}%",
    "format-disconnected": "NO NET"
  },
  "battery": {
    "format": "BAT {capacity}%",
    "format-charging": "CHR {capacity}%"
  }
}
WAYBAR_EOF

cat > ~/.config/waybar/style.css <<'CSS_EOF'
* {
  font-family: monospace;
  font-size: 12px;
  border: none;
  border-radius: 0;
  margin: 0;
  padding: 0 6px;
}
window#waybar {
  background: #1d1f21;
  color: #c5c8c6;
}
#tags button {
  color: #969896;
  padding: 0 4px;
}
#tags button.focused {
  color: #81a2be;
  font-weight: bold;
}
#clock, #cpu, #memory, #network, #battery {
  padding: 0 8px;
  color: #c5c8c6;
}
CSS_EOF
echo "    Waybar: OK"

# ============================================================
echo ""
echo "============================================================"
echo " post-install.sh เสร็จสมบูรณ์"
echo "============================================================"
echo ""
echo " สรุปสิ่งที่ติดตั้ง:"
echo "   - Intel GPU driver (mesa, intel-media-driver, vulkan)"
echo "   - River WM + Wayland stack"
echo "   - foot terminal"
echo "   - Waybar + Wofi"
echo "   - FreeRDP  (รันด้วย:  rdp <IP> <USERNAME>)"
echo "   - Brave browser"
echo ""
echo " Keybinding:"
echo "   Super+Enter       = เปิด terminal (foot)"
echo "   Super+D           = App launcher (wofi)"
echo "   Super+B           = Brave"
echo "   Super+Shift+C     = ปิด window"
echo "   Super+J/K         = เปลี่ยน focus"
echo "   Super+H/L         = ปรับขนาด window"
echo "   Super+1-9         = เปลี่ยน workspace (tag)"
echo "   Super+F           = Fullscreen"
echo "   Super+Space       = Float mode"
echo "   Super+Print       = Screenshot"
echo "   Super+Shift+Q     = ออกจาก River"
echo ""
echo " ขั้นตอนต่อไป:"
echo "   logout แล้ว login ใหม่ — River จะ start อัตโนมัติ"
echo "   หรือรัน:  river"
echo "============================================================"
