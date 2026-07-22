#!/bin/bash
#############################################################
#                                                           #
#  Minecraft Paper Server Automated Setup Script            #
#  Compatible with Ubuntu 22.04/24.04, Debian 11/12/13,     #
#  and Google Cloud Shell                                   #
#                                                           #
#############################################################

# Exit on any error
set -e

# Color definitions for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Server configuration variables
SERVER_DIR="$HOME/MinecraftServer"
BACKUP_DIR="$SERVER_DIR/backups"
LOG_DIR="$SERVER_DIR/logs"
PLUGINS_DIR="$SERVER_DIR/plugins"
CRASH_LOG_DIR="$SERVER_DIR/crash-logs"
START_SCRIPT="$SERVER_DIR/start-server.sh"
STOP_SCRIPT="$SERVER_DIR/stop-server.sh"
RESTART_SCRIPT="$SERVER_DIR/restart-server.sh"
TUNNEL_SCRIPT="$SERVER_DIR/tunnel.sh"
BACKUP_SCRIPT="$SERVER_DIR/backup.sh"
SERVER_PROPERTIES="$SERVER_DIR/server.properties"
EULA_FILE="$SERVER_DIR/eula.txt"
PAPER_JAR="paper.jar"
XMS="4G"
XMX="8G"
MINECRAFT_VERSION=""
PAPER_BUILD=""
RESTART_ENABLED=true

#############################################################
# Utility Functions
#############################################################

# Print colored messages
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_header() { echo -e "${MAGENTA}$1${NC}"; }

# Check if command exists
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Detect Linux distribution
detect_os() {
    print_info "Detecting operating system..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        print_success "Detected: $OS $VERSION"
        
        # Check for Google Cloud Shell
        if [ -n "$CLOUD_SHELL" ] || [ -n "$GOOGLE_CLOUD_SHELL" ] || [ -d "/google" ]; then
            OS="google-cloud-shell"
            print_info "Google Cloud Shell detected"
        fi
    else
        print_error "Cannot detect OS. Exiting."
        exit 1
    fi
}

# Install required packages based on OS
install_packages() {
    print_info "Installing required packages..."
    
    case "$OS" in
        ubuntu|debian|google-cloud-shell)
            # Update package list
            sudo apt-get update -qq
            
            # Install required packages
            sudo apt-get install -y -qq \
                curl \
                wget \
                jq \
                screen \
                unzip \
                tar \
                gzip \
                ca-certificates
            
            print_success "Base packages installed"
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Install correct Java version (Java 21 for Minecraft 1.21.x)
install_java() {
    print_info "Checking Java installation..."
    
    # Check if Java is installed and version
    NEEDS_INSTALL=false
    if command_exists java; then
        JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | sed 's/^1\.//' | cut -d'.' -f1)
        print_info "Current Java version: $JAVA_VERSION"
        
        # Minecraft 1.21.x requires Java 21
        if [ "$JAVA_VERSION" -lt 21 ]; then
            print_warning "Java version $JAVA_VERSION detected. Java 21 required for Minecraft 1.21.x"
            NEEDS_INSTALL=true
        else
            print_success "Java $JAVA_VERSION is compatible"
            return 0
        fi
    else
        print_info "Java not found. Installing Java..."
        NEEDS_INSTALL=true
    fi
    
    if [ "$NEEDS_INSTALL" = true ]; then
        print_info "Installing Java 21 (Temurin)..."
        
        case "$OS" in
            ubuntu|debian|google-cloud-shell)
                # Add Adoptium repository
                sudo apt-get install -y -qq wget apt-transport-https gnupg
                wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo apt-key add -
                echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | sudo tee /etc/apt/sources.list.d/adoptium.list
                sudo apt-get update -qq
                
                # Install Java 21
                sudo apt-get install -y -qq temurin-21-jdk
                ;;
            *)
                print_error "Cannot install Java on this OS"
                exit 1
                ;;
        esac
        
        # Verify Java installation
        if command_exists java; then
            JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | sed 's/^1\.//' | cut -d'.' -f1)
            print_success "Java $JAVA_VERSION installed successfully"
        else
            print_error "Java installation failed"
            exit 1
        fi
    fi
}

