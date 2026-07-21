#!/bin/bash

# ============================================================
# ULTIMATE DAYTONA NETWORK FIX SCRIPT v3.0
# Har issue ka solution - One Script to Rule Them All!
# ============================================================

R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; B="\033[1;34m"
C="\033[1;36m"; M="\033[1;35m"; W="\033[1;37m"; N="\033[0m"

# ============================================================
# BEAUTIFUL HEADER
# ============================================================
clear
echo -e "${R}╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${R}║${N}  ${M}█▀█${C} █▀▀${G} █▄░█${Y} ${W}▀█▀${B} █▀█${M} █▀▀${C} ${G}█▀▄${Y} █▀▀${B} █▀▀${M}  ${R}║${N}"
echo -e "${R}║${N}  ${M}█▀▄${C} █▀▀${G} █░▀█${Y} ${W}░█░${B} █▄█${M} █▀▀${C} ${G}█▄▀${Y} █▀▀${B} █▀▀${M}  ${R}║${N}"
echo -e "${R}║${N}  ${M}▀░▀${C} ▀▀▀${G} ▀░░▀${Y} ${W}░▀░${B} ▀░▀${M} ▀▀▀${C} ${G}▀░▀${Y} ▀▀▀${B} ▀▀▀${M}  ${R}║${N}"
echo -e "${R}╚══════════════════════════════════════════════════════════╝${N}"
echo -e "${C}       ULTIMATE NETWORK FIX by CodingBoyz- ${W}v3.0${N}"
echo ""

# ============================================================
# CHECK ROOT
# ============================================================
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}[✘]${N} ${W}This script must be run as root!${N}"
    echo -e "${Y}[!]${N} Run: ${C}sudo bash $0${N}"
    exit 1
fi

# ============================================================
# VARIABLES
# ============================================================
PROXY_IP="10.0.2.2"
PROXY_PORT="8796"
PROXY_URL="http://${PROXY_IP}:${PROXY_PORT}"
LOG_FILE="/var/log/daytona-fix.log"
BACKUP_DIR="/root/daytona-backup-$(date +%Y%m%d_%H%M%S)"
INTERFACE="eth0"
DNS_SERVERS=("8.8.8.8" "1.1.1.1" "208.67.222.222")
FAILED=0
FIXED=0

# ============================================================
# FUNCTIONS
# ============================================================

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

print_status() {
    echo -ne "${Y}[${N}"
    for i in {1..20}; do
        echo -ne "${G}█${N}"
        sleep 0.02
    done
    echo -e "${Y}]${N} ${C}$1${N}"
}

check_internet() {
    echo -ne "${Y}[${N}${C}Testing Internet${N}${Y}]${N} "
    if ping -c 2 8.8.8.8 &>/dev/null || wget -q --spider http://google.com; then
        echo -e "${G}✓ Connected${N}"
        return 0
    else
        echo -e "${R}✘ No Internet${N}"
        return 1
    fi
}

backup_configs() {
    log "${Y}[*]${N} Creating backup at: ${C}$BACKUP_DIR${N}"
    mkdir -p "$BACKUP_DIR"
    
    for file in /etc/profile.d/daytona-net.sh /etc/environment /etc/apt/apt.conf.d/99proxy /etc/sudoers.d/proxy /etc/resolv.conf /etc/hosts; do
        if [ -f "$file" ]; then
            cp "$file" "$BACKUP_DIR/" 2>/dev/null
            log "${G}[✓]${N} Backed up: $file"
        fi
    done
}

fix_proxy() {
    log "${Y}[*]${N} Setting up proxy configurations..."
    
    # Profile.d
    cat > /etc/profile.d/daytona-net.sh << EOF
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export FTP_PROXY="$PROXY_URL"
export ftp_proxy="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export all_proxy="$PROXY_URL"
export NO_PROXY="localhost,127.0.0.1,::1,*.local"
export no_proxy="localhost,127.0.0.1,::1,*.local"
EOF
    chmod +x /etc/profile.d/daytona-net.sh
    log "${G}[✓]${N} /etc/profile.d/daytona-net.sh"
    
    # Environment
    cat > /etc/environment << EOF
HTTP_PROXY="$PROXY_URL"
HTTPS_PROXY="$PROXY_URL"
http_proxy="$PROXY_URL"
https_proxy="$PROXY_URL"
FTP_PROXY="$PROXY_URL"
ftp_proxy="$PROXY_URL"
ALL_PROXY="$PROXY_URL"
all_proxy="$PROXY_URL"
NO_PROXY="localhost,127.0.0.1,::1,*.local"
no_proxy="localhost,127.0.0.1,::1,*.local"
EOF
    log "${G}[✓]${N} /etc/environment"
    
    # APT
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99proxy << EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
Acquire::ftp::Proxy "$PROXY_URL";
Acquire::socks::Proxy "$PROXY_URL";
EOF
    log "${G}[✓]${N} /etc/apt/apt.conf.d/99proxy"
    
    # Sudoers
    cat > /etc/sudoers.d/proxy << EOF
Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy FTP_PROXY ftp_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"
EOF
    chmod 440 /etc/sudoers.d/proxy
    log "${G}[✓]${N} sudoers proxy"
}

