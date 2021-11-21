autoload colors; colors  # allow coloured echo commands

section() {  # function to easily print section titles
    echo $fg_bold[cyan]
    clear
    echo -e "${1}${reset_color}\n--------------------------------------------------------\n"
}

if [ "$EUID" != "0" ]; then
    echo "ERROR: Must be ran as root user in an archlinux live environment"
    exit
fi

section "AutoArch - Arch Linux installation script"
read "?Press ENTER to start"

section "Initial checks and setup"

# check if booted in efi or bios mode
if ls /sys/firmware/efi/efivars > /dev/null 2>&1; then
    efi=true
    echo -ne "\nRunning in EFI"
else
    efi=false
    echo -ne "\nRunning in BIOS"
fi

echo " mode, if this was unexpected, check motherboard settings to make sure you boot in the correct mode"


# check if there is already an internet connection
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
            read "?Press ENTER to continue anyway or Ctrl-C to exit"
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


# setup keyboard layout
(
    echo "Showing all keyboard layouts. Find yours and remember the text between the last / and .map.gz"
    echo -e "Tip: use the up/down arrow keys to scroll and press q to exit this menu and continue\n"
    ls /usr/share/kbd/keymaps/**/*.map.gz
) | less

echo -ne "\nPlease enter a keyboard layout: "
read keymap
loadkeys "$keymap" > /dev/null 2>&1


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
    read "?Would you like to change the swap amount (enter 1) or use the suggested amount (enter 2)? "
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
lsblk -S
read dev"?Choose a disk from this list to partition (e.g. 'sda' or 'nvme0n1'): /dev/"
devp=$dev # ensure partitions on nvme drives (nvme0n1 -> nvme0n1p1 vs sda -> sda1) are referred to correctly
if [[ $dev == nvme* ]]; then
    devp="${dev}p"
fi

# select partition tool / method
section "Partitioning"
while [ true ]; do
    read manualpart"?Would you like to partition manually (enter 1) or automatically (enter 2)? "
    if [ $manualpart = "1" ]; then
        # manual partitioning

        while [ true ]; do
            echo -e "\n1) parted (cli)\n2) fdisk (cli)\n3) cfdisk (ncurses gui)"
            read "?Select a program to partition with (e.g. 1): "
            if [ $REPLY = "1" ]; then
                parted /dev/$dev
                break
            elif [ $REPLY = "2" ]; then
                fdisk /dev/$dev
                break
            elif [ $REPLY = "3" ]; then
                cfdisk /dev/$dev
                break
            else
                echo "invalid input"
            fi
        done
        echo "Now that you have set up partitions, you will have to format and mount them"
        echo "Press alt + left/right arrow to switch between terminals"
        read "?Press ENTER when you have finished to continue"
        break
    elif [ $manualpart = "2" ]; then
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
        break
    else
        echo "invalid input"
    fi
done


# choose linux kernel version to use
section "Main system setup"
while [ true ]; do
    echo "Please select your preferred kernel:"
    echo "1) Linux - most updated kernel version"
    echo "2) Linux LTS - stable release, updated less often"
    echo "3) Linux Hardened - very security-focused branch, fewer features"
    echo "4) Linux Zen - optimised for performance"
    read "?Your choice of kernel (enter a number): "
    if [ $REPLY = "1" ]; then
        kernel="linux"
        break
    elif [ $REPLY = "2" ]; then
        kernel="linux-lts"
        break
    elif [ $REPLY = "3" ]; then
        kernel="linux-hardened"
        break
    elif [ $REPLY = "4" ]; then
        kernel="linux-zen"
        break
    else
        echo "invalid input"
    fi
done