#############################################################
# PaperMC Download Functions (New PaperMC API)
#############################################################

# Fetch latest PaperMC build information
fetch_paper_build() {
    local version=$1
    print_info "Fetching PaperMC build information for version $version..."
    
    # PaperMC API v2 endpoint
    local API_URL="https://api.papermc.io/v2/projects/paper/versions/${version}"
    
    # Check if version exists
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL")
    if [ "$response" != "200" ]; then
        print_error "Minecraft version $version not found on PaperMC"
        print_info "Available versions can be found at: https://papermc.io/downloads"
        exit 1
    fi
    
    # Get latest build number
    local builds_response=$(curl -s "${API_URL}/builds")
    PAPER_BUILD=$(echo "$builds_response" | jq -r '.builds[-1].build')
    
    if [ -z "$PAPER_BUILD" ] || [ "$PAPER_BUILD" = "null" ]; then
        print_error "Could not find latest build for version $version"
        exit 1
    fi
    
    print_success "Found build #${PAPER_BUILD}"
    
    # Construct download URL
    local DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/${version}/builds/${PAPER_BUILD}/downloads/paper-${version}-${PAPER_BUILD}.jar"
    echo "$DOWNLOAD_URL"
}

# Download PaperMC jar
download_paper() {
    local version=$1
    local download_url=$(fetch_paper_build "$version")
    
    print_info "Downloading PaperMC server jar..."
    print_info "Download URL: $download_url"
    
    # Download the jar file
    if wget -q --show-progress -O "$SERVER_DIR/$PAPER_JAR" "$download_url"; then
        print_success "PaperMC jar downloaded successfully"
    else
        print_error "Failed to download PaperMC jar"
        print_info "Please check your internet connection and try again"
        exit 1
    fi
    
    # Verify downloaded file
    verify_jar
}

# Verify the downloaded file is a valid Java archive
verify_jar() {
    print_info "Verifying downloaded file..."
    
    local jar_file="$SERVER_DIR/$PAPER_JAR"
    
    # Check if file exists and has size
    if [ ! -f "$jar_file" ]; then
        print_error "PaperMC jar file not found"
        exit 1
    fi
    
    local file_size=$(stat -c%s "$jar_file" 2>/dev/null || stat -f%z "$jar_file" 2>/dev/null)
    if [ "$file_size" -lt 1000000 ]; then  # Less than 1MB is likely an error
        print_error "Downloaded file is too small ($file_size bytes) - likely corrupted"
        exit 1
    fi
    
    # Try to verify it's a valid zip/jar file
    if unzip -t "$jar_file" >/dev/null 2>&1; then
        print_success "Jar file verified successfully (Size: $file_size bytes)"
    else
        print_error "Downloaded file is not a valid Java archive"
        print_info "File path: $jar_file"
        exit 1
    fi
}

#############################################################
# Server Configuration
#############################################################

# Create server directory structure
create_server_structure() {
    print_info "Creating server directory structure..."
    
    # Create main directories
    mkdir -p "$SERVER_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$PLUGINS_DIR"
    mkdir -p "$CRASH_LOG_DIR"
    
    print_success "Directory structure created"
}

# Create eula.txt
create_eula() {
    print_info "Creating EULA agreement..."
    echo "eula=true" > "$EULA_FILE"
    print_success "EULA accepted"
}

# Configure server.properties
configure_server_properties() {
    print_info "Configuring server.properties..."
    
    # Create default server.properties if it doesn't exist
    if [ ! -f "$SERVER_PROPERTIES" ]; then
        # Generate default properties by running server once
        cd "$SERVER_DIR"
        java -jar "$PAPER_JAR" --initSettings --nogui > /dev/null 2>&1 &
        SERVER_PID=$!
        sleep 10
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
        cd - > /dev/null
    fi
    
    # Optimize server.properties
    if [ -f "$SERVER_PROPERTIES" ]; then
        # Configure view distance and simulation distance for performance
        sed -i 's/^view-distance=.*/view-distance=8/' "$SERVER_PROPERTIES"
        sed -i 's/^simulation-distance=.*/simulation-distance=5/' "$SERVER_PROPERTIES"
        sed -i 's/^max-players=.*/max-players=20/' "$SERVER_PROPERTIES"
        
        print_success "server.properties configured"
    fi
}

