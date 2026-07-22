#!/bin/bash
################################################################################
#                                                                              #
#  Minecraft Paper Server - One-Click Installer                                #
#  Works on: Google Cloud Shell, Ubuntu 22.04/24.04, Debian 11/12              #
#                                                                              #
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Variables
SERVER_DIR="$HOME/minecraft-server"
RAM_MIN="2G"
RAM_MAX="4G"

# Print with timestamp
log() {
    echo -e "${2}[$(date +'%H:%M:%S')] ${1}${NC}"
}

# Banner
clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║     Minecraft Paper Server - CodingBoyz      ║"
echo "║     Cloud Shell & VPS Compatible                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check environment
log "Checking system..." "$BLUE"
if [ -n "$CLOUD_SHELL" ] || [ -d "/google" ]; then
    log "✓ Google Cloud Shell detected" "$GREEN"
    log "⚠ Limited to 2GB RAM for stability" "$YELLOW"
    RAM_MIN="1G"
    RAM_MAX="2G"
else
    log "✓ VPS/Server detected" "$GREEN"
fi

# Install dependencies
log "Installing required packages..." "$BLUE"
sudo apt-get update -qq 2>/dev/null
sudo apt-get install -y -qq openjdk-21-jdk screen wget curl jq unzip 2>/dev/null

if command -v java >/dev/null; then
    log "✓ Java installed: $(java -version 2>&1 | head -1)" "$GREEN"
else
    log "✗ Java installation failed" "$RED"
    exit 1
fi

# Create server directory
mkdir -p "$SERVER_DIR"
cd "$SERVER_DIR"

