#!/bin/bash

###############################################################################
# Script for configuring KVM / QEMU / Virt-Manager based on the distribution  #
# WARNING: must be executed as root or via sudo                               #
###############################################################################

##############################
#         Colors            #
##############################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

##############################
#  Utility Functions       #
##############################
color_echo() {
  local color="$1"
  shift
  echo -e "${color}$*${NC}"
}

install_or_exit() {
  if ! "$@"; then
    color_echo "$RED" "The command \"$*\" failed. Aborting."
    exit 1
  fi
}

##############################
#   Root/sudo Check        #
##############################
if [ "$(id -u)" -ne 0 ]; then
  color_echo "$RED" "This script must be executed with root privileges (sudo)."
  exit 1
fi

##############################
#   systemctl Check        #
##############################
if ! command -v systemctl >/dev/null 2>&1; then
  color_echo "$RED" "systemctl not found. Make sure you are using a distribution with systemd."
  exit 1
fi

##################################
#   Distribution Detection   #
##################################
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS="${ID}"
  OS_LIKE="${ID_LIKE}"
else
  color_echo "$RED" "Unable to detect the distribution via /etc/os-release."
  exit 1
fi

################################################
# Update + Installation of KVM Packages        #
################################################

case "${OS}" in
  fedora)
    color_echo "$GREEN" "Fedora system detected."
    color_echo "$YELLOW" "Updating the system..."
    install_or_exit dnf -y upgrade
    color_echo "$YELLOW" "Installing virtualization packages..."
    install_or_exit dnf -y install @virtualization
    ;;

  arch|cachyos)
    color_echo "$GREEN" "Arch Linux-based system detected."
    color_echo "$YELLOW" "Updating the system..."
    install_or_exit pacman -Syu --noconfirm
    color_echo "$YELLOW" "Installing KVM, QEMU, and Virt-Manager..."
    install_or_exit pacman -S --noconfirm qemu virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat dmidecode libguestfs
    ;;

  ubuntu|debian|linuxmint)
    color_echo "$GREEN" "Debian/Ubuntu-based system detected."
    color_echo "$YELLOW" "Updating the system..."
    install_or_exit apt update
    install_or_exit apt upgrade -y
    color_echo "$YELLOW" "Installing KVM, QEMU, and Virt-Manager..."
    install_or_exit apt install -y virt-manager
    ;;

  *)
    if [[ "${OS_LIKE}" == *"fedora"* ]]; then
      color_echo "$GREEN" "Fedora-related distribution detected (ID_LIKE=${OS_LIKE})."
      color_echo "$YELLOW" "Updating the system..."
      install_or_exit dnf -y upgrade
      color_echo "$YELLOW" "Installing virtualization packages..."
      install_or_exit dnf -y install @virtualization

    elif [[ "${OS_LIKE}" == *"arch"* ]]; then
      color_echo "$GREEN" "Arch-related distribution detected (ID_LIKE=${OS_LIKE})."
      color_echo "$YELLOW" "Updating the system..."
      install_or_exit pacman -Syu --noconfirm
      color_echo "$YELLOW" "Installing KVM, QEMU, and Virt-Manager..."
      install_or_exit pacman -S --noconfirm qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat dmidecode libguestfs

    elif [[ "${OS_LIKE}" == *"debian"* || "${OS_LIKE}" == *"ubuntu"* ]]; then
      color_echo "$GREEN" "Debian/Ubuntu-related distribution detected (ID_LIKE=${OS_LIKE})."
      color_echo "$YELLOW" "Updating the system..."
      install_or_exit apt update
      install_or_exit apt upgrade -y
      color_echo "$YELLOW" "Installing KVM, QEMU, and Virt-Manager..."
      install_or_exit apt install -y virt-manager

    else
      color_echo "$RED" "Unsupported distribution: OS=${OS}, OS_LIKE=${OS_LIKE}"
      exit 1
    fi
    ;;
esac

######################################################
#  Adding the user to the libvirt and kvm groups     #
######################################################
CURRENT_USER=${SUDO_USER:-$(whoami)}
if [ -z "$CURRENT_USER" ]; then
  color_echo "$RED" "Unable to determine the current user (SUDO_USER or whoami)."
  exit 1
fi

color_echo "$YELLOW" "Adding the user ${CURRENT_USER} to the libvirt and kvm groups..."
if getent group libvirt >/dev/null 2>&1; then
  usermod -a -G libvirt "${CURRENT_USER}"
else
  color_echo "$RED" "The 'libvirt' group is not found on this system."
fi

if getent group kvm >/dev/null 2>&1; then
  usermod -a -G kvm "${CURRENT_USER}"
else
  color_echo "$RED" "The 'kvm' group is not found on this system."
fi

######################################################
# Transition to Modular Libvirt Daemons              #
######################################################
color_echo "$YELLOW" "Configuring modular Libvirt daemons..."

# 1. Stop and disable the old monolithic daemon if it's active
if systemctl is-active --quiet libvirtd.service || systemctl is-active --quiet libvirtd.socket; then
  color_echo "$YELLOW" "Monolithic libvirtd detected. Stopping and disabling..."
  systemctl stop libvirtd.service
  systemctl stop libvirtd{,-ro,-admin,-tcp,-tls}.socket 2>/dev/null || true
  systemctl disable libvirtd.service
  systemctl disable libvirtd{,-ro,-admin,-tcp,-tls}.socket 2>/dev/null || true
  
  # Mask to prevent accidental start as recommended by Libvirt documentation
  systemctl mask libvirtd.service
  systemctl mask libvirtd{,-ro,-admin,-tcp,-tls}.socket 2>/dev/null || true
fi

# 2. Enable and start the new modular daemons and sockets
color_echo "$YELLOW" "Enabling modular sockets (virtqemud, virtnetworkd, etc.)..."

for drv in qemu interface network nodedev nwfilter secret storage proxy; do
  # Unmask in case they were previously masked
  systemctl unmask virt${drv}d.service 2>/dev/null || true
  systemctl unmask virt${drv}d{,-ro,-admin}.socket 2>/dev/null || true

  # Enable services and sockets
  systemctl enable virt${drv}d.service 2>/dev/null || true
  systemctl enable virt${drv}d{,-ro,-admin}.socket 2>/dev/null || true
done

color_echo "$YELLOW" "Starting modular sockets..."
for drv in qemu network nodedev nwfilter secret storage proxy; do
  systemctl start virt${drv}d{,-ro,-admin}.socket 2>/dev/null || true
done

#############################
#     End of Installation   #
#############################
color_echo "$GREEN" "Installation and configuration completed successfully."
color_echo "$GREEN" "Please log out and log back in for the group changes to take effect."