# Create start server script
create_start_script() {
    print_info "Creating server start script..."
    
    cat > "$START_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash

# Minecraft Server Start Script
# Configuration
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XMS="4G"
XMX="8G"
PAPER_JAR="paper.jar"
LOG_DIR="$SERVER_DIR/logs"
CRASH_LOG_DIR="$SERVER_DIR/crash-logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create directories if they don't exist
mkdir -p "$LOG_DIR"
mkdir -p "$CRASH_LOG_DIR"

# Change to server directory
cd "$SERVER_DIR"

# Check if server is already running
if screen -list | grep -q "minecraft"; then
    echo -e "${YELLOW}[WARNING] Server is already running!${NC}"
    exit 1
fi

# Start server function
start_server() {
    echo -e "${BLUE}[INFO] Starting Minecraft server...${NC}"
    echo -e "${BLUE}[INFO] RAM: ${XMS} - ${XMX}${NC}"
    
    # Create log filename with timestamp
    LOG_FILE="$LOG_DIR/server-$(date +%Y-%m-%d_%H-%M-%S).log"
    
    # Start server in screen session
    screen -dmS minecraft java \
        -Xms${XMS} \
        -Xmx${XMX} \
        -XX:+UseG1GC \
        -XX:+ParallelRefProcEnabled \
        -XX:MaxGCPauseMillis=200 \
        -XX:+UnlockExperimentalVMOptions \
        -XX:+DisableExplicitGC \
        -XX:+AlwaysPreTouch \
        -XX:G1NewSizePercent=30 \
        -XX:G1MaxNewSizePercent=40 \
        -XX:G1HeapRegionSize=8M \
        -XX:G1ReservePercent=20 \
        -XX:G1HeapWastePercent=5 \
        -XX:G1MixedGCCountTarget=4 \
        -XX:InitiatingHeapOccupancyPercent=15 \
        -XX:G1MixedGCLiveThresholdPercent=90 \
        -XX:G1RSetUpdatingPauseTimePercent=5 \
        -XX:SurvivorRatio=32 \
        -XX:+PerfDisableSharedMem \
        -XX:MaxTenuringThreshold=1 \
        -Dusing.aikars.flags=https://mcflags.emc.gs \
        -Daikars.new.flags=true \
        -jar ${PAPER_JAR} --nogui
    
    # Wait a moment for the server to start
    sleep 5
    
    # Check if server started successfully
    if screen -list | grep -q "minecraft"; then
        echo -e "${GREEN}[SUCCESS] Server started in screen session!${NC}"
        echo -e "${BLUE}[INFO] Use 'screen -r minecraft' to attach to console${NC}"
        echo -e "${BLUE}[INFO] Use 'CTRL+A then D' to detach from console${NC}"
    else
        echo -e "${RED}[ERROR] Failed to start server!${NC}"
        exit 1
    fi
}

# Auto-restart loop
if [ "${RESTART_ENABLED:-true}" = "true" ]; then
    while true; do
        start_server
        
        # Wait for server to stop
        while screen -list | grep -q "minecraft"; do
            sleep 10
        done
        
        # Log crash
        TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
        echo "Server crashed at $TIMESTAMP" >> "$CRASH_LOG_DIR/crashes.log"
        
        echo -e "${YELLOW}[WARNING] Server stopped! Restarting in 10 seconds...${NC}"
        echo -e "${YELLOW}[INFO] Press CTRL+C to cancel restart${NC}"
        sleep 10
    done
else
    start_server
fi
SCRIPTEOF
    
    chmod +x "$START_SCRIPT"
    print_success "Start script created: $START_SCRIPT"
}

