#!/bin/bash

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Vérification que le script est exécuté en tant que root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Ce script doit être exécuté avec les privilèges root${NC}" >&2
  exit 1
fi

# Détection de la distribution
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS=$ID
  OS_LIKE=$ID_LIKE
else
  echo -e "${RED}Impossible de détecter la distribution.${NC}" >&2
  exit 1
fi

# Mise à jour du système et installation des paquets
if [[ "$OS" == "fedora" || "$OS_LIKE" == "fedora" ]]; then
  echo -e "${GREEN}Système Fedora détecté.${NC}"
  echo -e "${YELLOW}Installation des paquets de virtualisation...${NC}"
  dnf install -y @virtualization
elif [[ "$OS" == "arch" || "$OS_LIKE" == "arch" ]]; then
  echo -e "${GREEN}Système basé sur Arch Linux détecté.${NC}"
  echo -e "${YELLOW}Installation de KVM, QEMU, et Virt-Manager...${NC}"
  pacman -S --noconfirm qemu virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat dmidecode libguestfs
elif [[ "$OS" == "ubuntu" || "$OS_LIKE" == "ubuntu" || "$OS_LIKE" == "debian" || "$OS" == "debian" || "$OS_LIKE" == "linuxmint" || "$OS" == "linuxmint" ]]; then
  echo -e "${GREEN}Système basé sur Debian/Ubuntu détecté.${NC}"
  echo -e "${YELLOW}Installation de KVM, QEMU, et Virt-Manager...${NC}"
  apt update
  apt install -y virt-manager
else
  echo -e "${RED}Distribution non supportée : $OS${NC}" >&2
  exit 1
fi

# Configuration des permissions pour libvirtd
echo -e "${YELLOW}Configuration des permissions pour libvirtd...${NC}"
sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf
sed -i 's/#unix_sock_rw_perms = "0770"/unix_sock_rw_perms = "0770"/' /etc/libvirt/libvirtd.conf

# Activation et démarrage du service libvirtd
echo -e "${YELLOW}Activation et démarrage du service libvirtd...${NC}"
systemctl enable --now libvirtd

# Ajout de l'utilisateur initial (non root) au groupe libvirt et kvm
CURRENT_USER=${SUDO_USER:-$(whoami)}
echo -e "${YELLOW}Ajout de l'utilisateur ${CURRENT_USER} au groupe libvirt et kvm...${NC}"
usermod -a -G libvirt "${CURRENT_USER}"
usermod -a -G kvm "${CURRENT_USER}"

# Redémarrage du service libvirtd
systemctl restart libvirtd.service

# Fin de l'installation
echo -e "${GREEN}Installation terminée avec succès. Veuillez vous déconnecter et vous reconnecter pour que les modifications prennent effet.${NC}"
