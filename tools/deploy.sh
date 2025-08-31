#!/bin/bash
# Script to automate the deployment of various tools and VMs on Proxmox

#--------------------------------LXC TEMPLATE DOWNLOAD--------------------------------
pveam update && pveam available
read -p "Enter the template which you'd like to download" template_name
storage="local"
dir="vztmpl"
if pveam list $storage | grep -i $storage:$dir/$template_name; then
    echo "Template $template_name already installed"
else
    echo "Template not found. Downloading it now....................."
    if ! pveam download $storage $template_name; then
        echo "Failed to download the template. Exiting."
        exit 1
    fi
fi

# Optional: Download additional templates ----- If you want to skip this part, just press 'N' when prompted.
echo "Would you like to download additional LXC templates? (Y/N)"
read -r download_more
if [[ "$download_more" =~ ^[Yy]$ ]]; then
    echo "Fetching available templates..."
    pveam update > /dev/null 2>&1
    mapfile -t templates < <(pveam available | awk '{print $2}' | grep -v '^$')
    if [ ${#templates[@]} -eq 0 ]; then
        echo "No templates found."
    else
        echo "Available templates:"
        for i in "${!templates[@]}"; do
            printf "%3d) %s\n" $((i+1)) "${templates[$i]}"
        done
        echo "Enter the numbers of the templates you want to download (comma separated, e.g. 1,3,5):"
        read -r selected
        IFS=',' read -ra idxs <<< "$selected"
        for idx in "${idxs[@]}"; do
            idx_trim=$(echo "$idx" | xargs)
            if [[ "$idx_trim" =~ ^[0-9]+$ ]] && [ "$idx_trim" -ge 1 ] && [ "$idx_trim" -le ${#templates[@]} ]; then
                tname="${templates[$((idx_trim-1))]}"
                echo "Downloading $tname ..."
                if ! pveam download local "$tname"; then
                    echo "Failed to download $tname."
                fi
            else
                echo "Invalid selection: $idx_trim"
            fi
        done
    fi
fi

echo 'Available debian templates for sandbox containers : \n'
pveam list $storage | grep -i $storage:$dir/debian
read -p "Enter the debian template name for the debian sandbox containers : " debian_template_name

#--------------------------------ISO DOWNLOAD--------------------------------
## Download ISO files
iso_dir="/var/lib/vz/template/iso"
declare -A iso_urls=(
    ["ubuntu-22.04.iso"]="https://releases.ubuntu.com/22.04/ubuntu-22.04-desktop-amd64.iso"
    ["ubuntu-24.04.iso"]="https://releases.ubuntu.com/22.04/ubuntu-22.04-desktop-amd64.iso"
    ["kali-latest.iso"]="https://cdimage.kali.org/kali-2025.2/kali-linux-2025.2-installer-amd64.iso"
    #["windows.iso"]="https://software-download.microsoft.com/db/Win11_22H2_English_x64.iso"
    ["caine.iso"]="https://www.caine-live.net/Downloads/caine14.0.iso"
    ["kali-purple.iso"]="https://cdimage.kali.org/kali-2025.2/kali-linux-2025.2-installer-purple-amd64.iso"
    #["sift.iso"]=""
)
for iso in "${!iso_urls[@]}"; do
    if [ -f "$iso_dir/$iso" ]; then
        echo "$iso already exists."
    else
        echo "Downloading $iso..."
        if ! wget -O "$iso_dir/$iso" "${iso_urls[$iso]}"; then
            echo "Failed to download $iso. Exiting."
        fi
    fi
done

ct_dir="/var/lib/vz/template/cache"
declare -A ct_urls=(
    ["kali_amd64.tar.gz"]="https://images.linuxcontainers.org/images/kali/current/amd64/default/20250830_17:14/rootfs.tar.xz"
    #["add-more.tar.gz"]="replace-with-valid-url"
)

for ct in "${!ct_urls[@]}"; do
    if [ -f "$ct_dir/$ct" ]; then
        echo "$ct already exists."
    else
        echo "Downloading $ct..."
        if ! wget -O "$ct_dir/$ct" "${ct_urls[$ct]}"; then
            echo "Failed to download $ct. Exiting."
        fi
    fi
done

#--------------------------------CONTAINER CREATION--------------------------------
#Create containers for SFTP, Velociraptor, Wazuh

if ! pct create 101 local:vztmpl/$template_name --tags "general, ftp-server, filetransfer" --hostname SFTP-Server-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 32 --memory 2048 --swap 1024 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.100/24,gw=192.168.50.1 --cores=1 --password changemenow --description "root:changemenow"; then
    echo "Failed to create container for SFTP with CT-ID:101. Exiting Now....................."
    exit 1
fi

if ! pct create 102 local:vztmpl/$template_name --tags "Blue" --hostname Wazuh-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 40 --memory 4096 --swap 4096 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.105/24,gw=192.168.50.1 --cores=4 --password changemenow --description "root:changemenow"; then
    echo "Failed to create container for Wazuh with CT-ID:102. Exiting Now....................."
    exit 1
fi

if ! pct create 103 local:vztmpl/$template_name --tags "Blue" --hostname Velociraptor-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 30 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.110/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"; then
    echo "Failed to create container for Velociraptor with CT-ID:103. Exiting Now....................."
    exit 1
fi

if ! pct create 104 local:vztmpl/$template_name --tags "Blue" --hostname GRR-Rapid-Response-Ubu --nameserver "8.8.8.8" --storage local-lvm --rootfs 30 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.115/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"; then
    echo "Failed to create container for GRR-Rapid with CT-ID:104. Exiting Now....................."
    exit 1
fi

#create kali container if the template is downloaded
if pveam list $storage | grep -i $storage:$dir/kali-rolling; then
    echo "Kali template found. Creating kali container now....................."
    if ! pct create 105 local:vztmpl/kali-rolling --tags "Red" --hostname Kali  --nameserver "8.8.8.8" --storage local-lvm --rootfs 32 --memory 4096 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.120/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"; then
        echo "Failed to create container for Kali with CT-ID:105. Exiting Now....................."
        exit 1
    fi 
fi

#Create sandbox containers for Ubuntu and Debian

if ! pct create 200 local:vztmpl/$template_name --tags "Sandbox" --hostname Sandbox-Ubu-1 --nameserver "8.8.8.8" --storage local-lvm --rootfs 20 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.200/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"; then
    echo "Failed to create container for Sandbox-Ubu-1 with CT-ID:200. Exiting Now....................."
    exit 1
fi

if ! pct create 201 local:vztmpl/$template_name --tags "Sandbox" --hostname Sandbox-Ubu-2 --nameserver "8.8.8.8" --storage local-lvm --rootfs 20 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.201/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"; then
    echo "Failed to create container for Sandbox-Ubu-2 with CT-ID:201. Exiting Now....................."
    exit 1
fi

if ! pct create 202 local:vztmpl/$debian_template_name --tags "Sandbox-1" --hostname Sandbox-Deb-1 --nameserver "8.8.8.8" --storage local-lvm --rootfs 20 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.202/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"; then
    echo "Failed to create container for Sandbox-Deb-1 with CT-ID:202. Exiting Now....................."
    exit 1
fi

if ! pct create 203 local:vztmpl/$debian_template_name --tags "Sandbox-1" --hostname Sandbox-Deb-2 --nameserver "8.8.8.8" --storage local-lvm --rootfs 20 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.203/24,gw=192.168.50.1 --cores=2 --password changemenow --description "root:changemenow"; then
    echo "Failed to create container for Sandbox-Deb-2 with CT-ID:203. Exiting Now....................."
    exit 1
fi

#--------------------------------VM CREATION--------------------------------

if ! qm create 300 --name ubuntu-vm --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 local-lvm:10 --ide2 local:iso/ubuntu-22.04.iso,media=cdrom --boot order=ide2 --ostype l26;then
    echo "Failed to create VM for Ubuntu with VM-ID:201. Exiting Now....................."
    exit 1
fi

if ! qm create 301 --name kali-vm --memory 8192 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 local-lvm:10 --ide2 local:iso/kali-latest.iso,media=cdrom --boot order=ide2 --ostype l26;then
    echo "Failed to create VM for Kali with VM-ID:202. Exiting Now....................."
    exit 1
fi

if ! qm create 302 --name windows-vm --memory 8192 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 local-lvm:10 --ide2 local:iso/windows.iso,media=cdrom --boot order=ide2 --ostype win11;then
    echo "Failed to create VM for Windows with VM-ID:203. Exiting Now....................."
    exit 1
fi

if ! qm create 303 --name CaineOS --memory 8192 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 local-lvm:10 --ide2 local:iso/caine.iso,media=cdrom --boot order=ide2 --ostype l26;then
    echo "Failed to create VM for CaineOS with VM-ID:204. Exiting Now....................."
    exit 1
fi

#--------------------------------SFTP SERVER SETUP--------------------------------
setup_sftp(){
    while true; do
        read -p "Enter sftp username : " usname 
        if [ -n "$usname" ]; then
            break
        else
            echo "Username cannot be empty. Please enter a valid username."
        fi
    done
    pct start 101 && pct exec 101 -- bash -c "mkdir -p /ftpdir && chmod 701 /ftpdir && groupadd sftp_users && useradd -g sftp_users -d /upload -s /sbin/nologin $usname && echo \"Enter password for the new user\" && passwd $usname && mkdir -p /ftpdir/$usname/upload && chown -R root:sftp_users /ftpdir/$usname && chown -R $usname:sftp_users /ftpdir/$usname/upload && echo -e \"\nMatch Group sftp_users\nChrootDirectory /ftpdir/%u\nForceCommand internal-sftp\" >> /etc/ssh/sshd_config && systemctl restart sshd"
    
    #setup aliases and install net-tools
    pct exec 101 -- bash -c "dpkg -s net-tools >/dev/null 2>&1 || apt install net-tools -y && echo -e 'alias upd="apt update -y"\nalias upg="apt upgrade -y"\nalias cx="clear"\nalias nstatus="/usr/bin/watch -n 1 /usr/bin/netstat -alntup"\nalias instl="apt install -y"\nalias serve="ip a && python3 -m http.server 9090"' >> ~/.bashrc" || { echo "Failed to set aliases or install net-tools in GRR-Rapid container. Exiting."; exit 1; }

}

setup_sftp

#-------------------------------WAZUH SETUP--------------------------------

install_wazuh(){
    pct start 102 && pct exec 102 -- bash -c "curl -sO https://packages.wazuh.com/4.12/wazuh-install.sh && bash ./wazuh-install.sh -a && echo \"You can access Wazuh dashboard at https://192.168.50.105/\""
    #setup aliases and install net-tools
    pct exec 102 -- bash -c "dpkg -s net-tools >/dev/null 2>&1 || apt install net-tools -y && echo -e 'alias upd="apt update -y"\nalias upg="apt upgrade -y"\nalias cx="clear"\nalias nstatus="/usr/bin/watch -n 1 /usr/bin/netstat -alntup"\nalias instl="apt install -y"\nalias serve="ip a && python3 -m http.server 9090"' >> ~/.bashrc" || { echo "Failed to set aliases or install net-tools in GRR-Rapid container. Exiting."; exit 1; }
    pct stop 102
}

install_wazuh

#-------------------------------VELOCIRAPTOR SETUP--------------------------------

install_velociraptor(){
    pct start 103 || { echo "Failed to start container for Velociraptor with CT-ID:103. Exiting Now....................."; exit 1; }
    pct exec 103 -- bash -c "[ ! -d /etc ] && mkdir /etc; [ ! -f /etc/velociraptor.config.yaml ] && touch /etc/velociraptor.config.yaml" || { echo "Failed to prepare configuration for Velociraptor. Exiting."; exit 1; }
    #setup aliases and install net-tools
    pct exec 103 -- bash -c "dpkg -s net-tools >/dev/null 2>&1 || apt install net-tools -y && echo -e 'alias upd="apt update -y"\nalias upg="apt upgrade -y"\nalias cx="clear"\nalias nstatus="/usr/bin/watch -n 1 /usr/bin/netstat -alntup"\nalias instl="apt install -y"\nalias serve="ip a && python3 -m http.server 9090"' >> ~/.bashrc" || { echo "Failed to set aliases or install net-tools in Velociraptor container. Exiting."; exit 1; }

    pct exec 103 -- bash -c "[ ! -d /lib/systemd/system ] && mkdir -p /lib/systemd/system" || { echo "Failed to prepare systemd directory. Exiting."; exit 1; }
    pct exec 103 -- bash -c '
    cat << "EOF" > /tmp/install_velociraptor.sh
    #!/bin/bash
    set -e
    
    wget https://github.com/Velocidex/velociraptor/releases/download/v0.72/velociraptor-v0.72.4-linux-amd64
    cp ./velociraptor-v0.72.4-linux-amd64 /usr/local/bin/velociraptor
    chmod +x /usr/local/bin/velociraptor
    /usr/local/bin/velociraptor config generate -i
    sed -i "s/bind_address: 127.0.0.1/bind_address: 192.168.50.110/" /etc/velociraptor.config.yaml
    
    cat <<EOL > /lib/systemd/system/velociraptor.service
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
    ' || { echo "Failed to install Velociraptor. Exiting."; exit 1; }
    pct stop 103
}

install_velociraptor

#-------------------------------GRR-RAPID SETUP--------------------------------

setup_grr(){
    pct start 104 || { echo "Failed to start container for GRR-Rapid with CT-ID:104. Exiting Now....................."; exit 1; }
    pct exec 104 -- bash -c "apt update -y && apt install mariadb-server -y && wget https://storage.googleapis.com/releases.grr-response.com/grr-server_3.4.7-1_amd64.deb "  
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

    # Some MariaDB builds show this. Answer "n" and continue; if not shown, we fall through.
    expect {
        -re {Switch to unix_socket authentication.*\[Y/n\]} { send "n\r"; exp_continue }
        -re {Set root password\?.*\[Y/n\]} { send "n\r" }
    }

    expect -re {Remove anonymous users\?.*\[Y/n\]}
    send "Y\r"

    expect -re {Disallow root login remotely\?.*\[Y/n\]}
    send "Y\r"

    expect -re {Remove test database.*\[Y/n\]}
    send "Y\r"

    expect -re {Reload privilege tables now\?.*\[Y/n\]}
    send "Y\r"

    expect eof
    EOF
    ' 
    #pct exec 104 -- bash -c "apt install net-tools -y && echo -e 'alias upd="apt update -y"\nalias upg="apt upgrade -y"\nalias cx="clear"\nalias nstatus="/usr/bin/watch -n 1 /usr/bin/netstat -alntup"\nalias instl="apt install -y"\nalias serve="ip a && python3 -m http.server 9090"' >> ~/.bashrc
    
    #setup aliases and install net-tools
    pct exec 104 -- bash -c "dpkg -s net-tools >/dev/null 2>&1 || apt install net-tools -y && echo -e 'alias upd="apt update -y"\nalias upg="apt upgrade -y"\nalias cx="clear"\nalias nstatus="/usr/bin/watch -n 1 /usr/bin/netstat -alntup"\nalias instl="apt install -y"\nalias serve="ip a && python3 -m http.server 9090"' >> ~/.bashrc" || { echo "Failed to set aliases or install net-tools in GRR-Rapid container. Exiting."; exit 1; }
    pct stop 104
}

setup_grr