# Create stop server script
create_stop_script() {
    print_info "Creating server stop script..."
    
    cat > "$STOP_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash

# Minecraft Server Stop Script
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if server is running
if ! screen -list | grep -q "minecraft"; then
    echo -e "${YELLOW}[WARNING] Server is not running!${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] Stopping Minecraft server safely...${NC}"

# Send stop command to server console
screen -S minecraft -p 0 -X stuff "say Server is stopping in 10 seconds...$(printf '\r')"
screen -S minecraft -p 0 -X stuff "save-all$(printf '\r')"
sleep 5
screen -S minecraft -p 0 -X stuff "say Server is stopping in 5 seconds...$(printf '\r')"
sleep 5
screen -S minecraft -p 0 -X stuff "stop$(printf '\r')"

# Wait for server to stop
echo -e "${BLUE}[INFO] Waiting for server to stop...${NC}"
while screen -list | grep -q "minecraft"; do
    sleep 1
done

echo -e "${GREEN}[SUCCESS] Server stopped successfully!${NC}"
SCRIPTEOF
    
    chmod +x "$STOP_SCRIPT"
    print_success "Stop script created: $STOP_SCRIPT"
}

# Create restart server script
create_restart_script() {
    print_info "Creating server restart script..."
    
    cat > "$RESTART_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash

# Minecraft Server Restart Script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[INFO] Restarting Minecraft server...${NC}"

# Stop server if running
if screen -list | grep -q "minecraft"; then
    echo -e "${BLUE}[INFO] Stopping running server...${NC}"
    "$SCRIPT_DIR/stop-server.sh"
    sleep 5
fi

# Start server
echo -e "${BLUE}[INFO] Starting server...${NC}"
"$SCRIPT_DIR/start-server.sh" &
SCRIPTEOF
    
    chmod +x "$RESTART_SCRIPT"
    print_success "Restart script created: $RESTART_SCRIPT"
}

# Create tunnel script
create_tunnel_script() {
    print_info "Creating tunnel script..."
    
    cat > "$TUNNEL_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash

# Minecraft Server Tunnel Script
# Supports Pinggy and LocalXpose

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_menu() {
    echo -e "${CYAN}╔════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      Minecraft Tunnel Setup        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Select a tunnel option:${NC}"
    echo -e "${GREEN}1)${NC} Pinggy TCP Tunnel (Free)"
    echo -e "${GREEN}2)${NC} LocalXpose Alternative"
    echo -e "${GREEN}3)${NC} Exit"
    echo ""
    read -p "Enter choice (1-3): " choice
    
    case $choice in
        1) setup_pinggy ;;
        2) setup_localxpose ;;
        3) exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; show_menu ;;
    esac
}

setup_pinggy() {
    echo -e "${BLUE}[INFO] Setting up Pinggy TCP Tunnel...${NC}"
    echo -e "${YELLOW}[INFO] Your server will be accessible via a public URL${NC}"
    echo -e "${BLUE}[INFO] Starting tunnel...${NC}"
    echo -e "${GREEN}[INFO] Share this URL with your friends to connect${NC}"
    echo ""
    
    # Start Pinggy tunnel
    ssh -p 443 -R0:localhost:25565 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 tcp@a.pinggy.io
}

setup_localxpose() {
    echo -e "${BLUE}[INFO] LocalXpose Alternative${NC}"
    echo -e "${YELLOW}[INFO] For a more stable tunnel, consider using LocalXpose${NC}"
    echo -e "${BLUE}[INFO] Visit: https://localxpose.io/${NC}"
    
    # Check if localxpose is installed
    if command -v loclx > /dev/null 2>&1; then
        echo -e "${GREEN}[INFO] LocalXpose detected. Starting tunnel...${NC}"
        loclx tunnel tcp --port 25565 --to localhost:25565
    else
        echo -e "${YELLOW}[INFO] LocalXpose not installed. You can install it with:${NC}"
        echo -e "${BLUE}curl -s https://localxpose.io/install | bash${NC}"
        
        read -p "Would you like to install LocalXpose now? (y/n): " install_choice
        if [ "$install_choice" = "y" ] || [ "$install_choice" = "Y" ]; then
            echo -e "${BLUE}[INFO] Installing LocalXpose...${NC}"
            curl -s https://localxpose.io/install | bash
            echo -e "${GREEN}[SUCCESS] LocalXpose installed!${NC}"
            echo -e "${BLUE}[INFO] Starting tunnel...${NC}"
            loclx tunnel tcp --port 25565 --to localhost:25565
        fi
    fi
}

