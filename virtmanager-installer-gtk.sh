#!/bin/bash

# Si le script n'est pas root, on le relance avec pkexec ou sudo
if [ "$EUID" -ne 0 ]; then
  if command -v pkexec >/dev/null 2>&1; then
    exec pkexec "$0" "$@"
  elif command -v sudo >/dev/null 2>&1; then
    exec sudo "$0" "$@"
  else
    yad --error --text="Ce script nécessite les droits administrateur.\nInstallez 'sudo' ou 'pkexec'."
    exit 1
  fi
fi

# Détection de la distribution
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO_NAME="$NAME"
  OS="${ID}"
  OS_LIKE="${ID_LIKE}"
else
  DISTRO_NAME="Inconnue"
fi

# Détection automatique du pare-feu
AVAILABLE_FIREWALLS=()
[[ -x "$(command -v ufw)" && "$(systemctl is-active ufw)" == "active" ]] && AVAILABLE_FIREWALLS+=("ufw")
[[ -x "$(command -v firewall-cmd)" && "$(systemctl is-active firewalld)" == "active" ]] && AVAILABLE_FIREWALLS+=("firewalld")
[[ -x "$(command -v iptables)" ]] && AVAILABLE_FIREWALLS+=("iptables")

# Étape 1 : Sélection des composants
COMPONENTS=$(yad --width=500 --height=300 --center --title="KVM GTK Installer" \
  --text="Distribution détectée : $DISTRO_NAME\n\nSélectionnez les composants à installer :" \
  --form --separator=";" \
  --field="Installer QEMU/KVM/Virt-Manager:CHK" TRUE \
  --field="Configurer les groupes utilisateur:CHK" TRUE \
  --field="Activer le service libvirtd:CHK" TRUE)

IFS=";" read -r INSTALL_KVM ADD_GROUPS ENABLE_LIBVIRTD <<< "$COMPONENTS"

# Étape 2 : Pare-feu (si au moins un dispo)
FIREWALL=""
if [ ${#AVAILABLE_FIREWALLS[@]} -gt 0 ]; then
  FW_LIST=""
  for fw in "${AVAILABLE_FIREWALLS[@]}"; do
    FW_LIST+="TRUE $fw "
  done

  FIREWALL=$(yad --width=400 --center --list --radiolist \
    --title="Choix du pare-feu" \
    --column="Choix" --column="Pare-feu" $FW_LIST)

  if [ -z "$FIREWALL" ]; then
    yad --question --title="Ignorer le pare-feu ?" --text="Aucun pare-feu sélectionné.\nSouhaitez-vous continuer sans configurer de pare-feu ?"
    [[ $? -ne 0 ]] && exit 1
  fi
fi

# Étape 3 : Résumé
SUMMARY="Distribution : $DISTRO_NAME\n\nComposants à installer :"
[[ "$INSTALL_KVM" == "TRUE" ]] && SUMMARY+="\n- QEMU/KVM/Virt-Manager"
[[ "$ADD_GROUPS" == "TRUE" ]] && SUMMARY+="\n- Groupes utilisateur"
[[ "$ENABLE_LIBVIRTD" == "TRUE" ]] && SUMMARY+="\n- Activation libvirtd"
[[ -n "$FIREWALL" ]] && SUMMARY+="\n\nPare-feu choisi : $FIREWALL"

yad --width=400 --center --title="Résumé" --text="$SUMMARY" --button="Continuer":0 --button="Annuler":1
[[ $? -ne 0 ]] && exit 0

# Étape 4 : Exécution des actions avec progression
(
  echo "10"; echo "# Mise à jour du système..."
  case "$OS" in
    fedora) dnf -y upgrade ;;
    arch) pacman -Syu --noconfirm ;;
    debian|ubuntu|linuxmint) apt update && apt upgrade -y ;;
  esac

  if [[ "$INSTALL_KVM" == "TRUE" ]]; then
    echo "30"; echo "# Installation de KVM et outils..."
    case "$OS" in
      fedora) dnf install -y @virtualization ;;
      arch) pacman -S --noconfirm qemu virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat dmidecode libguestfs ;;
      debian|ubuntu|linuxmint)
        apt install -y virt-manager qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
        ;;
    esac
  fi

  if [[ "$ENABLE_LIBVIRTD" == "TRUE" ]]; then
    echo "60"; echo "# Activation de libvirtd..."
    systemctl enable --now libvirtd
  fi

  if [[ "$ADD_GROUPS" == "TRUE" ]]; then
    echo "75"; echo "# Ajout de l'utilisateur aux groupes..."
    CURRENT_USER=${SUDO_USER:-$(whoami)}
    usermod -aG libvirt "$CURRENT_USER"
    usermod -aG kvm "$CURRENT_USER"
  fi

  if [[ -n "$FIREWALL" ]]; then
    echo "85"; echo "# Configuration du pare-feu ($FIREWALL)..."
    case "$FIREWALL" in
      ufw)
        ufw allow 5900:5999/tcp
        ufw allow 16509/tcp
        ufw allow 49152:49216/tcp
        ;;
      firewalld)
        firewall-cmd --permanent --add-port=5900-5999/tcp
        firewall-cmd --permanent --add-port=16509/tcp
        firewall-cmd --permanent --add-port=49152-49216/tcp
        firewall-cmd --reload
        ;;
      iptables)
        iptables -A INPUT -p tcp --dport 5900:5999 -j ACCEPT
        iptables -A INPUT -p tcp --dport 16509 -j ACCEPT
        iptables -A INPUT -p tcp --dport 49152:49216 -j ACCEPT

        if [[ "$OS" == "debian" || "$OS_LIKE" == *"debian"* ]]; then
          apt install -y iptables-persistent
          iptables-save > /etc/iptables/rules.v4
        elif [[ "$OS" == "arch" ]]; then
          pacman -S --noconfirm iptables-nft
          iptables-save > /etc/iptables/iptables.rules
          systemctl enable --now iptables
        fi
        ;;
    esac
  fi

  echo "100"; echo "# Installation terminée !"
  sleep 1
) | yad --progress --width=500 --title="Installation KVM" --text="L'installation est en cours..." --percentage=0 --auto-close

# Fin
yad --info --title="Succès" --text="✅ Installation terminée.\n🔁 Redémarrez votre session pour appliquer les groupes."
