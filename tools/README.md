# Proxmox Automated Deployment Tools

This folder contains a Bash script to automate the setup of Proxmox LXC containers and VMs for security, monitoring, and forensic services.

---
# Features

- **Template Management:** Checks for and downloads the required Proxmox LXC template.
- **ISO Management:** Downloads ISOs for Ubuntu, Kali, CaineOS, and (optionally) Windows.
- **Automated Container Creation:** Sets up LXC containers for:
	- SFTP Server
	- Wazuh (SIEM/Security Monitoring)
	- Velociraptor (Endpoint Forensics)
	- GRR Rapid Response (Incident Response)
    - Two sandbox lxc containers
- **Automated VM Creation:** Sets up VMs for:
	- Ubuntu
	- Kali Linux
	- Windows (searching for a reliable source for the ISO file)
	- CaineOS
- **Service Installation & Configuration:** Installs and configures SFTP, Wazuh, Velociraptor, and GRR inside their respective containers.
- Adds useful aliases and ensures net-tools is installed in all containers.
---
# Requirements

- Proxmox VE installed and running
- Root privileges (access to `pveam`, `pct`, `qm`)
- Internet access for downloading templates, ISOs, and packages
- Sufficient storage in Proxmox pools (`local` for templates/ISOs, `local-lvm` for rootfs/disks)

---
## Usage
```
cd tools ; chmod +x deploying-tools.sh
./deploying-tools.sh
```

You will be prompted for the LXC template name and SFTP username during execution.

---
# Notes
- The script will create containers and VMs with predefined IDs and network settings. Adjust the script if you need different IPs or resources.
- The Windows ISO download is commented out by default. Uncomment and provide a valid link if you wish to deploy a Windows VM.
- All containers are provisioned with a default root password (changemenow). Change passwords after deployment for security.
- The script installs and configures each service automatically, but you may need to complete additional setup steps (e.g., Wazuh dashboard access, Velociraptor configuration) as prompted.