fix_dns() {
    log "${Y}[*]${N} Configuring DNS..."
    
    # Backup original resolv.conf
    [ -f /etc/resolv.conf ] && cp /etc/resolv.conf "$BACKUP_DIR/"
    
    # New resolv.conf
    cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 208.67.222.222
options timeout:2 attempts:5
EOF
    log "${G}[✓]${N} DNS configured"
    
    # Make immutable
    chattr +i /etc/resolv.conf 2>/dev/null || chmod 444 /etc/resolv.conf
    log "${G}[✓]${N} DNS locked"
}

fix_hosts() {
    log "${Y}[*]${N} Fixing hosts file..."
    
    cat > /etc/hosts << EOF
127.0.0.1 localhost localhost.localdomain
127.0.1.1 daytona
::1 localhost ip6-localhost ip6-loopback
10.0.2.2 host.docker.internal
10.0.2.2 gateway.docker.internal
EOF
    log "${G}[✓]${N} Hosts fixed"
}

fix_network_interfaces() {
    log "${Y}[*]${N} Configuring network interfaces..."
    
    # Detect interface
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    [ -z "$INTERFACE" ] && INTERFACE="eth0"
    
    # Bring up interface
    ip link set "$INTERFACE" up 2>/dev/null
    log "${G}[✓]${N} Interface: $INTERFACE"
    
    # Add routes
    ip route add default via 10.0.2.2 dev "$INTERFACE" 2>/dev/null
    log "${G}[✓]${N} Default route set"
}

fix_wget_curl() {
    log "${Y}[*]${N} Configuring wget/curl..."
    
    # Wget
    mkdir -p /etc/wgetrc.d/
    cat > /etc/wgetrc << EOF
use_proxy = on
http_proxy = $PROXY_URL
https_proxy = $PROXY_URL
ftp_proxy = $PROXY_URL
EOF
    
    # Curl
    mkdir -p /etc/curlrc.d/
    cat > /etc/curlrc << EOF
proxy = "$PROXY_URL"
EOF
    log "${G}[✓]${N} wget/curl configured"
}

fix_git() {
    log "${Y}[*]${N} Configuring Git proxy..."
    
    git config --global http.proxy "$PROXY_URL" 2>/dev/null
    git config --global https.proxy "$PROXY_URL" 2>/dev/null
    log "${G}[✓]${N} Git configured"
}

fix_docker() {
    if command -v docker &>/dev/null; then
        log "${Y}[*]${N} Configuring Docker..."
        mkdir -p /etc/systemd/system/docker.service.d
        cat > /etc/systemd/system/docker.service.d/http-proxy.conf << EOF
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
        systemctl daemon-reload 2>/dev/null
        systemctl restart docker 2>/dev/null
        log "${G}[✓]${N} Docker configured"
    fi
}

fix_pip_npm() {
    log "${Y}[*]${N} Configuring pip/npm..."
    
    # Pip
    mkdir -p /root/.pip
    cat > /root/.pip/pip.conf << EOF
[global]
proxy = $PROXY_URL
EOF
    
    # NPM
    npm config set proxy "$PROXY_URL" 2>/dev/null
    npm config set https-proxy "$PROXY_URL" 2>/dev/null
    log "${G}[✓]${N} pip/npm configured"
}

fix_android_sdk() {
    log "${Y}[*]${N} Configuring Android SDK..."
    
    if [ -d "/opt/android-sdk" ] || [ -d "$HOME/Android" ]; then
        export ANDROID_SDK_HOME="${ANDROID_SDK_HOME:-$HOME/Android/Sdk}"
        mkdir -p "$ANDROID_SDK_HOME" 2>/dev/null
        
        cat > ~/.android/androidtool.cfg << EOF
http.proxyHost=$PROXY_IP
http.proxyPort=$PROXY_PORT
https.proxyHost=$PROXY_IP
https.proxyPort=$PROXY_PORT
EOF
        log "${G}[✓]${N} Android SDK configured"
    fi
}

fix_firewall() {
    log "${Y}[*]${N} Configuring firewall..."
    
    # Allow proxy port
    if command -v ufw &>/dev/null; then
        ufw allow 8796/tcp 2>/dev/null
        ufw allow out 8796/tcp 2>/dev/null
        log "${G}[✓]${N} UFW configured"
    fi
    
    if command -v iptables &>/dev/null; then
        iptables -A INPUT -p tcp --dport 8796 -j ACCEPT 2>/dev/null
        iptables -A OUTPUT -p tcp --sport 8796 -j ACCEPT 2>/dev/null
        log "${G}[✓]${N} iptables configured"
    fi
}

fix_ssh() {
    log "${Y}[*]${N} Configuring SSH proxy..."
    
    mkdir -p ~/.ssh
    cat >> ~/.ssh/config << EOF
Host *
    ProxyCommand nc -X connect -x $PROXY_IP:$PROXY_PORT %h %p
EOF
    log "${G}[✓]${N} SSH configured"
}