# Run menu
show_menu
SCRIPTEOF
    
    chmod +x "$TUNNEL_SCRIPT"
    print_success "Tunnel script created: $TUNNEL_SCRIPT"
}

# Create backup script
create_backup_script() {
    print_info "Creating backup script..."
    
    cat > "$BACKUP_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash

# Minecraft Server Backup Script
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SERVER_DIR/backups"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Generate backup filename with timestamp
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/minecraft-backup-$TIMESTAMP.tar.gz"

echo -e "${BLUE}[INFO] Starting backup...${NC}"

# Save server if running
if screen -list | grep -q "minecraft"; then
    echo -e "${BLUE}[INFO] Saving server state...${NC}"
    screen -S minecraft -p 0 -X stuff "save-all$(printf '\r')"
    sleep 5
fi

# Create backup (excluding the jar file and backups directory)
echo -e "${BLUE}[INFO] Creating backup archive...${NC}"
tar -czf "$BACKUP_FILE" \
    --exclude="$SERVER_DIR/paper.jar" \
    --exclude="$SERVER_DIR/backups" \
    --exclude="$SERVER_DIR/logs" \
    --exclude="$SERVER_DIR/crash-logs" \
    -C "$SERVER_DIR" .

# Check if backup was successful
if [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}[SUCCESS] Backup created: $BACKUP_FILE${NC}"
    echo -e "${GREEN}[INFO] Backup size: $BACKUP_SIZE${NC}"
    
    # Clean up old backups (keep last 10)
    echo -e "${BLUE}[INFO] Cleaning old backups (keeping last 10)...${NC}"
    ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm
else
    echo -e "${RED}[ERROR] Backup failed!${NC}"
    exit 1
fi
SCRIPTEOF
    
    chmod +x "$BACKUP_SCRIPT"
    print_success "Backup script created: $BACKUP_SCRIPT"
}

# Configure auto-restart
configure_auto_restart() {
    print_info "Configuring auto-restart feature..."
    
    # Auto-restart is built into the start script
    # The server will automatically restart on crash
    # Crash logs will be saved to $CRASH_LOG_DIR
    
    # Create a systemd service for automatic startup on boot (optional)
    if [ "$OS" != "google-cloud-shell" ]; then
        cat > "$HOME/minecraft.service" << SERVICEEOF
[Unit]
Description=Minecraft Paper Server
After=network.target

[Service]
Type=forking
User=$USER
WorkingDirectory=$SERVER_DIR
ExecStart=/usr/bin/screen -dmS minecraft java -Xms${XMS} -Xmx${XMX} -jar ${PAPER_JAR} --nogui
ExecStop=/usr/bin/screen -S minecraft -p 0 -X stuff "stop$(printf '\r')"
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF
        
        print_info "Systemd service file created (optional): $HOME/minecraft.service"
        print_info "To install: sudo cp $HOME/minecraft.service /etc/systemd/system/ && sudo systemctl enable minecraft"
    fi
    
    print_success "Auto-restart configured"
}

# Plugin support
add_plugins() {
    print_info "Setting up plugin support..."
    
    # Create plugins directory
    mkdir -p "$PLUGINS_DIR"
    
    echo -e "${BLUE}[INFO] Plugin directory created: $PLUGINS_DIR${NC}"
    echo -e "${YELLOW}[INFO] You can add plugins by placing .jar files in the plugins directory${NC}"
    echo ""
    echo -e "${BLUE}Popular Plugins:${NC}"
    echo -e "${GREEN}• ViaVersion${NC} - Allow newer clients to connect"
    echo -e "  Download: https://www.spigotmc.org/resources/viaversion.19254/"
    echo -e "${GREEN}• ViaBackwards${NC} - Allow older clients to connect"
    echo -e "  Download: https://www.spigotmc.org/resources/viabackwards.27448/"
    echo -e "${GREEN}• EssentialsX${NC} - Essential commands for your server"
    echo -e "  Download: https://essentialsx.net/downloads.html"
    echo -e "${GREEN}• LuckPerms${NC} - Advanced permissions management"
    echo -e "  Download: https://luckperms.net/download"
    echo ""
    
    read -p "Would you like to download any plugins now? (y/n): " download_plugins
    if [ "$download_plugins" = "y" ] || [ "$download_plugins" = "Y" ]; then
        echo -e "${YELLOW}[INFO] Please download plugins manually and place them in:${NC}"
        echo -e "${BLUE}$PLUGINS_DIR${NC}"
        echo -e "${YELLOW}[INFO] Then restart the server to load them${NC}"
    fi
}

