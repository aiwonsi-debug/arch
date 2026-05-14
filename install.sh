#!/bin/bash
# ============================================================
# install.sh — รันใน Arch Linux Live USB
# Hardware: i5-6400T / 8GB RAM / sda4 30GB / UEFI Dual Boot
# ============================================================
# วิธีใช้:
#   chmod +x install.sh && ./install.sh
# ============================================================

set -e

# ---- ตัวแปรที่ต้องแก้ก่อนรัน ----
USERNAME="yourusername"
HOSTNAME="archlinux"
ROOT_PARTITION="/dev/sda4"
EFI_PARTITION="/dev/sda1"
TIMEZONE="Asia/Bangkok"
LOCALE_MAIN="en_US.UTF-8"
LOCALE_EXTRA="th_TH.UTF-8"

# ============================================================
echo ">>> [1/8] ตรวจสอบ UEFI mode"
# ============================================================
if [ ! -d /sys/firmware/efi/efivars ]; then
  echo "ERROR: ไม่ได้ boot แบบ UEFI — กรุณาตรวจสอบ BIOS settings"
  exit 1
fi
echo "    OK"

# ============================================================
echo ">>> [2/8] ตรวจสอบ Internet"
# ============================================================
if ! ping -c 1 archlinux.org &>/dev/null; then
  echo "ERROR: ไม่มี Internet — กรุณาเชื่อมต่อก่อน"
  exit 1
fi
echo "    OK"

# ============================================================
echo ">>> [3/8] ตั้งค่า Clock"
# ============================================================
timedatectl set-ntp true
echo "    OK"

# ============================================================
echo ">>> [4/8] เลือก Mirror"
# ============================================================
reflector --country Thailand,Singapore --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
echo "    OK"

# ============================================================
echo ">>> [5/8] Format และ Mount"
# ============================================================
echo ""
echo "  WARNING: กำลัง format ${ROOT_PARTITION}"
echo "  ข้อมูลใน partition นี้จะหายถาวร"
lsblk
echo ""
echo "  กด Enter เพื่อยืนยัน หรือ Ctrl+C เพื่อยกเลิก"
read -r

mkfs.ext4 -F "${ROOT_PARTITION}"
mount "${ROOT_PARTITION}" /mnt
mkdir -p /mnt/boot
mount "${EFI_PARTITION}" /mnt/boot
echo "    OK"
lsblk

# ============================================================
echo ">>> [6/8] pacstrap"
# ============================================================
# ลบไฟล์ที่อาจค้างจาก install attempt ก่อนหน้า
rm -f /mnt/boot/intel-ucode.img
rm -f /mnt/boot/initramfs-linux.img
rm -f /mnt/boot/vmlinuz-linux

pacstrap -K /mnt \
  base linux linux-firmware linux-headers \
  base-devel \
  intel-ucode \
  networkmanager \
  vim git sudo \
  man-db man-pages \
  pipewire pipewire-pulse wireplumber
echo "    OK"

# ============================================================
echo ">>> [7/8] สร้าง fstab"
# ============================================================
genfstab -U /mnt >> /mnt/etc/fstab
echo "    fstab:"
cat /mnt/etc/fstab

# ============================================================
echo ">>> [8/8] ตั้งค่าระบบใน chroot"
# ============================================================
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PARTITION}")
echo "    Root UUID: ${ROOT_UUID}"

# copy post-install script เข้าไปใน /mnt/home/<user> ถ้ามี
if [ -f ./post-install.sh ]; then
  mkdir -p /mnt/home/"${USERNAME}"
  cp ./post-install.sh /mnt/home/"${USERNAME}"/post-install.sh
fi

arch-chroot /mnt /bin/bash <<CHROOT_EOF
set -e

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo "    Timezone: OK"

# Locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#th_TH.UTF-8 UTF-8/th_TH.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE_MAIN}" > /etc/locale.conf
echo "    Locale: OK"

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<'HOSTS_EOF'
127.0.0.1   localhost
::1         localhost
HOSTS_EOF
echo "127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}" >> /etc/hosts
echo "    Hostname: OK"

# Root password — ใช้ chpasswd เพราะ passwd ต้องการ TTY ซึ่งไม่มีใน heredoc
echo ""
echo "    กรุณากำหนด root password (จะถูกตั้งเป็น password จริงในระบบ):"
read -r -s -p "    Root password: " ROOT_PASS
echo ""
read -r -s -p "    Confirm: " ROOT_PASS2
echo ""
if [ "$ROOT_PASS" != "$ROOT_PASS2" ]; then
  echo "ERROR: password ไม่ตรงกัน กรุณารัน script ใหม่"
  exit 1
fi
echo "root:${ROOT_PASS}" | chpasswd
echo "    Root password: OK"

# User
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo ""
read -r -s -p "    ${USERNAME} password: " USER_PASS
echo ""
read -r -s -p "    Confirm: " USER_PASS2
echo ""
if [ "$USER_PASS" != "$USER_PASS2" ]; then
  echo "ERROR: password ไม่ตรงกัน กรุณารัน script ใหม่"
  exit 1
