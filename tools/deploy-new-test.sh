#!/bin/bash

#not my own creation, used GPT-5 to help me clean up and make deploy.sh better.
#haven't tested all parts of the script, use at your own risk.

#---globals---
set -euo pipefail
storage="local"
dir="vztmpl"
iso_dir="/var/lib/vz/template/iso"
ct_dir="/var/lib/vz/template/cache"
declare -A iso_urls=(
  ["ubuntu-22.04.iso"]="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-desktop-amd64.iso"
  ["ubuntu-24.04.iso"]="https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-desktop-amd64.iso"
  ["kali-latest.iso"]="https://cdimage.kali.org/kali-2025.2/kali-linux-2025.2-installer-amd64.iso"
  ["caine.iso"]="https://www.caine-live.net/Downloads/caine14.0.iso"
  ["kali-purple.iso"]="https://cdimage.kali.org/kali-2025.2/kali-linux-2025.2-installer-purple-amd64.iso"
)
declare -A ct_urls=(
  ["kali_amd64.tar.xz"]="https://images.linuxcontainers.org/images/kali/current/amd64/default/20250902_17%3A14/rootfs.tar.xz"
)
template_name=""
debian_template_name=""

#---help---
usage() {
cat <<EOF
Usage: $0 [OPTIONS]

Bootstrap:
  --templates                 Run LXC template selection/download flow
  --debian-template           Pick or download a Debian template for sandbox containers
  --isos                      Download ISOs (Ubuntu/Kali/Caine/Kali-Purple)
  --ct-images                 Download CT rootfs images (e.g., Kali)

Create LXC containers:
  --create-sftp               Create SFTP container (CT 101)
  --create-wazuh              Create Wazuh container (CT 102)
  --create-velociraptor       Create Velociraptor container (CT 103)
  --create-grr                Create GRR container (CT 104)
  --create-localstack         Create Localstack container (CT 105)
  --create-deepfence          Create Deepfence container (CT 106)
  --create-kali               Create Kali container (CT 107) if template exists
  --create-sbx-ubu1           Create Sandbox Ubuntu 1 (CT 200)
  --create-sbx-ubu2           Create Sandbox Ubuntu 2 (CT 201)
  --create-sbx-deb1           Create Sandbox Debian 1 (CT 202)
  --create-sbx-deb2           Create Sandbox Debian 2 (CT 203)
  --create-lxcs               Create all LXC containers above

Post-setup for LXC:
  --setup-sftp                Configure SFTP on CT 101
  --setup-wazuh               Install Wazuh on CT 102
  --setup-velociraptor        Install Velociraptor on CT 103
  --setup-grr                 Install GRR on CT 104
  --setup-localstack          Minimal prep on CT 105
  --setup-all                 Run all post-setup steps for created containers

Create VMs:
  --create-vm-ubuntu          Create Ubuntu VM (VM 300, boots from ubuntu-22.04.iso)
  --create-vm-kali            Create Kali VM (VM 301)
  --create-vm-windows         Create Windows VM shell (VM 302)
  --create-vm-caine           Create CaineOS VM (VM 303)
  --create-vms                Create all VMs above

Shortcuts:
  --all                       Run templates, debian template, ISOs, CT images, create all LXCs, setup all, create all VMs

Other:
  -h, --help                  Show this help

Notes:
- Some steps are interactive by design (e.g., template selection, password prompts for GRR). They will only run if the step you chose requires them.
EOF
}

#---ensure-helpers---
ensure_templates_selected() {
  if [[ -z "$template_name" ]]; then lxc_templates; fi
  if [[ -z "$debian_template_name" ]]; then pick_debian_template; fi
}
ensure_isos() { download_isos; }
ensure_ct_images() { download_ct_images; }

