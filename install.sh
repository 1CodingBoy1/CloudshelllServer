#!/bin/bash
#############################################################
#                                                           #
#  Minecraft Paper Server - One-Click Setup                #
#  For Google Cloud Shell & Ubuntu/Debian                   #
#  GitHub: Add your repo link here                          #
#                                                           #
#############################################################

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Server Settings
SERVER_DIR="$HOME/minecraft-server"
MINECRAFT_VERSION="1.21.4"
RAM_MIN="2G"
RAM_MAX="4G"

# Function to print colored text
print_msg() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date +'%H:%M:%S')] ${message}${NC}"
}

# ASCII Art Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║                                                       ║"
    echo "║         Minecraft Paper Server Installer              ║"
    echo "║         Cloud Shell / VPS Edition                     ║"
    echo "║                                                       ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check if running in Cloud Shell
check_cloud_shell() {
    if [ -n "$CLOUD_SHELL" ] || [ -n "$GOOGLE_CLOUD_SHELL" ]; then
        print_msg "$GREEN" "✓ Google Cloud Shell Detected"
        IS_CLOUD_SHELL=true
    else
        print_msg "$YELLOW" "⚠ Running on VPS/Regular Server"
        IS_CLOUD_SHELL=false
    fi
}

# Install required packages
install_dependencies() {
    print_msg "$BLUE" "📦 Installing dependencies..."
    
    sudo apt-get update -y > /dev/null 2>&1
    sudo apt-get install -y \
        openjdk-21-jdk \
        screen \
        wget \
        curl \
        jq \
        unzip \
        tar > /dev/null 2>&1
    
    print_msg "$GREEN" "✓ Dependencies installed"
}

# Download PaperMC
download_paper() {
    print_msg "$BLUE" "🔍 Fetching latest PaperMC build for $MINECRAFT_VERSION..."
    
    mkdir -p "$SERVER_DIR"
    cd "$SERVER_DIR"
    
    # Fetch latest build info
    BUILD_INFO=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION/builds")
    
    if [ -z "$BUILD_INFO" ]; then
        print_msg "$RED" "✗ Failed to fetch build information"
        print_msg "$YELLOW" "Trying alternative version 1.21.3..."
        MINECRAFT_VERSION="1.21.3"
        BUILD_INFO=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION/builds")
    fi
    
    LATEST_BUILD=$(echo "$BUILD_INFO" | jq -r '.builds[-1].build')
    BUILD_NUMBER=$(echo "$BUILD_INFO" | jq -r '.builds[-1].build')
    
    if [ -z "$LATEST_BUILD" ] || [ "$LATEST_BUILD" == "null" ]; then
        print_msg "$RED" "✗ Could not find build for version $MINECRAFT_VERSION"
        print_msg "$YELLOW" "Please check https://papermc.io/downloads for available versions"
        exit 1
    fi
    
    print_msg "$GREEN" "✓ Found build #$BUILD_NUMBER"
    
    DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION/builds/$BUILD_NUMBER/downloads/paper-$MINECRAFT_VERSION-$BUILD_NUMBER.jar"
    
    print_msg "$BLUE" "📥 Downloading PaperMC..."
    wget -q --show-progress -O paper.jar "$DOWNLOAD_URL"
    
    if [ -f "paper.jar" ]; then
        chmod +x paper.jar
        print_msg "$GREEN" "✓ PaperMC downloaded successfully"
    else
        print_msg "$RED" "✗ Download failed!"
        exit 1
    fi
}

# Accept EULA
accept_eula() {
    print_msg "$BLUE" "📝 Accepting Minecraft EULA..."
    echo "eula=true" > "$SERVER_DIR/eula.txt"
    print_msg "$GREEN" "✓ EULA accepted"
}

