if [ "$EUID" != "0" ]; then
    echo "ERROR: Must be ran as root user in an archlinux live environment"
    exit
fi

autoload colors; colors  # allow coloured echo commands

section() {  # function to easily print section titles
    echo $fg_bold[cyan]
    clear
    echo -e "${1}${reset_color}\n--------------------------------------------------------\n"
}

section "Initial checks and setup"

echo "AutoArch - archlinux installation script (https://github.com/b-illy/autoarch)"

# check if booted in efi or bios mode
if ls /sys/firmware/efi/efivars > /dev/null 2>&1; then
    efi=true
    echo -ne "\nRunning in EFI"
else
    efi=false
    echo -ne "\nRunning in BIOS"
fi
echo " mode, if this was unexpected, check motherboard settings to make sure you boot in the correct mode"


read -q "?This script will attempt to install archlinux on your system which is potentially dangerous. Accept the risks and continue? [y/N] "
if [ $REPLY != "y" ]; then
    echo "Exiting..."
    exit
fi

echo -ne "\n"

# check if there is already an internet connection
section "Initial checks and setup"
echo -e "\nChecking internet connection..."
if curl https://archlinux.org > /dev/null 2>&1; then
    echo "Internet connection working, continuing..."
else
    echo "Internet connection doesn't seem to be working, entering troubleshooting..."
    while [ true ]; do
        read "?Are you trying to use ethernet (enter 1) or WiFi (enter 2)? "
        if [ $REPLY = "1" ]; then  # todo: look into common ethernet problems
            if ip link | grep -q "^[0-9]: e[a-z]\{2\}[0-9]: <"; then
                echo "No ethernet device detected."
            else
                echo "Ethernet device detected but no connection."
            fi
            read -q "?This will almost certainly cause issues - attempt to continue anyway? [y/N] "
            if [ $REPLY != "y" ]; then
                echo "Exiting... (re-run after troubleshooting internet connection)"
                exit
            fi
            break
        elif [ $REPLY = "2" ]; then
            echo -e "Set up a connection using iwctl\nRough instructions: (also type 'help' and/or consult Arch wiki)"
            echo -ne "station list\nstation *interface* scan\nstation *interface* list\nstation *interface* connect *ssid*\nstation *interface* show\n"
            iwctl
            break
        else
            echo "invalid input"
        fi
    done
fi

# sync time
echo -e "\nSyncing system clock..."
timedatectl set-ntp true

# install git and dialog for the install process
section "Initial checks and setup"
echo -e "Installing some packages to be used in the install process...\n"
pacman -Sy --noconfirm archlinux-keyring
pacman-key --init
pacman-key --populate archlinux
pacman -S --noconfirm dialog git


# dialog menu help
infostr="For certain parts of the install process, you will be asked to select \
a file from a dialog menu which looks a little like this one. To enter a directory \
or select a file in one of these menus, press the space bar. Use the arrow keys to \
navigate between options and, when you are finished, press ENTER."
dialog --title "Dialog Menu Help" --msgbox "${infostr}" 20 50


# setup keyboard layout
keymap=$(dialog --stdout --nocancel --backtitle "Keyboard layout setup" --title "Select a keyboard layout" --fselect /usr/share/kbd/keymaps/ 20 70)
loadkeys "$keymap"


# setup timezone
timezone=$(dialog --stdout --nocancel --backtitle "Timezone setup" --title "Select a timezone" --fselect /usr/share/zoneinfo/ 20 70)


# partitioning
section "Partitioning"
# determine a decent swap amount
physmem=0
physmem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
swap=0
if [ $physmem -lt 6000000 ]; then
    swap=$((($physmem+500000)/1000000))
elif [ $physmem -lt 12000000 ]; then
    swap=4
fi

# show recommended partitions (no separate home partition)
echo "Setting up partitions, recommended layout for you:"
if [ $efi = "true" ]; then
    echo "(gpt)"
    echo "efi partition (fat32) (512 MiB) (/mnt/boot) "
else
    echo "(mbr)"
fi
if [ $swap != 0 ]; then
    echo "swap partition (linux swap) ($swap GiB)"
fi
echo "root fs (ext4) (all remaining free space on the disk) (/mnt)"

# chance to modify swap amount
while [ true ]; do
    read "?Would you like to change the swap amount (1=yes, 2=no)? "
    if [ $REPLY = "1" ]; then
        echo -n "Input desired swap amount (in GiB): "
        read swap
        break
    elif [ $REPLY = "2" ]; then
        break
    else
        echo "invalid input"
    fi
done

