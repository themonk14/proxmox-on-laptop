#!/bin/bash

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

#Create containers for SFTP, Velociraptor, Wazuh

if ! pct create 101 local:vztmpl/$template_name --hostname SFTP-Server-Ubu --storage local-lvm --rootfs 32 --memory 2048 --swap 1024 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.100/24,gw=192.168.50.1 --cores=1 --password changemenow; then
    echo "Failed to create container for SFTP with CT-ID:101. Exiting Now....................."
    exit 1
fi

if ! pct create 102 local:vztmpl/$template_name --hostname Wazuh-Ubu --storage local-lvm --rootfs 40 --memory 4096 --swap 4096 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.105/24,gw=192.168.50.1 --cores=4 --password changemenow; then
    echo "Failed to create container for Wazuh with CT-ID:102. Exiting Now....................."
    exit 1
fi

if ! pct create 103 local:vztmpl/$template_name --hostname Velociraptor-Ubu --storage local-lvm --rootfs 30 --memory 2048 --swap 2048 --net0 name=eth0,bridge=vmbr0,ip=192.168.50.110/24,gw=192.168.50.1 --cores=2 --password changemenow; then
    echo "Failed to create container for Velociraptor with CT-ID:103. Exiting Now....................."
    exit 1
fi

#This is where installation happens.

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
}

setup_sftp

install_wazuh(){
    pct start 102 && pct exec 102 -- bash -c "curl -sO https://packages.wazuh.com/4.8/wazuh-install.sh && bash ./wazuh-install.sh -a && echo \"You can access Wazuh dashboard at https://192.168.50.105/\""
}

install_wazuh

install_velociraptor(){
    pct start 103 || { echo "Failed to start container for Velociraptor with CT-ID:103. Exiting Now....................."; exit 1; }
    pct exec 103 -- bash -c "[ ! -d /etc ] && mkdir /etc; [ ! -f /etc/velociraptor.config.yaml ] && touch /etc/velociraptor.config.yaml" || { echo "Failed to prepare configuration for Velociraptor. Exiting."; exit 1; }
    pct exec 103 -- bash -c "[ ! -d /lib/systemd/system ] && mkdir -p /lib/systemd/system" || { echo "Failed to prepare systemd directory. Exiting."; exit 1; }
    pct exec 103 -- bash -c "wget https://github.com/Velocidex/velociraptor/releases/download/v0.72/velociraptor-v0.72.4-linux-amd64 && cp ./velociraptor* /usr/local/bin/velociraptor && chmod +x /usr/local/bin/velociraptor && /usr/local/bin/velociraptor config generate -i && sed -i 's/bind_address: 127.0.0.1/bind_address: 192.168.50.110/' /etc/velociraptor.config.yaml && touch /lib/systemd/system/velociraptor.service && echo -e \"[Unit]\nDescription=Velociraptor\nAfter=syslog.target network.target\n\n[Service]\nType=simple\nRestart=always\nRestartSec=120\nLimitNOFILE=20000\nEnvironment=LANG=en_US.UTF-8\nExecStart=/usr/local/bin/velociraptor --config /etc/velociraptor.config.yaml frontend -v\n\n[Install]\nWantedBy=multi-user.target\" > /lib/systemd/system/velociraptor.service && systemctl daemon-reload && systemctl enable --now velociraptor && echo 'https://192.168.50.110:8889/app/index.html'" || { echo "Failed to install Velociraptor. Exiting."; exit 1; }
}

install_velociraptor