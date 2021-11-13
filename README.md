## Overview

Autoarch is a script to install archlinux to be ran within a live environment. It tries to stay true to the [arch wiki's installation guide](https://wiki.archlinux.org/title/Installation_guide), but makes the process much quicker and easier by removing the need to remember the process or manually enter commands.<br><br>
NOTE: When partitioning manually, the script still assumes some things about the disks and partitions. For example, it will try to install GRUB to the chosen disk and will mount the bootloader partition to /boot<br>

## Usage

This script is POSIX-compliant but works best with zsh (which is the default on the archiso anyway). For a one-line command to both download and run the script:


`curl -o autoarch.sh https://raw.githubusercontent.com/b-illy/autoarch/main/autoarch.sh && zsh autoarch.sh`


This script will only function properly within an [archlinux](https://archlinux.org/download/) live environment (booted from USB/CD/DVD)