# select device to partition
section "Partitioning"
echo "List of connected storage devices:"
lsblk
read dev"?Choose a disk from this list to partition (e.g. 'sda' or 'nvme0n1'): /dev/"
devp=$dev # ensure partitions on nvme drives (nvme0n1 -> nvme0n1p1 vs sda -> sda1) are referred to correctly
if [[ $dev == nvme* ]]; then
    devp="${dev}p"
fi

# select partition tool / method
section "Partitioning"
if dialog --backtitle "Partitioning" --yesno "Would you like this script to automatically partition according to the recommended layout?" 10 60; then
    # automatic partitioning
    if [ $efi = "false" ]; then
        # mbr / bios
        parted /dev/$dev mklabel msdos

        if [ $swap -ne 0 ]; then  # with swap
            parted /dev/$dev mkpart primary linux-swap 2MiB ${swap}GiB
            parted /dev/$dev mkpart primary ext4 ${swap}GiB 100%
            mkswap /dev/${devp}1
            mkfs.ext4 /dev/${devp}2
            mount /dev/${devp}2 /mnt
            swapon /dev/${devp}1
        else  # with no swap
            parted /dev/$dev mkpart primary ext4 2MiB 100%
            mkfs.ext4 /dev/${devp}1
            mount /dev/${devp}1 /mnt
        fi
    else
        # gpt / efi
        parted /dev/$dev mklabel gpt
        parted /dev/$dev mkpart boot fat32 2MiB 514MiB
        parted /dev/$dev set 1 boot
        parted /dev/$dev set 1 esp
        mkfs.fat -F 32 /dev/${devp}1

        if [ $swap -ne 0 ]; then  # with swap
            parted /dev/$dev mkpart swap linux-swap 514MiB $((($swap*1024)+514))MiB
            parted /dev/$dev mkpart rootfs ext4 $((($swap*1024)+514))MiB 100%
            mkswap /dev/${devp}2
            mkfs.ext4 /dev/${devp}3
            mount /dev/${devp}3 /mnt
            swapon /dev/${devp}2
        else  # no swap
            parted /dev/$dev mkpart rootfs ext4 514MiB 100%
            mkfs.ext4 /dev/${devp}2
            mount /dev/${devp}2 /mnt
        fi
        mkdir -p /mnt/boot
        mount /dev/${devp}1 /mnt/boot
    fi
else
    # manual partitioning
    REPLY=$(dialog --stdout --nocancel --backtitle "Partitioning" --menu "Choose a program to partition with" 20 40 20 \
    1 "parted (cli)" 2 "fdisk (cli)" 3 "cfdisk (ncurses gui)")  
    case $REPLY in
        1)
            parted /dev/$dev ;;
        2)
            fdisk /dev/$dev ;;
        3)
            cfdisk /dev/$dev ;;
    esac
    section "Partitioning"
    echo "Now that you have set up partitions, you will have to format and mount them (to /mnt/...)"
    echo "Press alt + left arrow/right arrow to switch between ttys to do this"
    read "?Press ENTER when you have finished to continue"
fi


# choose linux kernel version to use
REPLY=$(dialog --stdout --nocancel --backtitle "Main system setup" --menu "Select your preferred kernel" 20 80 20 \
1 "Linux - most updated kernel version" \
2 "Linux LTS - stable release, updated less often" \
3 "Linux Hardened - very security-focused branch, fewer features" \
4 "Linux Zen - optimised for performance")
case $REPLY in
    1)
        kernel="linux" ;;
    2)
        kernel="linux-lts" ;;
    3)
        kernel="linux-hardened" ;;
    4)
        kernel="linux-zen" ;;
esac


# install core system + useful packages
dialog --backtitle "Main system setup" --msgbox "Ready to install core packages and set up the system. This will likely take several minutes. Press OK to continue." 20 50
section "Main system setup"
# install packages
pacstrap /mnt --noconfirm \
    base $kernel linux-firmware xorg \
    networkmanager network-manager-applet nm-connection-editor \
    git base-devel \
    grub efibootmgr os-prober \
    btrfs-progs dosfstools e2fsprogs ntfs-3g xfsprogs \
    nano vim \
    man-db man-pages texinfo
# other useful setup stuff
section "Main system setup"
echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf  # save keymap across reboots on new system
genfstab -U /mnt >> /mnt/etc/fstab  # generate fs table for partitions to actually get mounted
arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt ln -sf ${timezone} /etc/localtime  # setup timezone
arch-chroot /mnt hwclock --systohc