# install core system + useful packages
section "Main system setup"
echo "Ready to install core packages and set up the system (will likely take several minutes)"
read "?Press ENTER when you are ready"
# install packages
pacstrap /mnt base $kernel linux-firmware networkmanager xorg neofetch git base-devel grub efibootmgr os-prober btrfs-progs dosfstools e2fsprogs ntfs-3g xfsprogs nano vim man-db man-pages texinfo --noconfirm
pacman -Sy
pacman -S git --noconfirm  # also install git to live environment to install yay later
# other useful setup stuff
echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf  # save keymap across reboots on new system
genfstab -U /mnt >> /mnt/etc/fstab  # generate fs table for partitions to actually get mounted
arch-chroot /mnt systemctl enable NetworkManager


# setup timezone
clear

(
    echo "This is a list of all available timezones and the filepaths to them"
    echo -e "Take note of the path (after /usr/share/zoneinfo/) for your timezone (e.g. Europe/London)\n"
    ls /mnt/usr/share/zoneinfo/**/*
) | less

echo -ne "\nInput path to desired timezone: /usr/share/zoneinfo/"
read timezone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
arch-chroot /mnt hwclock --systohc


# setup locale - locale.gen
section "Locale setup"
echo "Setting up locale..."
echo "You will have to uncomment (removing the '#' at the start of the line) any desired locales."
echo "It is recommend to only use the UTF8 variants and also to include en_US.UTF8"
echo "Remember your main locale's name (everything before the first space) as you will need it later"
read "?Press ENTER when you are ready"
nano /mnt/etc/locale.gen
arch-chroot /mnt locale-gen


# setup locale - choose main locale    
section "Locale setup"
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
echo "You will now have to replace en_US.UTF8 with your desired primary locale"
read "?Press ENTER when you are ready"
nano /mnt/etc/locale.conf


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
section "Setup machine hostname"
echo -ne "\nChoose a hostname for your computer, such as '${username}-pc': "
read hostname
echo $hostname > /mnt/etc/hostname
echo "127.0.0.1 localhost" >> /mnt/etc/hosts
echo "::1 localhost" >> /mnt/etc/hosts


# setup sudo
section "Sudo setup"
mv /mnt/etc/sudoers /mnt/etc/sudoers.bak
echo "## setup by a script. see /etc/sudoers.bak for the default file." > /mnt/etc/sudoers
echo "root ALL=(ALL) ALL" >> /mnt/etc/sudoers
echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
echo "@includedir /etc/sudoers.d" >> /mnt/etc/sudoers


# install yay
section "Yay (AUR helper) installation"
git clone https://aur.archlinux.org/yay-bin.git
mv yay-bin /mnt/home/${username}/yay-bin
arch-chroot /mnt chmod a+w /home/${username} /home/${username}/yay-bin  # makepkg needs specific perms
arch-chroot /mnt sudo -u $username bash -c "cd /home/${username}/yay-bin && makepkg -si"
rm -rf /mnt/home/${username}/yay-bin
arch-chroot /mnt chmod 755 /home/${username}  # set permissions back to something more reasonable


# desktop environment
section "Desktop environment installation"
while [ true ]; do
    echo -e "1) KDE Plasma (recommended for beginners)\n2) Xfce4\n3) LXQt\n4) GNOME\n5) Cinnamon\n6) None / manual install"
    echo "All installs will also include at least a display manager, filemanager and terminal emulator"
    read "?Select one of the above options to install (enter a number): "
    if [ $REPLY = "1" ]; then
        pacstrap /mnt sddm plasma ark dolphin dolphin-plugins gwenview kate konsole partitionmanager --noconfirm
        arch-chroot /mnt systemctl enable sddm
        break
    elif [ $REPLY = "2" ]; then
        pacstrap /mnt xfce4 xfce4-goodies lightdm lightdm-gtk-greeter --noconfirm
        arch-chroot /mnt systemctl enable lightdm
        break
    elif [ $REPLY = "3" ]; then
        pacstrap /mnt lxqt breeze-icons sddm xscreensaver xautolock xdg-utils --noconfirm
        arch-chroot /mnt systemctl enable sddm
        break
    elif [ $REPLY = "4" ]; then
        pacstrap /mnt gnome gnome-tweaks gnome-usage --noconfirm
        arch-chroot /mnt systemctl enable gdm
        break
    elif [ $REPLY = "5" ]; then
        pacstrap /mnt cinnamon xterm xed lightdm lightdm-gtk-greeter --noconfirm
        arch-chroot /mnt systemctl enable lightdm
        break
    elif [ $REPLY = "6" ]; then
        break
    else
        echo "invalid input"
    fi