# Get available Paper versions
log "Fetching available PaperMC versions..." "$BLUE"
AVAILABLE_VERSIONS=$(curl -s https://api.papermc.io/v2/projects/paper)

# Try multiple versions (latest first)
VERSIONS_TO_TRY=("1.21.4" "1.21.3" "1.21.1" "1.21" "1.20.6" "1.20.4" "1.20.2" "1.20.1" "1.20")

SELECTED_VERSION=""
for VERSION in "${VERSIONS_TO_TRY[@]}"; do
    if echo "$AVAILABLE_VERSIONS" | jq -e ".versions | index(\"$VERSION\")" >/dev/null 2>&1; then
        SELECTED_VERSION="$VERSION"
        break
    fi
done

if [ -z "$SELECTED_VERSION" ]; then
    log "No compatible version found. Checking all versions..." "$YELLOW"
    # Get the latest stable version
    LATEST_STABLE=$(echo "$AVAILABLE_VERSIONS" | jq -r '.versions[-1]')
    SELECTED_VERSION="$LATEST_STABLE"
fi

log "✓ Selected version: $SELECTED_VERSION" "$GREEN"

# Get latest build
log "Fetching latest build for $SELECTED_VERSION..." "$BLUE"
BUILDS_RESPONSE=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$SELECTED_VERSION/builds")
LATEST_BUILD=$(echo "$BUILDS_RESPONSE" | jq -r '.builds[-1].build')

if [ -z "$LATEST_BUILD" ] || [ "$LATEST_BUILD" == "null" ]; then
    log "✗ Failed to get build number" "$RED"
    exit 1
fi

log "✓ Build #$LATEST_BUILD found" "$GREEN"

# Download PaperMC
DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$SELECTED_VERSION/builds/$LATEST_BUILD/downloads/paper-$SELECTED_VERSION-$LATEST_BUILD.jar"

log "Downloading PaperMC server..." "$BLUE"
if wget -q --show-progress -O paper.jar "$DOWNLOAD_URL" 2>/dev/null; then
    if [ -f paper.jar ] && [ $(stat -c%s paper.jar 2>/dev/null || echo 0) -gt 1000000 ]; then
        log "✓ Downloaded successfully ($(du -h paper.jar | cut -f1))" "$GREEN"
    else
        log "✗ Download failed or file too small" "$RED"
        exit 1
    fi
else
    log "✗ Download failed. Trying direct download..." "$YELLOW"
    curl -L -o paper.jar "$DOWNLOAD_URL"
    if [ ! -f paper.jar ] || [ $(stat -c%s paper.jar 2>/dev/null || echo 0) -lt 1000000 ]; then
        log "✗ All download attempts failed" "$RED"
        exit 1
    fi
fi

# Accept EULA
log "Accepting Minecraft EULA..." "$BLUE"
echo "eula=true" > eula.txt
log "✓ EULA accepted" "$GREEN"

# Server properties
log "Creating server.properties..." "$BLUE"
cat > server.properties << EOF
enable-jmx-monitoring=false
rcon.port=25575
gamemode=survival
enable-command-block=false
enable-query=false
generator-settings={}
level-name=world
motd=Paper Server on Cloud
query.port=25565
pvp=true
generate-structures=true
difficulty=easy
max-players=20
network-compression-threshold=256
max-tick-time=60000
use-native-transport=true
online-mode=true
allow-flight=false
view-distance=8
simulation-distance=5
spawn-protection=16
server-port=25565
enable-rcon=false
EOF
log "✓ server.properties created" "$GREEN"

# Start script
log "Creating start script..." "$BLUE"
cat > start.sh << SCRIPTEOF
#!/bin/bash
cd "\$(dirname "\$0")"
echo "Starting Minecraft Server v$SELECTED_VERSION..."
echo "RAM: $RAM_MIN - $RAM_MAX"
screen -dmS minecraft java -Xms$RAM_MIN -Xmx$RAM_MAX -XX:+UseG1GC -jar paper.jar --nogui
echo "✓ Server started in background"
echo "To view console: screen -r minecraft"
echo "To detach: CTRL+A then D"
SCRIPTEOF
chmod +x start.sh

# Stop script
cat > stop.sh << 'SCRIPTEOF'
#!/bin/bash
if screen -list | grep -q "minecraft"; then
    echo "Stopping server..."
    screen -S minecraft -p 0 -X stuff "say Server stopping in 10s...\r"
    sleep 5
    screen -S minecraft -p 0 -X stuff "save-all\r"
    sleep 5
    screen -S minecraft -p 0 -X stuff "stop\r"
    echo "✓ Server stopped"
else
    echo "✗ Server not running"
fi
SCRIPTEOF
chmod +x stop.sh

# Backup script
cat > backup.sh << 'SCRIPTEOF'
#!/bin/bash
DIR="$(dirname "$0")/backups"
mkdir -p "$DIR"
FILE="$DIR/backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$FILE" -C "$(dirname "$0")" world world_nether world_the_end 2>/dev/null
echo "✓ Backup saved: $FILE"
SCRIPTEOF
chmod +x backup.sh

# Final message
clear
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}   ✅ Server Installed Successfully!${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}📁 Location:${NC} $SERVER_DIR"
echo -e "${YELLOW}🎮 Version:${NC}  $SELECTED_VERSION"
echo -e "${YELLOW}💾 RAM:${NC}      $RAM_MIN - $RAM_MAX"
echo ""
echo -e "${CYAN}Commands:${NC}"
echo -e "  ${GREEN}Start:${NC}    bash $SERVER_DIR/start.sh"
echo -e "  ${GREEN}Stop:${NC}     bash $SERVER_DIR/stop.sh"
echo -e "  ${GREEN}Console:${NC}  screen -r minecraft"
echo -e "  ${GREEN}Backup:${NC}   bash $SERVER_DIR/backup.sh"
echo ""
read -p "Start server now? (y/n): " start_choice
if [ "$start_choice" = "y" ] || [ "$start_choice" = "Y" ]; then
    cd "$SERVER_DIR" && bash start.sh
    sleep 2
    echo ""
    echo -e "${GREEN}Server is starting! Use 'screen -r minecraft' to view${NC}"
fi
