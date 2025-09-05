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
$SUDO apt-get install -y ufw fail2ban unattended-upgrades apt-listchanges chkrootkit rkhunter rsyslog logwatch


#yet to add more hardening steps

#change SSH port from 22 to 2222
#$SUDO sed -i '/^#Port 22/s/^#//' /etc/ssh/sshd_config

# Disable root SSH login
#$SUDO sed -i 's/^#*PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

read -p "enter delegated admin username: " usernm
echo
echo "Creating user "$usernm" with sudo privileges"
$SUDO useradd -m -s /bin/bash $usernm
echo
$SUDO passwd $usernm

mv /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat <<'SSHD' >> "/etc/ssh/sshd_config"
Include /etc/ssh/sshd_config.d/*.conf
Protocol 2
Port 2232

# ===== Authentication =====
# Prefer key-based auth + TOTP over passwords.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication yes
UsePAM yes
LoginGraceTime 1m
MaxAuthTries 2
MaxSessions 2
PermitEmptyPasswords no
permittunnel no
ClientAliveInterval 60
ClientAliveCountMax 2
maxstartups 10:30:100

X11Forwarding no

LogLevel VERBOSE

SyslogFacility AUTHPRIV

#Uncomment the below line only if you're sure
PermitRootLogin no

HostbasedAuthentication no

VersionAddendum none

RhostsRSAAuthentication no

#uncomment the below line  and replace it with your local network range
#Match Address 10.0.0.0/24
SSHD