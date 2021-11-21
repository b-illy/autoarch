## Overview

Autoarch is a script to install [Arch Linux](https://archlinux.org) to be ran within a live environment. It stays true to the [Arch wiki's installation guide](https://wiki.archlinux.org/title/Installation_guide), but makes the process much quicker and easier by removing the need to remember the process or manually enter commands.<br><br>
NOTE: When partitioning manually, the script still assumes some things about the disks and partitions. For example, it will try to install GRUB to the initially chosen disk and will assume the bootloader partition is at `/boot`.<br>

## Usage

This script is designed only for use with zsh (installed on the archiso already). For a one-line command to both download and run the script:

`curl -O https://b-illy.github.io/autoarch/autoarch.sh && zsh autoarch.sh`

(or, alternatively, [click here](https://b-illy.github.io/autoarch/autoarch.sh) to download)

Of course, this script will only function properly within an [Arch Linux](https://archlinux.org/download) live environment (booted from USB/CD/DVD). Make sure to use the latest image (or at least something relatively recent) to avoid errors.
