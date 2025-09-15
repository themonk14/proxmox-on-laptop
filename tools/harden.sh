#!/bin/bash
# This script applies basic security hardening measures to my Proxmox node.

set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This script targets Debian/Ubuntu based systems." >&2
    exit 1
fi

if [[ $(id -u) -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

SSH_PORT_DEFAULT=2232
read -rp "Desired SSH port [${SSH_PORT_DEFAULT}]: " ssh_port
ssh_port=${ssh_port:-$SSH_PORT_DEFAULT}

if ! [[ $ssh_port =~ ^[0-9]+$ ]] || ((ssh_port < 1 || ssh_port > 65535)); then
    echo "Invalid SSH port: $ssh_port" >&2
    exit 1
fi

read -rp "Enter delegated admin username [pveadmin]: " usernm
usernm=${usernm:-pveadmin}

if ! [[ $usernm =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "Invalid username: $usernm" >&2
    exit 1
fi

echo "Installing baseline security packages..."
$SUDO apt-get update
$SUDO apt-get install -y \
    aide \
    apt-listchanges \
    chkrootkit \
    fail2ban \
    logwatch \
    needrestart \
    rkhunter \
    rsyslog \
    unattended-upgrades \
    ufw

if ! id -u "$usernm" >/dev/null 2>&1; then
    echo "Creating user $usernm with sudo privileges"
    $SUDO useradd -m -s /bin/bash "$usernm"
    $SUDO usermod -aG sudo "$usernm"
    echo "Set a strong password for $usernm"
    $SUDO passwd "$usernm"
else
    echo "User $usernm already exists; ensuring sudo group membership"
    if ! id -nG "$usernm" | tr ' ' '\n' | grep -qx "sudo"; then
        $SUDO usermod -aG sudo "$usernm"
    fi
fi

if [[ -f /etc/ssh/sshd_config ]] && [[ ! -f /etc/ssh/sshd_config.pre-hardening ]]; then
    echo "Backing up existing sshd_config to /etc/ssh/sshd_config.pre-hardening"
    $SUDO cp /etc/ssh/sshd_config /etc/ssh/sshd_config.pre-hardening
fi

cat <<SSHD | $SUDO tee /etc/ssh/sshd_config >/dev/null
Include /etc/ssh/sshd_config.d/*.conf
Protocol 2
Port ${ssh_port}
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

# ===== Authentication =====
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
LoginGraceTime 1m
MaxAuthTries 3
MaxSessions 2
PermitEmptyPasswords no
PermitRootLogin no
PermitTunnel no

# ===== Network Behaviour =====
ClientAliveInterval 60
ClientAliveCountMax 2
MaxStartups 10:30:100
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
TCPKeepAlive no
Compression delayed
UseDNS no

# ===== Auditing =====
LogLevel VERBOSE
SyslogFacility AUTHPRIV
PrintMotd no
PrintLastLog yes
VersionAddendum none

# ===== Host Restrictions =====
HostbasedAuthentication no
IgnoreRhosts yes
GSSAPIAuthentication no
# AllowUsers ${usernm}

# Update the Match block to restrict administrative networks when ready
# Match Address 10.0.0.0/24
SSHD

if $SUDO systemctl list-unit-files | awk '{print $1}' | grep -qx "ssh.service"; then
    $SUDO systemctl restart ssh
elif $SUDO systemctl list-unit-files | awk '{print $1}' | grep -qx "sshd.service"; then
    $SUDO systemctl restart sshd
else
    echo "Warning: unable to automatically restart SSH service" >&2
fi

echo "Configuring UFW firewall policies"
$SUDO ufw default deny incoming
$SUDO ufw default allow outgoing
$SUDO ufw allow "${ssh_port}/tcp"
$SUDO ufw allow 8006/tcp
read -rp "Allow SPICE console range 5900:5999/tcp? [Y/n]: " allow_spice
if [[ -z ${allow_spice} || ${allow_spice} =~ ^[Yy]$ ]]; then
    $SUDO ufw allow 5900:5999/tcp
fi
if $SUDO ufw status 2>&1 | grep -q "Status: inactive"; then
    echo "Enabling UFW"
    $SUDO ufw --force enable
fi

echo "Configuring Fail2Ban"
$SUDO install -d -m 755 /etc/fail2ban/jail.d
cat <<EOF | $SUDO tee /etc/fail2ban/jail.d/hardening.local >/dev/null
[sshd]
enabled = true
backend = systemd
port = ${ssh_port}
maxretry = 3
findtime = 10m
bantime = 1h
ignoreip = 127.0.0.1/8 ::1

[recidive]
enabled = true
bantime = 1w
findtime = 1d
maxretry = 5
EOF
$SUDO systemctl restart fail2ban

echo "Configuring unattended upgrades"
cat <<'EOF' | $SUDO tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Verbose "1";
EOF

cat <<'EOF' | $SUDO tee /etc/apt/apt.conf.d/51hardening-unattended-upgrades >/dev/null
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Mail "";
EOF

echo "Applying kernel and network sysctl hardening"
cat <<'EOF' | $SUDO tee /etc/sysctl.d/99-hardening.conf >/dev/null
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.randomize_va_space = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 1
fs.protected_regular = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF
$SUDO sysctl --system >/dev/null

if command -v aideinit >/dev/null 2>&1; then
    if [[ ! -f /var/lib/aide/aide.db ]]; then
        echo "Initializing AIDE integrity database"
        $SUDO aideinit
        $SUDO mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi
fi

echo "Basic hardening complete. Review SSH access before logging out."