fi
echo "${USERNAME}:${USER_PASS}" | chpasswd
echo "    User password: OK"

# sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo "    sudo: OK"

# systemd-boot
# --force เพื่อ overwrite ไฟล์ที่มีอยู่แล้วจาก Windows EFI partition
bootctl install --force 2>/dev/null || bootctl update

cat > /boot/loader/entries/arch.conf <<BOOT_EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw quiet
BOOT_EOF

cat > /boot/loader/loader.conf <<LOADER_EOF
default  arch.conf
timeout  5
console-mode max
editor   no
LOADER_EOF

echo "    systemd-boot: OK"
bootctl list

# Services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
echo "    Services: OK"

# สิทธิ์ post-install script
if [ -f /home/${USERNAME}/post-install.sh ]; then
  chown ${USERNAME}:${USERNAME} /home/${USERNAME}/post-install.sh
  chmod +x /home/${USERNAME}/post-install.sh
  echo "    post-install.sh: copied to /home/${USERNAME}/"
fi

CHROOT_EOF

echo ""
echo "============================================================"
echo " install.sh เสร็จสมบูรณ์"
echo "============================================================"
echo " ขั้นตอนต่อไป:"
echo "   1.  umount -R /mnt"
echo "   2.  reboot  (ถอด USB ระหว่าง reboot)"
echo "   3.  login เป็น ${USERNAME}"
echo "   4.  bash ~/post-install.sh"
echo "============================================================"echo "    OK"

# ============================================================
echo ">>> [3/8] ตั้งค่า Clock"
# ============================================================
timedatectl set-ntp true
echo "    OK"

# ============================================================
echo ">>> [4/8] เลือก Mirror"
# ============================================================
reflector --country Thailand,Singapore --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
echo "    OK"

# ============================================================
echo ">>> [5/8] Format และ Mount"
# ============================================================
echo ""
echo "  WARNING: กำลัง format ${ROOT_PARTITION}"
echo "  ข้อมูลใน partition นี้จะหายถาวร"
lsblk
echo ""
echo "  กด Enter เพื่อยืนยัน หรือ Ctrl+C เพื่อยกเลิก"
read -r

mkfs.ext4 -F "${ROOT_PARTITION}"
mount "${ROOT_PARTITION}" /mnt
mkdir -p /mnt/boot
mount "${EFI_PARTITION}" /mnt/boot
echo "    OK"
lsblk

# ============================================================
echo ">>> [6/8] pacstrap"
# ============================================================
# ลบไฟล์ที่อาจค้างจาก install attempt ก่อนหน้า
rm -f /mnt/boot/intel-ucode.img
rm -f /mnt/boot/initramfs-linux.img
rm -f /mnt/boot/vmlinuz-linux

pacstrap -K /mnt \
  base linux linux-firmware linux-headers \
  base-devel \
  intel-ucode \
  networkmanager \
  vim git sudo \
  man-db man-pages \
  pipewire pipewire-pulse wireplumber
echo "    OK"

# ============================================================
echo ">>> [7/8] สร้าง fstab"
# ============================================================
genfstab -U /mnt >> /mnt/etc/fstab
echo "    fstab:"
cat /mnt/etc/fstab

# ============================================================
echo ">>> [8/8] ตั้งค่าระบบใน chroot"
# ============================================================
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PARTITION}")
echo "    Root UUID: ${ROOT_UUID}"

# copy post-install script เข้าไปใน /mnt/home/<user> ถ้ามี
if [ -f ./post-install.sh ]; then
  mkdir -p /mnt/home/"${USERNAME}"
  cp ./post-install.sh /mnt/home/"${USERNAME}"/post-install.sh
fi

arch-chroot /mnt /bin/bash <<CHROOT_EOF
set -e

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo "    Timezone: OK"

# Locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#th_TH.UTF-8 UTF-8/th_TH.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE_MAIN}" > /etc/locale.conf
echo "    Locale: OK"

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<'HOSTS_EOF'
127.0.0.1   localhost
::1         localhost
HOSTS_EOF
echo "127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}" >> /etc/hosts
echo "    Hostname: OK"

# Root password — retry จนกว่าจะสำเร็จ
echo ""
echo "    กรุณาตั้ง password สำหรับ root (อย่างน้อย 8 ตัว มีตัวเลขและตัวอักษร):"
until passwd; do
  echo "    password ไม่ผ่าน กรุณาลองใหม่:"
done

# User
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo ""
echo "    กรุณาตั้ง password สำหรับ ${USERNAME} (อย่างน้อย 8 ตัว มีตัวเลขและตัวอักษร):"
until passwd ${USERNAME}; do
  echo "    password ไม่ผ่าน กรุณาลองใหม่:"
done

# sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo "    sudo: OK"

# systemd-boot
# --force เพื่อ overwrite ไฟล์ที่มีอยู่แล้วจาก Windows EFI partition
bootctl install --force 2>/dev/null || bootctl update

