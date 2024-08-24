#!/bin/bash

#Run this script only after installing wpasupplicant and its dependencies in proxmox

#List available wifi interface
wlan_interface=$(ip link show | grep 'state UP' | awk -F: '$2 ~ /w/ {print $2}' | tr -d ' ')

initial_config() {
#This will configure the wireless interface and the vmbr0 bridge. 
#It will backup the old /etc/network/interfaces file and create a new file at the same path

read -p "Enter the WiFi you'd like to connect to : " ssid
read -p "Enter WiFi password : " psk
echo
read -p "Shall I connect to this network ? (Y/n) : " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

# Write the configuration to the wpasupplicant file while creating a backup of the old file. 
cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.old

cat <<EOF > /etc/wpa_supplicant/wpa_supplicant.conf
network={
    ssid="$ssid"
    psk="$psk"
}
EOF

#Connect to wifi
wpa_supplicant -B -i $wlan_interface -c /etc/wpa_supplicant/wpa_supplicant.conf && dhclient $wlan_interface

# Configure /etc/network/interfaces to set up vmbr0
mv /etc/network/interfaces /etc/network/interfaces.old
cat <<EOF >> /etc/network/interfaces

auto lo
iface lo inet loopback

auto $wlan_interface
iface $wlan_interface inet dhcp
         wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf

source /etc/network/interfaces.d/*

auto vmbr0
iface vmbr0 inet static
        address 192.168.50.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0

EOF

# Restart networking service to apply the configuration
systemctl restart networking
}
initial_config

# this will install dnsmasq utiliy
if ! dpkg -s dnsmasq > /dev/null 2>&1; then
    apt-get update
    apt-get install -y dnsmasq
fi

# Configure dnsmasq for DHCP on vmbr0
cat <<EOF > /etc/dnsmasq.d/vmbr0.conf
interface=vmbr0
dhcp-range=192.168.50.100,192.168.50.200,255.255.255.0,24h
EOF

systemctl restart dnsmasq

# Backup existing iptables rules
BACKUP_DIR="/etc/iptables/backup"
BACKUP_FILE="$BACKUP_DIR/rules.v4.backup_$(date +%F_%T)"
mkdir -p $BACKUP_DIR

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

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Set up iptables rules for NAT and forwarding
iptables -t nat -A POSTROUTING -o $wlan_interface -j MASQUERADE
iptables -A FORWARD -i vmbr0 -o $wlan_interface -j ACCEPT
iptables -A FORWARD -i $wlan_interface -o vmbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

# this will install iptables-persistent utiliy
if ! dpkg -s iptables-persistent > /dev/null 2>&1; then
    apt-get update
    apt-get install -y iptables-persistent
fi

# Reload iptables-persistent to apply rules
systemctl restart iptables-persistent

echo "wireless interface, vmbr0 interface, dnsmasq and iptables configured and started successfully."