fix_systemd() {
    log "${Y}[*]${N} Configuring systemd proxy..."
    
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/proxy.conf << EOF
[Manager]
DefaultEnvironment="HTTP_PROXY=$PROXY_URL"
DefaultEnvironment="HTTPS_PROXY=$PROXY_URL"
DefaultEnvironment="http_proxy=$PROXY_URL"
DefaultEnvironment="https_proxy=$PROXY_URL"
EOF
    systemctl daemon-reload 2>/dev/null
    log "${G}[✓]${N} Systemd configured"
}

restart_services() {
    log "${Y}[*]${N} Restarting services..."
    
    # Apply all changes
    source /etc/profile.d/daytona-net.sh 2>/dev/null
    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"
    export HTTP_PROXY="$PROXY_URL"
    export HTTPS_PROXY="$PROXY_URL"
    
    # Restart services
    for service in networking network-manager systemd-resolved avahi-daemon; do
        systemctl restart "$service" 2>/dev/null
    done
    
    log "${G}[✓]${N} Services restarted"
}

verify_fix() {
    log "${Y}[*]${N} Verifying fix..."
    
    echo ""
    echo -e "${C}═══════════════════════════════════════════════════════════${N}"
    echo -e "${W}  VERIFICATION RESULTS${N}"
    echo -e "${C}═══════════════════════════════════════════════════════════${N}"
    
    # Check proxy
    echo -ne "${Y}  Proxy Set:${N} "
    [ -n "$HTTP_PROXY" ] && echo -e "${G}✓${N}" || echo -e "${R}✘${N}"
    
    # Check internet
    echo -ne "${Y}  Internet:${N} "
    ping -c 1 8.8.8.8 &>/dev/null && echo -e "${G}✓${N}" || echo -e "${R}✘${N}"
    
    # Check DNS
    echo -ne "${Y}  DNS:${N} "
    nslookup google.com &>/dev/null && echo -e "${G}✓${N}" || echo -e "${R}✘${N}"
    
    # Check APT
    echo -ne "${Y}  APT:${N} "
    apt update &>/dev/null && echo -e "${G}✓${N}" || echo -e "${R}✘${N}"
    
    # Check wget
    echo -ne "${Y}  wget:${N} "
    wget -q --spider http://google.com && echo -e "${G}✓${N}" || echo -e "${R}✘${N}"
    
    echo -e "${C}═══════════════════════════════════════════════════════════${N}"
    echo ""
}

show_summary() {
    echo -e "${C}┌─────────────────────────────────────────────────────────────┐${N}"
    echo -e "${C}│${N}  ${G}✅ FIX COMPLETE!${N}                                      ${C}│${N}"
    echo -e "${C}│${N}                                                           ${C}│${N}"
    echo -e "${C}│${N}  ${W}Backup created at:${N} ${Y}$BACKUP_DIR${N}                       ${C}│${N}"
    echo -e "${C}│${N}  ${W}Log file:${N} ${Y}$LOG_FILE${N}                                  ${C}│${N}"
    echo -e "${C}│${N}                                                           ${C}│${N}"
    echo -e "${C}│${N}  ${W}If still issues:${N}                                          ${C}│${N}"
    echo -e "${C}│${N}  ${Y}1.${N} Run: ${C}source /etc/profile.d/daytona-net.sh${N}        ${C}│${N}"
    echo -e "${C}│${N}  ${Y}2.${N} Restart terminal${N}                                    ${C}│${N}"
    echo -e "${C}│${N}  ${Y}3.${N} Reboot emulator${N}                                    ${C}│${N}"
    echo -e "${C}│${N}                                                           ${C}│${N}"
    echo -e "${C}└─────────────────────────────────────────────────────────────┘${N}"
    echo ""
}

# ============================================================
# MAIN EXECUTION
# ============================================================

log "${G}[+]${N} Starting Daytona Ultimate Fix v3.0"
log "${Y}[*]${N} Time: $(date)"

# Show progress
echo -e "${Y}┌──────────────────────────────────────────────────┐${N}"
echo -e "${Y}│${N}  ${C}Fixing everything... Please wait${N}              ${Y}│${N}"
echo -e "${Y}└──────────────────────────────────────────────────┘${N}"
echo ""

# Backup
backup_configs

# Check current status
check_internet && INTERNET_OK=true || INTERNET_OK=false

# Fix everything
fix_proxy
fix_dns
fix_hosts
fix_network_interfaces
fix_wget_curl
fix_git
fix_docker
fix_pip_npm
fix_android_sdk
fix_firewall
fix_ssh
fix_systemd
restart_services

# Final check
echo ""
print_status "Verifying all fixes..."
verify_fix

# Summary
show_summary

# Export for current session
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"

log "${G}[+]${N} Fix completed successfully!"

# Re-source profile
source /etc/profile.d/daytona-net.sh 2>/dev/null

echo -e "${G}✅ Done!${N} Network should work now."
echo -e "${Y}💡 Tip:${N} Run ${C}source /etc/profile.d/daytona-net.sh${N} if proxy not working"
echo ""