# locale setup
locales=$(grep -E "\#[a-zA-Z_]+\.UTF-8 UTF-8" /mnt/etc/locale.gen | cut -d "." -f 1 | cut -d "#" -f 2)
checklistinput=$(for line in $(echo -n $locales); do; echo -n " $line off"; done)
menuinput=$(for line in $(echo -n $locales); do; echo -n " $line"; done)
echo "--stdout --no-cancel --no-items --backtitle \"Locale setup\" --menu \"Select primary locale\" 20 40 20${menuinput}" > /tmp/.dialog.tmp
primarylocale=$(dialog --file /tmp/.dialog.tmp)
echo "--stdout --no-cancel --no-items --backtitle \"Locale setup\" --checklist \"Select any additional locales\" 20 40 20${checklistinput}" > /tmp/.dialog.tmp
otherlocales=$(dialog --file /tmp/.dialog.tmp)
rm /tmp/.dialog.tmp

# setup locale.gen
section "Locale setup"
mv /mnt/etc/locale.gen /mnt/etc/locale.gen.tmp
echo -e "### this section was made automatically by autoarch\n### see below for the original file" > /mnt/etc/locale.gen
for line in $(echo -n "${primarylocale} ${otherlocales}"); do; echo "${line}.UTF-8 UTF-8" >> /mnt/etc/locale.gen; done
cat /mnt/etc/locale.gen.tmp >> /mnt/etc/locale.gen && rm /mnt/etc/locale.gen.tmp  # append original

# generate/setup locales
arch-chroot /mnt locale-gen  # generate locales
echo "LANG=${primarylocale}.UTF-8" > /mnt/etc/locale.conf  # set primary locale


# initramfs
section "initramfs"
arch-chroot /mnt mkinitcpio -P


# grub install
section "GRUB install and setup"
if [ $efi = "true" ]; then
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    arch-chroot /mnt grub-install --target=i386-pc /dev/$dev
fi


# grub config
section "GRUB install and setup"
echo -e "You will now have a chance to edit your GRUB config\nIf you are fine with the default, just exit nano with Ctrl-X"
read "?Press ENTER when you are ready"

nano /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# setup users + passwords
section "Local accounts setup"
echo -ne "Creating a non-root sudoer user.\nEnter desired username (cannot contain spaces): "
read username
arch-chroot /mnt useradd -m -G wheel -s /bin/bash $username
echo -e "\n(note: if password setting fails in this section, the default password is the same as username)"
echo "Setting up password for ${username}:"
echo -e "${username}\n${username}\n" | arch-chroot /mnt passwd $username > /dev/null 2>&1 # setup default password so login possible if passwd fails
arch-chroot /mnt passwd $username
echo -e "\nSetting up password for root user:"
echo -e "root\nroot\n" | arch-chroot /mnt passwd > /dev/null 2>&1 # setup default password so login possible if passwd fails
arch-chroot /mnt passwd


# choose hostname
echo $(dialog --stdout --nocancel --backtitle "Hostname setup" --inputbox "Choose a hostname for your computer (such as '${username}-pc')" 10 60) > /mnt/etc/hostname
echo "127.0.0.1 localhost" >> /mnt/etc/hosts
echo "::1 localhost" >> /mnt/etc/hosts


# setup sudo
section "Sudo setup"
mv /mnt/etc/sudoers /mnt/etc/sudoers.bak
echo "## setup by a script. see /etc/sudoers.bak for the default file." > /mnt/etc/sudoers
echo "root ALL=(ALL) ALL" >> /mnt/etc/sudoers
echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
echo "@includedir /etc/sudoers.d" >> /mnt/etc/sudoers


# aur helper
REPLY=$(dialog --stdout --nocancel --backtitle "AUR helper installation" --menu "Choose an AUR helper" 20 40 20 \
1 "yay" 2 "paru" 3 "aura" 4 "None")
section "AUR helper installation"
case $REPLY in
    1)
        pkg="yay-bin" ;;
    2)
        pkg="paru-bin" ;;
    3)
        pkg="aura-bin" ;;
esac

if [[ $REPLY -ne 4 ]]; then
    # install pkg from aur manually
    git clone https://aur.archlinux.org/${pkg}.git
    mv ${pkg} /mnt/home/${username}/${pkg}
    arch-chroot /mnt chmod a+w /home/${username} /home/${username}/${pkg}  # makepkg needs specific perms
    arch-chroot /mnt sudo -u $username bash -c "cd /home/${username}/${pkg} && makepkg -si"
    rm -rf /mnt/home/${username}/${pkg}
    arch-chroot /mnt chmod 755 /home/${username}  # set permissions back to something more reasonable
