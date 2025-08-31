#!/bin/bash

#Run this script only after installing wpasupplicant and its dependencies in proxmox

# Detect if running as root, set SUDO variable accordingly
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Ensure required tools are installed
if ! command -v apt-rdepends &>/dev/null; then
    echo "Installing apt-rdepends..."
    $SUDO apt-get update
    $SUDO apt-get install -y apt-rdepends net-tools upower wireless-tools vlock isc-dhcp-client
fi

# Fix any missing dependencies
$SUDO apt-get install -f -y && $SUDO apt-get install -y wpasupplicant

echo "wpasupplicant and its dependencies have been installed."

# Detect wireless interface, bring it up if down
wlan_interface=$(ip link show | awk -F: '$2 ~ /w/ {print $2}' | tr -d ' ' | head -n1)
if [ -n "$wlan_interface" ]; then
    ip link show "$wlan_interface" | grep -q 'state UP' || $SUDO ip link set "$wlan_interface" up
else
    echo "No wireless interface found. Exiting."
    exit 1
fi

initial_config() {
echo "Using wireless interface: $wlan_interface"
echo "Scanning for available WiFi networks..."
mapfile -t ssids < <(iwlist "$wlan_interface" scan | grep 'ESSID:' | sed 's/.*ESSID:"\(.*\)"/\1/' | sort | uniq | grep -v '^$')

if [ ${#ssids[@]} -eq 0 ]; then
    echo "No WiFi networks found."
    exit 1
fi

echo "Available WiFi networks:"
for i in "${!ssids[@]}"; do
    printf "%2d) %s\n" $((i+1)) "${ssids[$i]}"
done

# Ask user to select a network
read -p "Enter the number of the WiFi network to connect to: " choice
ssid="${ssids[$((choice-1))]}"
if [ -z "$ssid" ]; then
    echo "Invalid selection."
    exit 1
fi

# Ask for password (input hidden)
read -rsp "Enter password for '$ssid': " psk
echo

# Confirm connection
read -p "Connect to '$ssid'? (Y/n): " confirm
if [[ ! "$confirm" =~ ^([yY][eE][sS]?|[yY])$ ]]; then
    echo "Aborted."
    exit 1
fi

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

# Set up an isolated vmbr1 interface
read -p "Would you like to set up a completely isolated interface (vmbr1) ? (y/N): " setup_vmbr1

# Only after confirmation isolated vmbr1 is added to interfaces
if [[ $setup_vmbr1 =~ ^[yY](es)?$ ]]; then
    cat <<EOF >> /etc/network/interfaces
auto vmbr1
iface vmbr1 inet static
        address 10.10.10.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0
EOF
    # Drop forwarding from vmbr1 to any other interface
    iptables -A FORWARD -i vmbr1 ! -o vmbr1 -j DROP
    # Drop forwarding from any interface to vmbr1 (optional, for full isolation)
    iptables -A FORWARD ! -i vmbr1 -o vmbr1 -j DROP
    # Allow forwarding within vmbr1
    iptables -A FORWARD -i vmbr1 -o vmbr1 -j ACCEPT
    echo "Isolated vmbr1 interface configured. Only VMs/Containers attached to vmbr1 can communicate with each other."
fi

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

# Add useful aliases to .bashrc
read -p "Would you like to add aliases ? (y/N): " aliases_setup

# Only after confirmation aliases are added to .bashrc
if [[ $aliases_setup =~ ^[yY](es)?$ ]]; then
    echo -e 'alias upd="apt update -y"\nalias upg="apt upgrade -y"\nalias cx="clear"\nalias nstatus="/usr/bin/watch -n 1 /usr/bin/netstat -alntup"\nalias instl="apt install -y"\nalias serve="ip a && python3 -m http.server 9090"\nalias chargestatus="upower -i $(upower -e | grep 'BAT') | grep -E "state|to\ full|percentage"\nalias lock="ip link set wlp45s0 down && vlock"' >> ~/.bashrc || { echo "Failed to set aliases in proxmox node. Exiting."; exit 1; }
fi

# copy scripts in diag folder to /usr/local/bin
read -p "Would you like to copy scripts in diag folder to /usr/local/bin ? (y/N): " scr_copy

# Only after confirmation the scripts are copied
if [[ $scr_copy =~ ^[yY](es)?$ ]]; then
    $SUDO chmod 711 diag/*
    $SUDO cp diag/* /usr/local/bin/
fi

read -p "Would you like to setuo cronjobs ? " cronchk
# Add cronjobs for networking and AIDE
if [[ $cronchk =~ ^[yY](es)?$ ]]; then
cat <<'EOF' | crontab -
@reboot sleep 60 && systemctl restart networking && sleep 30 && dhclient wlp45s0
0 */23 * * * sleep 60 && systemctl restart networking && sleep 30 && dhclient wlp45s0
EOF
fi

# Execute deploy.sh to create VMs and containers
read -p "Would you like to create VMs, LXC containers and deploy tools ? (y/N): " scr_exec_conf

# Only after confirmation, deploy.sh is executed
if [[ $scr_exec_conf =~ ^[yY](es)?$ ]]; then
    $SUDO chmod +x tools/deploy.sh
    $SUDO bash tools/deploy.sh
fi