#!/bin/bash

###############################################################################
# Script de configuration de KVM / QEMU / Virt-Manager selon la distribution  #
# ATTENTION : doit être exécuté en root ou via sudo                           #
###############################################################################

##############################
#         Couleurs          #
##############################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

##############################
#  Fonctions utilitaires    #
##############################
color_echo() {
  # Affiche le texte avec la couleur choisie
  # Usage : color_echo $GREEN "Message"
  local color="$1"
  shift
  echo -e "${color}$*${NC}"
}

install_or_exit() {
  # Exécute la commande passée en argument
  # Si la commande échoue, on arrête le script
  # Usage : install_or_exit dnf install -y @virtualization
  if ! "$@"; then
    color_echo "$RED" "La commande \"$*\" a échoué. Abandon."
    exit 1
  fi
}

##############################
#   Vérification root/sudo  #
##############################
if [ "$(id -u)" -ne 0 ]; then
  color_echo "$RED" "Ce script doit être exécuté avec les privilèges root (sudo)."
  exit 1
fi

##############################
# Vérification de systemctl #
##############################
if ! command -v systemctl >/dev/null 2>&1; then
  color_echo "$RED" "systemctl est introuvable. Assurez-vous d'utiliser une distribution avec systemd."
  exit 1
fi

##################################
#   Détection de la distribution #
##################################
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS="${ID}"
  OS_LIKE="${ID_LIKE}"
else
  color_echo "$RED" "Impossible de détecter la distribution via /etc/os-release."
  exit 1
fi

################################################
# Mise à jour + installation des paquets KVM   #
################################################

case "${OS}" in
  fedora)
    color_echo "$GREEN" "Système Fedora détecté."
    color_echo "$YELLOW" "Mise à jour du système..."
    install_or_exit dnf -y upgrade
    color_echo "$YELLOW" "Installation des paquets de virtualisation..."
    install_or_exit dnf -y install @virtualization
    ;;

  arch)
    color_echo "$GREEN" "Système basé sur Arch Linux détecté."
    color_echo "$YELLOW" "Mise à jour du système..."
    install_or_exit pacman -Syu --noconfirm
    color_echo "$YELLOW" "Installation de KVM, QEMU, et Virt-Manager..."
    install_or_exit pacman -S --noconfirm qemu virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat dmidecode libguestfs
    ;;

  ubuntu|debian|linuxmint)
    # Détection plus fine via ID_LIKE si nécessaire
    # (Par exemple, si ID=pop pour Pop!_OS, ID_LIKE=ubuntu)
    color_echo "$GREEN" "Système basé sur Debian/Ubuntu détecté."
    color_echo "$YELLOW" "Mise à jour du système..."
    install_or_exit apt update
    install_or_exit apt upgrade -y
    color_echo "$YELLOW" "Installation de KVM, QEMU, et Virt-Manager..."
    install_or_exit apt install -y virt-manager
    ;;

  *)
    # Si OS n’est pas connu mais ID_LIKE l’est, on tente une détection via ID_LIKE
    if [[ "${OS_LIKE}" == *"fedora"* ]]; then
      color_echo "$GREEN" "Distribution apparentée à Fedora détectée (ID_LIKE=${OS_LIKE})."
      color_echo "$YELLOW" "Mise à jour du système..."
      install_or_exit dnf -y upgrade
      color_echo "$YELLOW" "Installation des paquets de virtualisation..."
      install_or_exit dnf -y install @virtualization

    elif [[ "${OS_LIKE}" == *"arch"* ]]; then
      color_echo "$GREEN" "Distribution apparentée à Arch détectée (ID_LIKE=${OS_LIKE})."
      color_echo "$YELLOW" "Mise à jour du système..."
      install_or_exit pacman -Syu --noconfirm
      color_echo "$YELLOW" "Installation de KVM, QEMU, et Virt-Manager..."
      install_or_exit pacman -S --noconfirm qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat dmidecode libguestfs

    elif [[ "${OS_LIKE}" == *"debian"* || "${OS_LIKE}" == *"ubuntu"* ]]; then
      color_echo "$GREEN" "Distribution apparentée à Debian/Ubuntu détectée (ID_LIKE=${OS_LIKE})."
      color_echo "$YELLOW" "Mise à jour du système..."
      install_or_exit apt update
      install_or_exit apt upgrade -y
      color_echo "$YELLOW" "Installation de KVM, QEMU, et Virt-Manager..."
      install_or_exit apt install -y virt-manager

    else
      color_echo "$RED" "Distribution non supportée : OS=${OS}, OS_LIKE=${OS_LIKE}"
      exit 1
    fi
    ;;
esac

######################################################
# Configuration de libvirtd si le fichier existe     #
######################################################
color_echo "$YELLOW" "Configuration des permissions pour libvirtd..."
if [ -f /etc/libvirt/libvirtd.conf ]; then
  sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf
  sed -i 's/#unix_sock_rw_perms = "0770"/unix_sock_rw_perms = "0770"/' /etc/libvirt/libvirtd.conf
else
  color_echo "$RED" "Le fichier /etc/libvirt/libvirtd.conf est introuvable. La configuration pourrait ne pas être complète."
fi

######################################################
# Activation et démarrage du service libvirtd        #
######################################################
color_echo "$YELLOW" "Activation et démarrage du service libvirtd..."
install_or_exit systemctl enable --now libvirtd

######################################################
#  Ajout de l'utilisateur au groupe libvirt et kvm   #
######################################################
CURRENT_USER=${SUDO_USER:-$(whoami)}
# Juste au cas où la variable serait vide (rare, mais possible)
if [ -z "$CURRENT_USER" ]; then
  color_echo "$RED" "Impossible de déterminer l'utilisateur courant (SUDO_USER ou whoami)."
  exit 1
fi

color_echo "$YELLOW" "Ajout de l'utilisateur ${CURRENT_USER} aux groupes libvirt et kvm..."
if getent group libvirt >/dev/null 2>&1; then
  usermod -a -G libvirt "${CURRENT_USER}"
else
  color_echo "$RED" "Le groupe 'libvirt' est introuvable sur ce système."
fi

if getent group kvm >/dev/null 2>&1; then
  usermod -a -G kvm "${CURRENT_USER}"
else
  color_echo "$RED" "Le groupe 'kvm' est introuvable sur ce système."
fi

#############################
# Redémarrage du service   #
#############################
install_or_exit systemctl restart libvirtd.service

#############################
#     Fin de l'installation #
#############################
color_echo "$GREEN" "Installation terminée avec succès."
color_echo "$GREEN" "Veuillez vous déconnecter et vous reconnecter pour que les modifications de groupe prennent effet."
