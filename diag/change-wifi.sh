#!/bin/bash

#install iw package if not installed
if ! dpkg -s iw > /dev/null 2>&1; then
    apt-get update
    apt-get install -y iw wireless-tools
fi

# Detect the wireless interface
wlan_interface=$(iw dev | awk '$1=="Interface"{print $2}' | head -n1)
if [ -z "$wlan_interface" ]; then
    echo "No wireless interface found."
    exit 1
fi

# Scan for available WiFi networks
clear
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

# Backup and write wpa_supplicant config
sudo cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.bak 2>/dev/null
sudo bash -c "cat > /etc/wpa_supplicant/wpa_supplicant.conf" <<EOF
network={
    ssid="$ssid"
    psk="$psk"
}
EOF

# Kill any running wpa_supplicant and connect
sudo pkill wpa_supplicant
sudo wpa_supplicant -B -i "$wlan_interface" -c /etc/wpa_supplicant/wpa_supplicant.conf

# Wait for IP assignment (up to 60 seconds)
echo "Waiting for IP address on $wlan_interface..."
for i in {1..60}; do
    ip_addr=$(ip -4 addr show "$wlan_interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$ip_addr" ]; then
        break
    fi
    sleep 1
done

if [ -z "$ip_addr" ]; then
    echo "No IP assigned after 60 seconds. Requesting IP with dhclient..."
    sudo dhclient "$wlan_interface"
    sleep 3
    ip_addr=$(ip -4 addr show "$wlan_interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
fi

if [ -n "$ip_addr" ]; then
    echo "Connected! IP address assigned to $wlan_interface: $ip_addr"
else
    echo "Failed to obtain an IP address."
fi

echo "If the IP is not assigned automatically after reboot, run: sudo dhclient $wlan_interface"