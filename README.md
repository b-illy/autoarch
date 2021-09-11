# autoarch
archlinux installation script

## Usage

This script works best with zsh. For a one-line command to both download and run the script:

`curl -s https://raw.githubusercontent.com/b-illy/autoarch/main/autoarch.sh | zsh`

or

`zsh -c $(curl -s https://raw.githubusercontent.com/b-illy/autoarch/main/autoarch.sh)`

Alternatively, you can use this command to save a copy: (wget is not preinstalled on the live USB arch image)

`curl -o autoarch.sh https://raw.githubusercontent.com/b-illy/autoarch/main/autoarch.sh && zsh autoarch.sh`

This script will only function properly on an [archlinux](https://archlinux.org/download/) live USB
