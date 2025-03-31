Voici un commentaire détaillé pour chaque fonction et section du script. Cela explique chaque étape de manière claire et concise.

#!/bin/bash

# === VARIABLES ===
TIMESTAMP=$(date +"%Y%m%d_%H%M%S") 
# Crée un horodatage au format "YYYYMMDD_HHMMSS" pour l'utiliser dans le nom du fichier de log.

LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log"
# Déclare un répertoire pour stocker les logs et définit le fichier de log à créer avec l'horodatage.

CONFIG_DIR="./config"
# Déclare le répertoire de configuration où se trouvent les fichiers comme "motd.txt", "bashrc.append", etc.

PACKAGE_LIST="./lists/packages.txt"
# Définit le fichier contenant la liste des paquets à installer.

USERNAME=$(logname)
USER_HOME="/home/$USERNAME"
# Récupère le nom d'utilisateur et déduit le chemin du répertoire personnel de l'utilisateur.

# === FUNCTIONS ===

log() {
  # Fonction de log qui ajoute des messages au fichier de log avec un horodatage.
  # "tee -a" permet d'afficher également le message dans le terminal en plus de l'ajouter au fichier de log.
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_and_install() {
  # Cette fonction vérifie si un paquet est déjà installé.
  # Si le paquet est installé, un message est enregistré, sinon il est installé via apt.
  # Les logs de l'installation (ou de l'échec) sont également ajoutés au fichier de log.
  local pkg=$1
  if dpkg -s "$pkg" &>/dev/null; then
    log "$pkg is already installed."
  else
    log "Installing $pkg..."
    apt install -y "$pkg" &>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "$pkg successfully installed."
    else
      log "Failed to install $pkg."
    fi
  fi
}

ask_yes_no() {
  # Fonction qui demande à l'utilisateur une réponse oui/non.
  # Retourne 0 pour "oui" et 1 pour "non".
  read -p "$1 [y/N]: " answer
  case "$answer" in
    [Yy]* ) return 0 ;;
    * ) return 1 ;;
  esac
}

# === INITIAL SETUP ===

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
log "Starting post-installation script. Logged user: $USERNAME"
# Crée le répertoire des logs et le fichier de log. Enregistre un message de démarrage.

if [ "$EUID" -ne 0 ]; then
  log "This script must be run as root."
  exit 1
fi
# Vérifie si le script est exécuté avec les privilèges root (ID utilisateur différent de 0). Si ce n'est pas le cas, le script s'arrête.

# === 1. SYSTEM UPDATE ===
log "Updating system packages..."
apt update && apt upgrade -y &>>"$LOG_FILE"
# Met à jour les paquets système en utilisant apt et enregistre les logs.

# === 2. PACKAGE INSTALLATION ===
if [ -f "$PACKAGE_LIST" ]; then
  log "Reading package list from $PACKAGE_LIST"
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
    check_and_install "$pkg"
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation."
fi
# Vérifie si le fichier contenant la liste des paquets existe.
# Si oui, il lit chaque ligne du fichier, ignore les lignes vides et les commentaires (lignes commençant par #), et installe chaque paquet via la fonction `check_and_install`.

# === 3. UPDATE MOTD ===
if [ -f "$CONFIG_DIR/motd.txt" ]; then
  cp "$CONFIG_DIR/motd.txt" /etc/motd
  log "MOTD updated."
else
  log "motd.txt not found."
fi
# Si un fichier "motd.txt" est trouvé dans le répertoire de configuration, il remplace le fichier "/etc/motd" pour modifier le Message Of The Day (MOTD).
# Sinon, il enregistre que le fichier n'a pas été trouvé.

# === 4. CUSTOM .bashrc ===
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi
# Si le fichier "bashrc.append" existe dans le répertoire de configuration, il est ajouté au fichier ".bashrc" de l'utilisateur.
# Cela permet de personnaliser le comportement du shell pour l'utilisateur.

# === 5. CUSTOM .nanorc ===
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi
# Si le fichier "nanorc.append" existe, il est ajouté au fichier ".nanorc" de l'utilisateur pour personnaliser les paramètres de l'éditeur nano.

# === 6. ADD SSH PUBLIC KEY ===
if ask_yes_no "Would you like to add a public SSH key?"; then
  read -p "Paste your public SSH key: " ssh_key
  mkdir -p "$USER_HOME/.ssh"
  echo "$ssh_key" >> "$USER_HOME/.ssh/authorized_keys"
  chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  log "SSH public key added."
fi
# Demande à l'utilisateur s'il souhaite ajouter une clé SSH publique.
# Si l'utilisateur accepte, il est invité à coller la clé publique, qui est ensuite ajoutée au fichier "authorized_keys" dans son répertoire ".ssh".
# Les permissions du répertoire ".ssh" et du fichier "authorized_keys" sont ajustées pour des raisons de sécurité.

# === 7. SSH CONFIGURATION: KEY AUTH ONLY ===
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  log "SSH configured to accept key-based authentication only."
else
  log "sshd_config file not found."
fi
# Modifie la configuration SSH pour désactiver l'authentification par mot de passe et permettre uniquement l'authentification par clé publique.
# Le service SSH est ensuite redémarré pour appliquer les changements.

log "Post-installation script completed."
# Enregistre un message indiquant que le script a terminé.

exit 0
# Sort du script avec un code de succès.

Chaque fonction a un rôle spécifique dans ce script, allant de l'installation de paquets à la personnalisation de fichiers de configuration système, en passant par la configuration de la sécurité SSH.
 Les commentaires expliquent les actions de chaque section pour rendre le script plus facile à comprendre.

Je laisse même la réponse chatgpt - parceque honnetement, on va tous coder avec chatgpt pour ceux qui aime pas le code.