# Paper optimization suggestions
show_optimization_tips() {
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Paper Server Optimization Tips            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Using Aikar's flags for optimal JVM performance"
    echo -e "${GREEN}✓${NC} View distance set to 8 chunks"
    echo -e "${GREEN}✓${NC} Simulation distance set to 5 chunks"
    echo -e "${GREEN}✓${NC} Max players configured"
    echo ""
    echo -e "${YELLOW}Additional Recommendations:${NC}"
    echo -e "${BLUE}•${NC} Install ${GREEN}Chunky${NC} to pre-generate chunks"
    echo -e "${BLUE}•${NC} Use ${GREEN}Spark${NC} to monitor server performance"
    echo -e "${BLUE}•${NC} Configure ${GREEN}paper.yml${NC} for more optimizations"
    echo -e "${BLUE}•${NC} Set up regular backups with the backup script"
    echo -e "${BLUE}•${NC} Monitor server logs for issues"
    echo ""
}

#############################################################
# Installation Function
#############################################################

install_minecraft_server() {
    print_header "╔════════════════════════════════════╗"
    print_header "║  Minecraft Server Installation     ║"
    print_header "╚════════════════════════════════════╝"
    echo ""
    
    # Ask for Minecraft version
    echo -e "${BLUE}Enter Minecraft version (e.g., 1.21.7):${NC}"
    read -p "> " MINECRAFT_VERSION
    
    if [ -z "$MINECRAFT_VERSION" ]; then
        print_error "No version specified. Using default: 1.21.4"
        MINECRAFT_VERSION="1.21.4"
    fi
    
    # Install required packages
    install_packages
    
    # Install Java
    install_java
    
    # Create server directory structure
    create_server_structure
    
    # Download PaperMC
    download_paper "$MINECRAFT_VERSION"
    
    # Create EULA
    create_eula
    
    # Configure server properties
    configure_server_properties
    
    # Create all scripts
    create_start_script
    create_stop_script
    create_restart_script
    create_tunnel_script
    create_backup_script
    
    # Configure auto-restart
    configure_auto_restart
    
    # Plugin support
    add_plugins
    
    # Show optimization tips
    show_optimization_tips
    
    print_success "Minecraft Paper server installation complete!"
    echo ""
    print_info "Server directory: $SERVER_DIR"
    print_info "Use the menu to start/stop/manage your server"
    echo ""
}

#############################################################
# Server Management Functions
#############################################################

start_server_menu() {
    print_info "Starting Minecraft server..."
    "$START_SCRIPT" &
    sleep 2
    print_success "Server start initiated"
}

stop_server_menu() {
    print_info "Stopping Minecraft server..."
    "$STOP_SCRIPT"
}

restart_server_menu() {
    print_info "Restarting Minecraft server..."
    "$RESTART_SCRIPT"
}

view_console() {
    if screen -list | grep -q "minecraft"; then
        print_info "Attaching to Minecraft console..."
        print_info "To detach: Press CTRL+A then D"
        sleep 2
        screen -r minecraft
    else
        print_warning "Server is not running!"
        print_info "Start the server first to view the console"
    fi
}

install_tunnel_menu() {
    print_info "Launching tunnel setup..."
    "$TUNNEL_SCRIPT"
}

backup_server_menu() {
    print_info "Creating server backup..."
    "$BACKUP_SCRIPT"
}

#############################################################
# Main Menu
#############################################################