#---lxc-templates---
lxc_templates() {
  pveam update
  pveam available > /tmp/templates.txt
  awk '{print NR ") " $0}' /tmp/templates.txt | less
  read -p "Enter the number of the template you'd like to download: " template_num
  template_name=$(awk -v num="$template_num" 'NR==num {print $2}' /tmp/templates.txt)
  if [ -z "$template_name" ]; then echo "Invalid selection."; exit 1; fi
  if pveam list $storage | grep -i "$storage:$dir/$template_name" >/dev/null; then
    echo "Template $template_name already installed"
  else
    echo "Template not found locally. Downloading..."
    pveam download $storage "$template_name" || { echo "Download failed."; exit 1; }
  fi
  echo "Would you like to download additional LXC templates? (Y/N)"
  read -r download_more
  if [[ "$download_more" =~ ^[Yy]$ ]]; then
    pveam update >/dev/null 2>&1
    pveam available > /tmp/templates.txt
    awk '{print NR ") " $0}' /tmp/templates.txt | less
    mapfile -t templates < <(awk '{print $2}' /tmp/templates.txt | grep -v '^$')
    if [ ${#templates[@]} -gt 0 ]; then
      echo "Enter the numbers to download (comma separated, e.g. 1,3,5):"
      read -r selected
      IFS=',' read -ra idxs <<< "$selected"
      for idx in "${idxs[@]}"; do
        idx_trim=$(echo "$idx" | xargs)
        if [[ "$idx_trim" =~ ^[0-9]+$ ]] && [ "$idx_trim" -ge 1 ] && [ "$idx_trim" -le ${#templates[@]} ]; then
          tname="${templates[$((idx_trim-1))]}"
          echo "Downloading $tname ..."
          pveam download local "$tname" || echo "Failed to download $tname."
        else
          echo "Invalid selection: $idx_trim"
        fi
      done
    fi
  fi
}

#---pick-debian-template---
pick_debian_template() {
  clear
  echo "Available debian templates for sandbox containers:"
  debian_templates=( $(pveam list $storage | grep -i "$storage:$dir/debian" | awk '{print $1}') )
  if [ ${#debian_templates[@]} -eq 0 ]; then
    echo "No debian templates found locally. Listing available debian templates to download:"
    mapfile -t available_debian_templates < <(pveam available | grep -i debian | awk '{print $2 ? $1 : ""}')
    if [ ${#available_debian_templates[@]} -eq 0 ]; then echo "No debian templates available."; exit 1; fi
    for i in "${!available_debian_templates[@]}"; do printf "%2d) %s\n" $((i+1)) "${available_debian_templates[$i]}"; done
    read -p "Enter the number of the debian template to download: " debian_download_num
    debian_download_name="${available_debian_templates[$((debian_download_num-1))]}"
    if [ -z "$debian_download_name" ]; then echo "Invalid selection."; exit 1; fi
    echo "Downloading $debian_download_name ..."
    pveam download $storage "$debian_download_name" || { echo "Failed to download."; exit 1; }
    debian_templates=( $(pveam list $storage | grep -i "$storage:$dir/debian" | awk '{print $1}') )
  fi
  for i in "${!debian_templates[@]}"; do printf "%2d) %s\n" $((i+1)) "${debian_templates[$i]}"; done
  read -p "Enter the number of the debian template for sandbox containers: " debian_template_num
  debian_template_name="${debian_templates[$((debian_template_num-1))]}"
  if [ -z "$debian_template_name" ]; then echo "Invalid selection."; exit 1; fi
}

#---download-isos---
download_isos() {
  mkdir -p "$iso_dir"
  for iso in "${!iso_urls[@]}"; do
    if [ -f "$iso_dir/$iso" ]; then
      echo "$iso already exists."
    else
      echo "Downloading $iso..."
      attempt=1
      while [ $attempt -le 3 ]; do
        if wget -O "$iso_dir/$iso" "${iso_urls[$iso]}"; then break; fi
        if grep -q "Name or service not known" <<< "$(tail -n 10 /var/log/syslog 2>/dev/null || true)"; then
          need_dns_update=false
          grep -q "nameserver 8.8.8.8" /etc/resolv.conf || need_dns_update=true
          grep -q "nameserver 8.8.4.4" /etc/resolv.conf || need_dns_update=true
          if $need_dns_update; then
            echo "Adding Google DNS to /etc/resolv.conf..."
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
            echo "nameserver 8.8.4.4" >> /etc/resolv.conf
          fi
        else
          echo "Failed attempt $attempt for $iso. Retrying..."
        fi
        attempt=$((attempt+1))
        sleep 2
      done
      if [ $attempt -gt 3 ]; then echo "Failed to download $iso after 3 attempts."; fi
    fi
  done
}

#---download-ct-images---
download_ct_images() {
  mkdir -p "$ct_dir"
  for ct in "${!ct_urls[@]}"; do
    if [ -f "$ct_dir/$ct" ]; then
      echo "$ct already exists."
    else
      echo "Downloading $ct..."
      wget -O "$ct_dir/$ct" "${ct_urls[$ct]}" || echo "Failed to download $ct."
    fi
  done
}

#---create-sftp---
create_sftp() {
  ensure_templates_selected
  clear && echo "Creating SFTP container...."
  pct create 101 local:vztmpl/$template_name --tags "general, ftp-server, filetransfer" --hostname SFTP-Server-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 32 --memory 2048 --swap 1024 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.100/24,gw=192.168.50.1 --cores=1 --password changemenow --description "root:changemenow"
}

#---create-wazuh---
create_wazuh() {
  ensure_templates_selected
  clear && echo "Creating Wazuh container...."
  pct create 102 local:vztmpl/$template_name --tags "Blue" --hostname Wazuh-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 40 --memory 4096 --swap 4096 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.105/24,gw=192.168.50.1 --cores=4 --password changemenow --description "root:changemenow"
}

#---create-velociraptor---
create_velociraptor() {
  ensure_templates_selected
  clear && echo "Creating Velociraptor container...."
  pct create 103 local:vztmpl/$template_name --tags "Blue" --hostname Velociraptor-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 30 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.110/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"
}

#---create-grr---
create_grr() {
  ensure_templates_selected
  clear && echo "Creating GRR-Rapid-Response container...."
  pct create 104 local:vztmpl/$template_name --tags "Blue" --hostname GRR-Rapid-Response-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 30 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.115/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"
}

#---create-localstack---
create_localstack() {
  ensure_templates_selected
  clear && echo "Creating localstack container...."
  pct create 105 local:vztmpl/$template_name --tags "cloud" --hostname localstack-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 30 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.120/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"
}

#---create-deepfence---
create_deepfence() {
  ensure_templates_selected
  clear && echo "Creating deepfence container...."
  pct create 106 local:vztmpl/$template_name --tags "cloud" --hostname deepfence-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 30 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.121/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow.  https://github.com/deepfence/ThreatMapper."
}

#---create-kali---
create_kali() {
  clear && echo "Creating Kali container...."
  if pveam list $storage | grep -i "$storage:$dir/kali_amd64" >/dev/null; then
    pct create 107 local:vztmpl/kali_amd64.tar.xz --tags "Red" --hostname Kali --nameserver "8.8.8.8" --storage local-lvm --rootfs 32 --memory 4096 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.125/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"
    pct start 107
    pct exec 107 -- bash -c "rm -rf /etc/resolv.conf && touch /etc/resolv.conf && echo 'nameserver 8.8.8.8' >> /etc/resolv.conf && echo 'nameserver 8.8.4.4' >> /etc/resolv.conf"
    pct exec 107 -- bash -c "mkdir -p /root/old-apt-sources && mv /etc/apt/sources.list /root/old-apt-sources/ && tee /etc/apt/sources.list <<EOF
deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
deb-src http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
deb https://deb.kali.org/kali kali-rolling main contrib non-free non-free-firmware
EOF"
    pct exec 107 -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"
    pct stop 107
  else
    echo "Kali template not found locally."
  fi
}

#---create-sbx-ubu1---
create_sbx_ubu1() {
  ensure_templates_selected
  pct create 200 local:vztmpl/$template_name --tags "Sandbox" --hostname Sandbox-Ubu-1 --nameserver "8.8.8.8" --storage local-lvm --rootfs 20 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.200/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"
  pct start 200
  pct exec 200 -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"
  pct stop 200
}

#---create-sbx-ubu2---
create_sbx_ubu2() {
  ensure_templates_selected
  pct create 201 local:vztmpl/$template_name --tags "Sandbox" --hostname Sandbox-Ubu-2 --nameserver "8.8.8.8" --storage local-lvm --rootfs 20 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.201/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"
  pct start 201
  pct exec 201 -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"
  pct stop 201
}

#---create-sbx-deb1---
create_sbx_deb1() {
  ensure_templates_selected
  pct create 202 $debian_template_name --tags "Sandbox-1" --hostname Sandbox-Deb-1 --nameserver "8.8.8.8" --storage local-lvm --rootfs 20 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.202/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"
  pct start 202
  pct exec 202 -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"
  pct stop 202
}

#---create-sbx-deb2---
create_sbx_deb2() {
  ensure_templates_selected
  pct create 203 $debian_template_name --tags "Sandbox-1" --hostname Sandbox-Deb-2 --nameserver "8.8.8.8" --storage local-lvm --rootfs 20 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.203/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"
  pct start 203
  pct exec 203 -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"
  pct stop 203
}

#---create-lxcs---
create_lxcs() {
  create_sftp
  create_wazuh
  create_velociraptor
  create_grr
  create_localstack
  create_deepfence
  create_kali
  create_sbx_ubu1
  create_sbx_ubu2
  create_sbx_deb1
  create_sbx_deb2
}

#---create-vm-ubuntu---
create_vm_ubuntu() {
  ensure_isos
  clear && echo "Creating Ubuntu VM...."
  qm create 300 --name ubuntu-vm --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 local-lvm:50 --ide2 local:iso/ubuntu-22.04.iso,media=cdrom --boot order=ide2 --ostype l26
}

#---create-vm-kali---
create_vm_kali() {
  ensure_isos
  qm create 301 --name kali-vm --memory 8192 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 local-lvm:70 --ide2 local:iso/kali-latest.iso,media=cdrom --boot order=ide2 --ostype l26
}

#---create-vm-windows---
create_vm_windows() {
  qm create 302 --name windows-vm --memory 8192 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 local-lvm:80 --boot order=scsi0 --ostype win10
}

#---create-vm-caine---
create_vm_caine() {
  ensure_isos
  qm create 303 --name CaineOS --memory 8192 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 local-lvm:10 --ide2 local:iso/caine.iso,media=cdrom --boot order=ide2 --ostype l26
}

#---create-vms---
create_vms() {
  create_vm_ubuntu
  create_vm_kali
  create_vm_windows
  create_vm_caine
}

#---setup-sftp---
setup_sftp() {
  clear
  echo "Setting up SFTP server in container 101."
  while true; do
    read -p "Enter sftp username : " usname
    if [ -n "$usname" ]; then break; else echo "Username cannot be empty."; fi
  done
  pct start 101 && pct exec 101 -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 && mkdir -p /ftpdir && chmod 701 /ftpdir && groupadd sftp_users && useradd -g sftp_users -d /upload -s /sbin/nologin $usname && echo 'Enter password for the new user' && passwd $usname && mkdir -p /ftpdir/$usname/upload && chown -R root:sftp_users /ftpdir/$usname && chown -R $usname:sftp_users /ftpdir/$usname/upload && echo -e '\nMatch Group sftp_users\nChrootDirectory /ftpdir/%u\nForceCommand internal-sftp' >> /etc/ssh/sshd_config && systemctl restart sshd"
  pct exec 101 -- bash -c "dpkg -s net-tools >/dev/null 2>&1 || apt install net-tools -y; cat <<'EOF' >> ~/.bashrc
alias upd=\"apt update -y\"
alias upg=\"apt upgrade -y\"
alias cx=\"clear\"
alias nstatus=\"/usr/bin/watch -n 1 /usr/bin/netstat -alntup\"
alias instl=\"apt install -y\"
alias serve=\"ip a && python3 -m http.server 9090\"
EOF"
  pct stop 101
  clear
  echo "SFTP server setup is complete."
}

#---setup-wazuh---
setup_wazuh() {
  pct start 102 && pct exec 102 -- bash -c "apt-get update && apt-get install -y locales curl wget git && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 && curl -sO https://packages.wazuh.com/4.12/wazuh-install.sh && bash ./wazuh-install.sh -a && echo 'You can access Wazuh dashboard at https://192.168.50.105/'"
  pct exec 102 -- bash -c "dpkg -s net-tools >/dev/null 2>&1 || apt install net-tools -y; cat <<'EOF' >> ~/.bashrc
alias upd=\"apt update -y\"
alias upg=\"apt upgrade -y\"
alias cx=\"clear\"
alias nstatus=\"/usr/bin/watch -n 1 /usr/bin/netstat -alntup\"
alias instl=\"apt install -y\"
alias serve=\"ip a && python3 -m http.server 9090\"
EOF"
  pct stop 102
  clear
  echo "Wazuh setup is complete."
}

#---setup-velociraptor---
setup_velociraptor() {
  pct start 103
  pct exec 103 -- bash -c 'apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 && [ ! -f /etc/velociraptor.config.yaml ] && touch /etc/velociraptor.config.yaml'
  pct exec 103 -- bash -c "dpkg -s net-tools >/dev/null 2>&1 || apt-get install -y net-tools; cat <<'EOF' >> ~/.bashrc
alias upd=\"apt-get update -y\"
alias upg=\"apt-get upgrade -y\"
alias cx=\"clear\"
alias nstatus=\"/usr/bin/watch -n 1 /usr/bin/netstat -alntup\"
alias instl=\"apt-get install -y\"
alias serve=\"ip a && python3 -m http.server 9090\"
EOF"
  pct exec 103 -- bash -lc '
cat <<'"'"'EOF'"'"' > /tmp/install_velociraptor.sh
#!/bin/bash
set -e
wget -O /usr/local/bin/velociraptor https://github.com/Velocidex/velociraptor/releases/download/v0.72/velociraptor-v0.72.4-linux-amd64
chmod +x /usr/local/bin/velociraptor
/usr/local/bin/velociraptor config generate -i
if [ -f /etc/velociraptor.config.yaml ]; then
  sed -i "s/bind_address: 127.0.0.1/bind_address: 192.168.50.110/" /etc/velociraptor.config.yaml || true
fi
cat <<'"'"'EOL'"'"' > /lib/systemd/system/velociraptor.service
[Unit]
Description=Velociraptor
After=syslog.target network.target
[Service]
Type=simple
Restart=always
RestartSec=120
LimitNOFILE=20000
Environment=LANG=en_US.UTF-8
ExecStart=/usr/local/bin/velociraptor --config /etc/velociraptor.config.yaml frontend -v
[Install]
WantedBy=multi-user.target
EOL
systemctl daemon-reload
systemctl enable --now velociraptor
echo "https://192.168.50.110:8889/app/index.html"
EOF
chmod +x /tmp/install_velociraptor.sh
bash /tmp/install_velociraptor.sh
'
  pct stop 103
}

#---setup-grr---
setup_grr() {
  pct start 104
  pct exec 104 -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 && apt install mariadb-server -y && wget https://storage.googleapis.com/releases.grr-response.com/grr-server_3.4.7-1_amd64.deb"
  pct exec 104 -- bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y expect
    expect << "EOF"
    log_user 1
    spawn mysql_secure_installation
    set timeout 120
    expect -re {Enter current password for root.*:}
    send "\r"
    expect {
        -re {Switch to unix_socket authentication.*\[Y/n\]} { send "n\r"; exp_continue }
        -re {Set root password\?.*\[Y/n\]} { send "n\r"; exp_continue }
        -re {Change the root password\?.*\[Y/n\]} { send "n\r"; exp_continue }
        -re {Remove anonymous users\?.*\[Y/n\]} {send "Y\r"; exp_continue }
        -re {Disallow root login remotely\?.*\[Y/n\]} {send "Y\r"; exp_continue }
        -re {Remove test database.*\[Y/n\]} {send "Y\r"; exp_continue }
        -re {Reload privilege tables now\?.*\[Y/n\]} {send "Y\r"; exp_continue }
    }
EOF
'
  pct exec 104 -- bash -c "apt install /grr-ser* || apt --fix-broken install -y && apt install /grr-ser* -y"
  pct exec 104 -- bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
read -s -p "MySQL ROOT password (leave empty if using unix_socket): " MYSQL_ROOT_PASS; echo
read -s -p "GRR admin password: " ADMIN_PASS; echo
apt-get update -y && apt-get install -y --no-install-recommends expect
expect <<EOF
log_user 1
set timeout 1800
set mysql_root_pass "$MYSQL_ROOT_PASS"
set admin_pass "$ADMIN_PASS"
spawn grr_config_updater initialize
expect {
    -re {Use Fleetspeak.*\[Yn\]:} { send "Y\r"; exp_continue }
    -re {Please enter your hostname.*:} { send "\r"; exp_continue }
    -re {Fleetspeak public HTTPS port.*:} { send "\r"; exp_continue }
    -re {Fleetspeak MySQL Host.*:} { send "localhost\r"; exp_continue }
    -re {Fleetspeak MySQL Port.*:} { send "3306\r"; exp_continue }
    -re {Fleetspeak MySQL Database.*:} { send "\r"; exp_continue }
    -re {Fleetspeak MySQL Username.*:} { send "\r"; exp_continue }
    -re {Please enter password for database user .*:} {
        if { \$mysql_root_pass eq "" } { send "\r" } else { send "\$mysql_root_pass\r" }
        exp_continue
    }
    -re {MySQL Host.*:} { send "localhost\r"; exp_continue }
    -re {MySQL Port .* \[0\]:} { send "0\r"; exp_continue }
    -re {MySQL Database.*:} { send "\r"; exp_continue }
    -re {MySQL Username.*:} { send "\r"; exp_continue }
    -re {Please enter password for database user .*:} {
        if { \$mysql_root_pass eq "" } { send "\r" } else { send "\$mysql_root_pass\r" }
        exp_continue
    }
    -re {Configure SSL connections for MySQL\?.*\[yN\]:} { send "N\r"; exp_continue }
    -re {Frontend URL \[http://.*:8080/\]:} { send "\r"; exp_continue }
    -re {AdminUI URL \[http://.*:8000\]:} { send "\r"; exp_continue }
    -re {Email Domain.*:} { send "\r"; exp_continue }
    -re {Alert Email Address.*:} { send "\r"; exp_continue }
    -re {Emergency Access Email Address.*:} { send "\r"; exp_continue }
    -re {Please enter password for user .admin.:} { send "\$admin_pass\r"; exp_continue }
    -re {Please re-enter password for user .admin.:} { send "\$admin_pass\r"; exp_continue }
    -re {Re-?download templates\?.*\[yN\]:} { send "N\r"; exp_continue }
    -re {Repack client templates\?.*\[Yn\]:} { send "Y\r"; exp_continue }
    -re {Restart service.*\?.*\[Yn\]:} { send "Y\r"; exp_continue }
    eof { }
}
EOF
systemctl --no-pager --full status grr-server fleetspeak-server || true
unset MYSQL_ROOT_PASS ADMIN_PASS
'
  pct exec 104 -- bash -c "dpkg -s net-tools >/dev/null 2>&1 || apt install net-tools -y; cat <<'EOF' >> ~/.bashrc
alias upd=\"apt update -y\"
alias upg=\"apt upgrade -y\"
alias cx=\"clear\"
alias nstatus=\"/usr/bin/watch -n 1 /usr/bin/netstat -alntup\"
alias instl=\"apt install -y\"
alias serve=\"ip a && python3 -m http.server 9090\"
EOF"
  pct stop 104
}

#---setup-localstack---
setup_localstack() {
  pct start 105 || { echo "Failed to start container 105."; exit 1; }
  pct exec 105 -- bash -c "apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 && dpkg -s net-tools >/dev/null 2>&1 || apt install net-tools -y; cat <<'EOF' >> ~/.bashrc
alias upd=\"apt update -y\"
alias upg=\"apt upgrade -y\"
alias cx=\"clear\"
alias nstatus=\"/usr/bin/watch -n 1 /usr/bin/netstat -alntup\"
alias instl=\"apt install -y\"
alias serve=\"ip a && python3 -m http.server 9090\"
EOF"
  pct stop 105
}

#---setup-all---
setup_all() {
  setup_sftp
  setup_wazuh
  setup_velociraptor
  setup_grr
  setup_localstack
}

#---dispatch---
if [[ $# -eq 0 ]]; then usage; exit 0; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --templates) lxc_templates;;
    --debian-template) pick_debian_template;;
    --isos) download_isos;;
    --ct-images) download_ct_images;;

    --create-sftp) create_sftp;;
    --create-wazuh) create_wazuh;;
    --create-velociraptor) create_velociraptor;;
    --create-grr) create_grr;;
    --create-localstack) create_localstack;;
    --create-deepfence) create_deepfence;;
    --create-kali) create_kali;;
    --create-sbx-ubu1) create_sbx_ubu1;;
    --create-sbx-ubu2) create_sbx_ubu2;;
    --create-sbx-deb1) create_sbx_deb1;;
    --create-sbx-deb2) create_sbx_deb2;;
    --create-lxcs) create_lxcs;;

    --setup-sftp) setup_sftp;;
    --setup-wazuh) setup_wazuh;;
    --setup-velociraptor) setup_velociraptor;;
    --setup-grr) setup_grr;;
    --setup-localstack) setup_localstack;;
    --setup-all) setup_all;;

    --create-vm-ubuntu) create_vm_ubuntu;;
    --create-vm-kali) create_vm_kali;;
    --create-vm-windows) create_vm_windows;;
    --create-vm-caine) create_vm_caine;;
    --create-vms) create_vms;;

    --all)
      lxc_templates
      pick_debian_template
      download_isos
      download_ct_images
      create_lxcs
      setup_all
      create_vms
      ;;
    *)
      echo "Unknown option: $1"; usage; exit 1;;
  esac
  shift
done