done


# browser
section "Web browser installation"
while [ true ]; do
    echo -e "1) Firefox\n2) Chromium\n3) qutebrowser\n4) Vivaldi\n5) None / manual install"
    read "?Choose a browser to install (enter a number): "
    if [ $REPLY = "1" ]; then
        pacstrap /mnt firefox --noconfirm
        break
    elif [ $REPLY = "2" ]; then
        pacstrap /mnt chromium --noconfirm
        break
    elif [ $REPLY = "3" ]; then
        pacstrap /mnt qutebrowser --noconfirm
        break
    elif [ $REPLY = "4" ]; then
        pacstrap /mnt vivaldi --noconfirm
        break
    elif [ $REPLY = "5" ]; then
        break
    else
        echo "invalid input"
    fi
done


# vm guest stuff
section "VM guest tools setup"

# vmware
if dmesg | grep -i "manufacturer: vmware" > /dev/null 2>&1; then
    while [ true ]; do
        read "?VMware detected. Would you like to setup open-vm-tools (1=yes, 2=no)? "
        if [ $REPLY = "1" ]; then
            pacstrap /mnt open-vm-tools --noconfirm
            arch-chroot /mnt systemctl enable vmtoolsd
            arch-chroot /mnt systemctl enable vmware-vmblock-fuse
            break
        elif [ $REPLY = "2" ]; then
            break
        else
            echo "invalid input"
        fi
    done
fi


# virtualbox
if dmesg | grep -i "manufacturer: virtualbox" > /dev/null 2>&1; then
    while [ true ]; do
        read "?VirtualBox detected. Would you like to setup virtualbox-guest-utils (1=yes, 2=no)? "
        if [ $REPLY = "1" ]; then
            pacstrap /mnt virtualbox-guest-utils --noconfirm
            break
        elif [ $REPLY = "2" ]; then
            break
        else
            echo "invalid input"
        fi
    done
fi


# fonts
section "Optional fonts"
while [ true ]; do
    read "?Would you like to install a large collection of fonts (enter 1) or just use the preinstalled ones for now (enter 2)? "
    if [ $REPLY = "1" ]; then
        pacstrap /mnt ttf-liberation ttf-droid gnu-free-fonts ttf-roboto noto-fonts ttf-ubuntu-font-family ttf-cascadia-code ttf-anonymous-pro ttf-hack ttf-jetbrains-mono --noconfirm
        break
    elif [ $REPLY = "2" ]; then
        break
    else
        echo "invalid input"
    fi
done


# microcode
section "CPU microcode patches"
while [ true ]; do
    echo -e "CPU microcode patches:\n1) Intel\n2) AMD\n3) None"
    read "?Choose which CPU microcode patches to install (enter a number): "
    if [ $REPLY = "1" ]; then
        echo "Installing Intel microcode patches..."
        pacstrap /mnt intel-ucode --noconfirm
        echo "Reconfiguring GRUB to work correctly with these microcode patches..."
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        break
    elif [ $REPLY = "2" ]; then
        echo "Installing AMD microcode patches..."
        pacstrap /mnt amd-ucode --noconfirm
        echo "Reconfiguring GRUB to work correctly with these microcode patches..."
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        break
    elif [ $REPLY = "3" ]; then
        break
    else
        echo "invalid input"
    fi
done


# finishing up
section "END"
echo -e "All done!\nYou should be good to reboot now\n"
while [ true ]; do
    read "?Reboot now (1=yes, 2=no)? "
    if [ $REPLY = "1" ]; then
        reboot
        break
    elif [ $REPLY = "2" ]; then
        exit
        break
    else
        echo "invalid input"
    fi
done
