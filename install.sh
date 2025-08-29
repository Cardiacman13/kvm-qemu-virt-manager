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
  # Displays text with the chosen color
  # Usage: color_echo $GREEN "Message"
  local color="$1"
  shift
  echo -e "${color}$*${NC}"
}

install_or_exit() {
  # Executes the command passed as an argument
  # If the command fails, the script stops
  # Usage: install_or_exit dnf install -y @virtualization
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
    # Finer detection via ID_LIKE if necessary
    # (For example, if ID=pop for Pop!_OS, ID_LIKE=ubuntu)
    color_echo "$GREEN" "Debian/Ubuntu-based system detected."
    color_echo "$YELLOW" "Updating the system..."
    install_or_exit apt update
    install_or_exit apt upgrade -y
    color_echo "$YELLOW" "Installing KVM, QEMU, and Virt-Manager..."
    install_or_exit apt install -y virt-manager
    ;;

  *)
    # If OS is unknown but ID_LIKE is known, attempt detection via ID_LIKE
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
# Configuration of libvirtd if the file exists       #
######################################################
color_echo "$YELLOW" "Configuring permissions for libvirtd..."
if [ -f /etc/libvirt/libvirtd.conf ]; then
  sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf
  sed -i 's/#unix_sock_rw_perms = "0770"/unix_sock_rw_perms = "0770"/' /etc/libvirt/libvirtd.conf
else
  color_echo "$RED" "The file /etc/libvirt/libvirtd.conf is not found. The configuration may not be complete."
fi

######################################################
# Enabling and starting the libvirtd service         #
######################################################
color_echo "$YELLOW" "Enabling and starting the libvirtd service..."
install_or_exit systemctl enable --now libvirtd

######################################################
#  Adding the user to the libvirt and kvm groups     #
######################################################
CURRENT_USER=${SUDO_USER:-$(whoami)}
# Just in case the variable is empty (rare, but possible)
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

#############################
# Restarting the service    #
#############################
install_or_exit systemctl restart libvirtd.service

#############################
#     End of Installation   #
#############################
color_echo "$GREEN" "Installation completed successfully."
color_echo "$GREEN" "Please log out and log back in for the group changes to take effect."