# Create server.properties
create_server_properties() {
    print_msg "$BLUE" "⚙️ Configuring server..."
    
    cat > "$SERVER_DIR/server.properties" << 'EOF'
#Minecraft server properties
enable-jmx-monitoring=false
rcon.port=25575
level-seed=
gamemode=survival
enable-command-block=false
enable-query=false
generator-settings={}
level-name=world
motd=A Minecraft Server Powered by Paper
query.port=25565
pvp=true
generate-structures=true
difficulty=easy
network-compression-threshold=256
max-tick-time=60000
max-players=20
use-native-transport=true
online-mode=true
enable-status=true
allow-flight=false
broadcast-rcon-to-ops=true
view-distance=8
max-build-height=256
server-ip=
allow-nether=true
server-port=25565
enable-rcon=false
sync-chunk-writes=true
op-permission-level=4
prevent-proxy-connections=false
hide-online-players=false
resource-pack=
entity-broadcast-range-percentage=100
simulation-distance=5
rcon.password=
player-idle-timeout=0
force-gamemode=false
rate-limit=0
hardcore=false
white-list=false
broadcast-console-to-ops=true
spawn-npcs=true
spawn-animals=true
function-permission-level=2
level-type=minecraft\:normal
text-filtering-config=
spawn-monsters=true
enforce-whitelist=false
resource-pack-sha1=
spawn-protection=16
max-world-size=29999984
EOF
    
    print_msg "$GREEN" "✓ Server.properties configured"
}

# Create start script
create_start_script() {
    print_msg "$BLUE" "📜 Creating start script..."
    
    cat > "$SERVER_DIR/start.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"
echo "Starting Minecraft Server..."
echo "RAM: $RAM_MIN - $RAM_MAX"
echo "Version: $MINECRAFT_VERSION"
echo ""
screen -dmS minecraft java \\
    -Xms$RAM_MIN \\
    -Xmx$RAM_MAX \\
    -XX:+UseG1GC \\
    -XX:+ParallelRefProcEnabled \\
    -XX:MaxGCPauseMillis=200 \\
    -XX:+UnlockExperimentalVMOptions \\
    -XX:+DisableExplicitGC \\
    -XX:+AlwaysPreTouch \\
    -XX:G1NewSizePercent=30 \\
    -XX:G1MaxNewSizePercent=40 \\
    -XX:G1HeapRegionSize=8M \\
    -XX:G1ReservePercent=20 \\
    -XX:G1HeapWastePercent=5 \\
    -XX:G1MixedGCCountTarget=4 \\
    -XX:InitiatingHeapOccupancyPercent=15 \\
    -XX:G1MixedGCLiveThresholdPercent=90 \\
    -XX:G1RSetUpdatingPauseTimePercent=5 \\
    -XX:SurvivorRatio=32 \\
    -XX:+PerfDisableSharedMem \\
    -XX:MaxTenuringThreshold=1 \\
    -jar paper.jar --nogui

echo "Server started! Use 'screen -r minecraft' to view console"
EOF
    
    chmod +x "$SERVER_DIR/start.sh"
    print_msg "$GREEN" "✓ Start script created"
}

# Create stop script
create_stop_script() {
    cat > "$SERVER_DIR/stop.sh" << 'EOF'
#!/bin/bash
if screen -list | grep -q "minecraft"; then
    echo "Stopping Minecraft server..."
    screen -S minecraft -p 0 -X stuff "say Server stopping in 10 seconds...$(printf '\r')"
    sleep 5
    screen -S minecraft -p 0 -X stuff "save-all$(printf '\r')"
    sleep 5
    screen -S minecraft -p 0 -X stuff "stop$(printf '\r')"
    echo "Server stopped!"
else
    echo "Server is not running!"
fi
EOF
    
    chmod +x "$SERVER_DIR/stop.sh"
}

# Create backup script
create_backup_script() {
    cat > "$SERVER_DIR/backup.sh" << 'EOF'
#!/bin/bash
BACKUP_DIR="$(dirname "$0")/backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo "Creating backup..."
tar -czf "$BACKUP_DIR/world_backup_$TIMESTAMP.tar.gz" -C "$(dirname "$0")" world world_nether world_the_end 2>/dev/null
echo "Backup saved to: $BACKUP_DIR/world_backup_$TIMESTAMP.tar.gz"
EOF
    
    chmod +x "$SERVER_DIR/backup.sh"
}