show_main_menu() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         Minecraft Paper Server Manager         ║${NC}"
    echo -e "${CYAN}║              Created with ❤️                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show server status
    if screen -list | grep -q "minecraft"; then
        echo -e "Server Status: ${GREEN}● RUNNING${NC}"
    else
        echo -e "Server Status: ${RED}● STOPPED${NC}"
    fi
    echo -e "Server Directory: ${BLUE}$SERVER_DIR${NC}"
    echo ""
    
    echo -e "${YELLOW}Main Menu:${NC}"
    echo -e "${GREEN}1)${NC} Install Minecraft Server"
    echo -e "${GREEN}2)${NC} Start Server"
    echo -e "${GREEN}3)${NC} Stop Server"
    echo -e "${GREEN}4)${NC} Restart Server"
    echo -e "${GREEN}5)${NC} View Console"
    echo -e "${GREEN}6)${NC} Setup Tunnel"
    echo -e "${GREEN}7)${NC} Backup Server"
    echo -e "${GREEN}8)${NC} Edit Server Properties"
    echo -e "${GREEN}9)${NC} Show Optimization Tips"
    echo -e "${GREEN}0)${NC} Exit"
    echo ""
    
    read -p "Enter your choice (0-9): " menu_choice
    
    case $menu_choice in
        1) 
            install_minecraft_server
            ;;
        2) 
            if [ -f "$START_SCRIPT" ]; then
                start_server_menu
            else
                print_error "Server not installed. Please install first."
                print_info "Run option 1 to install the server"
            fi
            ;;
        3) 
            if [ -f "$STOP_SCRIPT" ]; then
                stop_server_menu
            else
                print_error "Server not installed. Please install first."
            fi
            ;;
        4) 
            if [ -f "$RESTART_SCRIPT" ]; then
                restart_server_menu
            else
                print_error "Server not installed. Please install first."
            fi
            ;;
        5) 
            if [ -f "$START_SCRIPT" ]; then
                view_console
            else
                print_error "Server not installed. Please install first."
            fi
            ;;
        6) 
            if [ -f "$TUNNEL_SCRIPT" ]; then
                install_tunnel_menu
            else
                print_error "Server not installed. Please install first."
            fi
            ;;
        7) 
            if [ -f "$BACKUP_SCRIPT" ]; then
                backup_server_menu
            else
                print_error "Server not installed. Please install first."
            fi
            ;;
        8) 
            if [ -f "$SERVER_PROPERTIES" ]; then
                print_info "Opening server.properties with nano..."
                nano "$SERVER_PROPERTIES"
            else
                print_error "server.properties not found. Install server first."
            fi
            ;;
        9) 
            show_optimization_tips
            ;;
        0) 
            print_info "Goodbye!"
            exit 0
            ;;
        *) 
            print_error "Invalid choice. Please try again."
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

#############################################################
# Script Entry Point
#############################################################

# Display welcome message
clear
echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Minecraft Paper Server Setup Script       ║${NC}"
echo -e "${CYAN}║         Automated Installation & Management    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root is not recommended!"
    print_info "Consider running as a regular user"
    read -p "Continue anyway? (y/n): " root_choice
    if [ "$root_choice" != "y" ] && [ "$root_choice" != "Y" ]; then
        exit 0
    fi
fi

# Detect operating system
detect_os

# Check if server is already installed
if [ -f "$START_SCRIPT" ]; then    print_info "Existing Minecraft server installation detected"
    show_main_menu
else
    print_info "No existing server installation detected"
    echo ""
    echo -e "${YELLOW}What would you like to do?${NC}"
    echo -e "${GREEN}1)${NC} Install a new Minecraft server"
    echo -e "${GREEN}2)${NC} Exit"
    echo ""
    read -p "Enter choice (1-2): " initial_choice
    
    case $initial_choice in
        1) 
            install_minecraft_server
            echo ""
            read -p "Press Enter to open main menu..."
            show_main_menu
            ;;
        2) 
            print_info "Goodbye!"
            exit 0
            ;;
        *) 
            print_error "Invalid choice"
            exit 1
            ;;
    esac
fi
