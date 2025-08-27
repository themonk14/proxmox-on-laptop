# Proxmox LXC Setup Script  

This repository contains a Bash script to automate the setup of **Proxmox LXC containers** for three common security and monitoring services:  

- **SFTP Server** (for secure file transfer)  
- **Wazuh** (SIEM / security monitoring platform)  
- **Velociraptor** (endpoint visibility & digital forensics platform)  

The script handles:  
1. Checking if a Proxmox template is available (and downloading it if missing).  
2. Creating containers with predefined IDs, storage, resources, and network settings.  
3. Installing and configuring SFTP, Wazuh, and Velociraptor automatically inside their respective containers.  

---

## Requirements  
- Proxmox VE installed and running  
- Access to `pveam` and `pct` commands (root privileges)  
- Internet access for downloading templates and packages  
- A valid Proxmox storage pool (defaults: `local` for templates, `local-lvm` for rootfs)  

---

## Usage  
```bash
chmod +x setup-containers.sh
./setup-containers.sh