fi


# desktop environment
REPLY=$(dialog --stdout --nocancel --backtitle "Desktop environment installation" --menu "Choose a desktop environment" 20 40 20 \
1 "KDE Plasma" 2 "xfce4" 3 "LXQt" 4 "GNOME" 5 "Cinnamon" 6 "MATE" 7 "Budgie" 8 "None")
section "Desktop environment installation"
case $REPLY in
    1)  # plasma
        pacstrap /mnt --noconfirm sddm plasma ark dolphin dolphin-plugins gwenview kate konsole partitionmanager
        arch-chroot /mnt systemctl enable sddm ;;
    2)  # xfce
        pacstrap /mnt --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
        arch-chroot /mnt systemctl enable lightdm ;;
    3)  # lxqt
        pacstrap /mnt --noconfirm lxqt breeze-icons sddm xscreensaver xautolock xdg-utils
        arch-chroot /mnt systemctl enable sddm ;;
    4)  # gnome
        pacstrap /mnt --noconfirm gnome gnome-tweaks gnome-usage
        arch-chroot /mnt systemctl enable gdm ;;
    5)  # cinnamon
        pacstrap /mnt --noconfirm cinnamon xterm xed lightdm lightdm-gtk-greeter
        arch-chroot /mnt systemctl enable lightdm ;;
    6)  # mate
        pacstrap /mnt --noconfirm mate mate-extra lightdm lightdm-gtk-greeter blueman
        arch-chroot /mnt systemctl enable lightdm ;;
    7)  # budgie
        pacstrap /mnt --noconfirm budgie-extras budgie-screensaver gnome-control-center budgie-desktop-view gedit gnome-terminal gdm
        arch-chroot /mnt systemctl enable gdm ;;
esac


# browser
REPLY=$(dialog --stdout --nocancel --backtitle "Web browser installation" --menu "Choose a browser to install" 20 40 20 \
1 "Firefox" 2 "Chromium" 3 "qutebrowser" 4 "Vivaldi" 5 "None")
section "Web browser installation"
case $REPLY in
    1)
        pacstrap /mnt --noconfirm firefox ;;
    2)
        pacstrap /mnt --noconfirm chromium ;;
    3)
        pacstrap /mnt --noconfirm qutebrowser ;;
    4)
        pacstrap /mnt --noconfirm vivaldi ;;
esac


# vm guest stuff
if dmesg | grep -i "manufacturer: vmware" > /dev/null 2>&1; then
    if dialog --backtitle "VM Guest Tools" --yesno "VMware detected. Would you like to setup open-vm-tools?" 10 60; then
        section "VM Guest Tools"
        pacstrap /mnt --noconfirm open-vm-tools
        arch-chroot /mnt systemctl enable vmtoolsd
        arch-chroot /mnt systemctl enable vmware-vmblock-fuse
    fi
fi

if dmesg | grep -i "manufacturer: virtualbox" > /dev/null 2>&1; then
    if dialog --backtitle "VM Guest Tools" --yesno "VirtualBox detected. Would you like to setup virtualbox-guest-utils?" 10 60; then
        section "VM Guest Tools"
        pacstrap /mnt --noconfirm virtualbox-guest-utils
    fi
fi


# fonts
if dialog --backtitle "Fonts" --title "Optional fonts" --yesno "Would you like to install a large collection of fonts?" 10 60; then
    section "Fonts"
    pacstrap /mnt --noconfirm ttf-liberation ttf-droid gnu-free-fonts ttf-roboto noto-fonts ttf-ubuntu-font-family ttf-cascadia-code ttf-anonymous-pro ttf-hack ttf-jetbrains-mono
fi


# microcode
REPLY=$(dialog --stdout --nocancel --backtitle "CPU microcode patches" --menu "Choose which CPU microcode patches to install" 20 40 20 \
1 "Intel" 2 "AMD" 3 "None")
section "CPU microcode patches"
case $REPLY in
    1)
        echo "Installing Intel microcode patches..."
        pacstrap /mnt --noconfirm intel-ucode
        echo "Reconfiguring GRUB to work correctly with these microcode patches..."
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        ;;
    2)
        echo "Installing AMD microcode patches..."
        pacstrap /mnt --noconfirm amd-ucode
        echo "Reconfiguring GRUB to work correctly with these microcode patches..."
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        ;;
esac


# finishing up
if dialog --backtitle "END" --title "All finished!" --yesno "Would you like to reboot now?" 10 60; then
    reboot
fi