# Show server info
show_info() {
    clear
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Installation Complete!${NC}"
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}📂 Server Location:${NC} $SERVER_DIR"
    echo -e "${YELLOW}🎮 Minecraft Version:${NC} $MINECRAFT_VERSION"
    echo -e "${YELLOW}💾 RAM Allocation:${NC} $RAM_MIN - $RAM_MAX"
    echo ""
    echo -e "${CYAN}📋 Available Commands:${NC}"
    echo -e "${GREEN}  Start Server:${NC}    bash $SERVER_DIR/start.sh"
    echo -e "${GREEN}  Stop Server:${NC}     bash $SERVER_DIR/stop.sh"
    echo -e "${GREEN}  View Console:${NC}    screen -r minecraft"
    echo -e "${GREEN}  Detach Console:${NC}  CTRL+A then D"
    echo -e "${GREEN}  Backup World:${NC}    bash $SERVER_DIR/backup.sh"
    echo ""
    echo -e "${YELLOW}⚡ Quick Start:${NC}"
    echo -e "  cd $SERVER_DIR && bash start.sh"
    echo ""
}

# Main installation function
install_server() {
    show_banner
    print_msg "$PURPLE" "🚀 Starting Minecraft Server Installation..."
    echo ""
    
    check_cloud_shell
    
    if [ "$IS_CLOUD_SHELL" = true ]; then
        print_msg "$YELLOW" "⚠ Cloud Shell has limited resources (2GB RAM)"
        print_msg "$YELLOW" "⚠ Server may be slow or crash on high load"
        RAM_MIN="1G"
        RAM_MAX="2G"
        echo ""
        read -p "Continue? (y/n): " choice
        if [ "$choice" != "y" ]; then
            exit 0
        fi
    fi
    
    install_dependencies
    download_paper
    accept_eula
    create_server_properties
    create_start_script
    create_stop_script
    create_backup_script
    
    show_info
    
    # Ask to start server
    echo ""
    read -p "Start server now? (y/n): " start_choice
    if [ "$start_choice" = "y" ]; then
        print_msg "$BLUE" "Starting server..."
        cd "$SERVER_DIR" && bash start.sh
        sleep 3
        echo ""
        print_msg "$GREEN" "Server started! Attach console with: screen -r minecraft"
    fi
}

# Menu function
show_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║       Minecraft Server Manager             ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Check server status
        if screen -list 2>/dev/null | grep -q "minecraft"; then
            echo -e "Status: ${GREEN}● Online${NC}"
        else
            echo -e "Status: ${RED}● Offline${NC}"
        fi
        
        echo ""
        echo -e "${YELLOW}1)${NC} Install/Reinstall Server"
        echo -e "${YELLOW}2)${NC} Start Server"
        echo -e "${YELLOW}3)${NC} Stop Server"
        echo -e "${YELLOW}4)${NC} View Console"
        echo -e "${YELLOW}5)${NC} Backup World"
        echo -e "${YELLOW}6)${NC} Edit server.properties"
        echo -e "${YELLOW}7)${NC} Exit"
        echo ""
        read -p "Choose option (1-7): " opt
        
        case $opt in
            1) install_server ;;
            2) bash "$SERVER_DIR/start.sh" 2>/dev/null || echo "Server not installed!";;
            3) bash "$SERVER_DIR/stop.sh" 2>/dev/null || echo "Server not installed!";;
            4) screen -r minecraft 2>/dev/null || echo "Server not running!";;
            5) bash "$SERVER_DIR/backup.sh" 2>/dev/null || echo "Server not installed!";;
            6) nano "$SERVER_DIR/server.properties" 2>/dev/null || echo "Server not installed!";;
            7) echo "Goodbye!"; exit 0;;
            *) echo "Invalid option!";;
        esac
        
        read -p "Press Enter to continue..."
    done
}

# Start the script
case "${1}" in
    install)
        install_server
        ;;
    menu)
        show_menu
        ;;
    start)
        bash "$SERVER_DIR/start.sh"
        ;;
    stop)
        bash "$SERVER_DIR/stop.sh"
        ;;
    *)
        show_menu
        ;;
esac
