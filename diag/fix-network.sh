#!/bin/bash
#run this script when you suspect the network issue is caused by corrupted iptables
# Define backup directory and file
BACKUP_DIR="/etc/iptables/backup"
BACKUP_FILE="$BACKUP_DIR/rules.v4.backup_$(date +%F_%T)"

# Create backup directory if it does not exist
mkdir -p $BACKUP_DIR

# Backup existing iptables rules
if [ -f /etc/iptables/rules.v4 ]; then
    cp /etc/iptables/rules.v4 $BACKUP_FILE
    echo "Backup of existing iptables rules saved to $BACKUP_FILE"
else
    echo "No existing iptables rules to backup."
fi

# Flush existing iptables rules
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X
iptables -t nat -X
iptables -t mangle -X

# Enable IP forwarding (already enabled, but included for completeness)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Set up new iptables rules

# Enable NAT for outgoing traffic on wlp45s0
iptables -t nat -A POSTROUTING -o wlp45s0 -j MASQUERADE

# Allow forwarding from vmbr0 to wlp45s0
iptables -A FORWARD -i vmbr0 -o wlp45s0 -j ACCEPT

# Allow established connections from wlp45s0 to vmbr0
iptables -A FORWARD -i wlp45s0 -o vmbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

# Ensure iptables-persistent is installed for rules to persist across reboots
if ! dpkg -s iptables-persistent > /dev/null 2>&1; then
    apt-get update
    apt-get install -y iptables-persistent
fi

# Reload iptables-persistent to ensure rules are applied on reboot
systemctl restart iptables-persistent

echo "iptables rules applied and saved successfully."