cat > /boot/loader/entries/arch.conf <<BOOT_EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw quiet
BOOT_EOF

cat > /boot/loader/loader.conf <<LOADER_EOF
default  arch.conf
timeout  5
console-mode max
editor   no
LOADER_EOF

echo "    systemd-boot: OK"
bootctl list

# Services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
echo "    Services: OK"

# สิทธิ์ post-install script
if [ -f /home/${USERNAME}/post-install.sh ]; then
  chown ${USERNAME}:${USERNAME} /home/${USERNAME}/post-install.sh
  chmod +x /home/${USERNAME}/post-install.sh
  echo "    post-install.sh: copied to /home/${USERNAME}/"
fi

CHROOT_EOF

echo ""
echo "============================================================"
echo " install.sh เสร็จสมบูรณ์"
echo "============================================================"
echo " ขั้นตอนต่อไป:"
echo "   1.  umount -R /mnt"
echo "   2.  reboot  (ถอด USB ระหว่าง reboot)"
echo "   3.  login เป็น ${USERNAME}"
echo "   4.  bash ~/post-install.sh"
echo "============================================================"echo "    OK"

# ============================================================
echo ">>> [3/8] ตั้งค่า Clock"
# ============================================================
timedatectl set-ntp true
echo "    OK"

# ============================================================
echo ">>> [4/8] เลือก Mirror"
# ============================================================
reflector --country Thailand,Singapore --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
echo "    OK"

# ============================================================
echo ">>> [5/8] Format และ Mount"
# ============================================================
echo ""
echo "  WARNING: กำลัง format ${ROOT_PARTITION}"
echo "  ข้อมูลใน partition นี้จะหายถาวร"
lsblk
echo ""
echo "  กด Enter เพื่อยืนยัน หรือ Ctrl+C เพื่อยกเลิก"
read -r

mkfs.ext4 -F "${ROOT_PARTITION}"
mount "${ROOT_PARTITION}" /mnt
mkdir -p /mnt/boot
mount "${EFI_PARTITION}" /mnt/boot
echo "    OK"
lsblk

# ============================================================
echo ">>> [6/8] pacstrap"
# ============================================================
pacstrap -K /mnt \
  base linux linux-firmware linux-headers \
  base-devel \
  intel-ucode \
  networkmanager \
  vim git sudo \
  man-db man-pages \
  pipewire pipewire-pulse wireplumber
echo "    OK"

# ============================================================
echo ">>> [7/8] สร้าง fstab"
# ============================================================
genfstab -U /mnt >> /mnt/etc/fstab
echo "    fstab:"
cat /mnt/etc/fstab

# ============================================================
echo ">>> [8/8] ตั้งค่าระบบใน chroot"
# ============================================================
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PARTITION}")
echo "    Root UUID: ${ROOT_UUID}"

# copy post-install script เข้าไปใน /mnt/home/<user> ถ้ามี
if [ -f ./post-install.sh ]; then
  mkdir -p /mnt/home/"${USERNAME}"
  cp ./post-install.sh /mnt/home/"${USERNAME}"/post-install.sh
fi

arch-chroot /mnt /bin/bash <<CHROOT_EOF
set -e

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo "    Timezone: OK"

# Locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#th_TH.UTF-8 UTF-8/th_TH.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE_MAIN}" > /etc/locale.conf
echo "    Locale: OK"

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<'HOSTS_EOF'
127.0.0.1   localhost
::1         localhost
HOSTS_EOF
echo "127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}" >> /etc/hosts
echo "    Hostname: OK"

# Root password
echo ""
echo "    กรุณาตั้ง password สำหรับ root:"
passwd

# User
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo ""
echo "    กรุณาตั้ง password สำหรับ ${USERNAME}:"
passwd ${USERNAME}

# sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo "    sudo: OK"

# systemd-boot
bootctl install --force 2>/dev/null || bootctl update

cat > /boot/loader/entries/arch.conf <<BOOT_EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw quiet
BOOT_EOF

cat > /boot/loader/loader.conf <<LOADER_EOF
default  arch.conf
timeout  5
console-mode max
editor   no
LOADER_EOF

echo "    systemd-boot: OK"
bootctl list

# Services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
echo "    Services: OK"

# สิทธิ์ post-install script
if [ -f /home/${USERNAME}/post-install.sh ]; then
  chown ${USERNAME}:${USERNAME} /home/${USERNAME}/post-install.sh
  chmod +x /home/${USERNAME}/post-install.sh
  echo "    post-install.sh: copied to /home/${USERNAME}/"
fi

CHROOT_EOF

echo ""
echo "============================================================"
echo " install.sh เสร็จสมบูรณ์"
echo "============================================================"
echo " ขั้นตอนต่อไป:"
echo "   1.  umount -R /mnt"
echo "   2.  reboot  (ถอด USB ระหว่าง reboot)"
echo "   3.  login เป็น ${USERNAME}"
echo "   4.  bash ~/post-install.sh"
echo "============================================================"
