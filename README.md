
# Proxmox on a Laptop over WiFi

Proxmox VE Deployment with Real-Time Network Security and Incident Response Frameworks 

This project focuses on the automation of creation of virtualized network environment by using Proxmox VE. For networking the following components are set up in the script; A virtual bridge called vmbr0, DHCP server via dnsmasq: NAT and packet forwarding via iptables. This setup enables VMs in Proxmox to be in a position to communicate with each other and also access the internet.

**Prerequisites**
1. A laptop with decent configuration. 
2. Static IP reserved in the router and Internet connection. 
3. wpasupplicant and it's dependencies on a pendrive

**My experience and lessons learned :**
I have a spare laptop without an Ethernet port and display issues and I thought I could repurpose it as virtualization server by installing Proxmox in it. I know it doesn't compete with server level performance, but I thought of doing it anyway. The first problem I faced was I had to connect to my WiFi network manually. 

I had to download "wpasupplicant" and its dependencies on another machine onto a USB drive. Then I've installed them from the USB drive and configured the wpasupplicant configuration file in order to connect to the Wi-Fi network. I used the "dhclient" to get an IP address for the Wi-Fi interface.

**How does this repo help ?**
The " proxmox-setup.sh " script configures wpa_supplicant, interfaces file, installs and configures dnsmasq file, flushes existing iptable rules and creates new rules for NAT and IP forwarding. Just by running it you can save up enough time to work on something else.

**What doesn't it do yet ?**
You need to mount the USB drive and install wpa_supplicant manually. This script should only be run after successfully installing wpa_supplicant utility.

## Installation

Clone the repository using 
```bash
  git clone https://github.com/themonk14/proxmox-on-laptop.git
  cd proxmox-on-laptop
```

or download the zip file and extract it.

Run the proxmox-setup.sh file on a fresh proxmox installation. Ignore changing directory command if you're already in the cloned directory.
```bash
  cd proxmox-on-laptop
  chmod +x proxmox-setup.sh
  bash proxmox-setup.sh
```

Run the deploying-tools.sh file to automate setting up sftp server, Wazuh and velociraptor
```bash
  chmod +x deploying-tools.sh
  bash deploying-tools.sh
```
