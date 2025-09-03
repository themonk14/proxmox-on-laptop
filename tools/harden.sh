#!/bin/bash
# This script applies various security hardening measures to a Proxmox server.

# Detect if running as root, set SUDO variable accordingly
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi  
# Ensure required tools are installed
$SUDO apt-get update
$SUDO apt-get install -y ufw fail2ban unattended-upgrades apt-listchanges chkrootkit rkhunter   logwatch


#yet to add more hardening steps