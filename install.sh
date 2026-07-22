#!/bin/bash
################################################################################
#                                                                              #
#  Minecraft Paper Server - Fixed Installer                                    #
#  Works on: Google Cloud Shell, Ubuntu, Debian                                #
#                                                                              #
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
SERVER_DIR="$HOME/minecraft-server"
RAM_MIN="2G"
RAM_MAX="4G"

# Log function
log() {
    echo -e "${2}[$(date +'%H:%M:%S')] ${1}${NC}"
}

# Banner
clear
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Minecraft Paper Server Installer v2.0   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""

# Check environment
if [ -d "/google" ] || [ -n "$CLOUD_SHELL" ]; then
    log "Google Cloud Shell detected" "$GREEN"
    RAM_MIN="1G"
    RAM_MAX="2G"
fi

# Install Java
log "Installing Java 21..." "$BLUE"
sudo apt-get update -qq 2>/dev/null
sudo apt-get install -y -qq openjdk-21-jdk screen wget curl jq 2>/dev/null

if ! command -v java >/dev/null; then
    log "Java installation failed!" "$RED"
    exit 1
fi
log "✓ Java installed" "$GREEN"

# Create server directory
mkdir -p "$SERVER_DIR"
cd "$SERVER_DIR"

# Get PaperMC versions directly
log "Getting available versions..." "$BLUE"
PAPER_API="https://api.papermc.io/v2/projects/paper"
VERSION_LIST=$(curl -s "$PAPER_API" | jq -r '.versions[]' 2>/dev/null)

if [ -z "$VERSION_LIST" ]; then
    log "Cannot fetch PaperMC API. Using known working version..." "$YELLOW"
    # Fallback to known working versions
    VERSIONS=("1.21" "1.20.6" "1.20.4" "1.20.2" "1.20.1" "1.20" "1.19.4" "1.19.2" "1.18.2")
    
    for ver in "${VERSIONS[@]}"; do
        log "Trying version $ver..." "$BLUE"
        RESPONSE=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$ver")
        if echo "$RESPONSE" | grep -q "builds"; then
            SELECTED_VERSION="$ver"
            log "✓ Found working version: $ver" "$GREEN"
            break
        fi
    done
else
    # Get the latest version from the list
    SELECTED_VERSION=$(echo "$VERSION_LIST" | tail -1)
    log "✓ Latest version: $SELECTED_VERSION" "$GREEN"
fi

if [ -z "$SELECTED_VERSION" ]; then
    log "No version found! Using 1.20.4 as fallback" "$YELLOW"
    SELECTED_VERSION="1.20.4"
fi

# Get build number
log "Fetching build information..." "$BLUE"
BUILD_INFO=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$SELECTED_VERSION/builds")

if [ -z "$BUILD_INFO" ]; then
    log "Failed to get build info. Trying alternative API..." "$YELLOW"
    
    # Alternative: try direct download with known URL pattern
    # For PaperMC, try builds from 100 onwards
    for build in $(seq 500 -1 1); do
        DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$SELECTED_VERSION/builds/$build/downloads/paper-$SELECTED_VERSION-$build.jar"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$DOWNLOAD_URL")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            LATEST_BUILD=$build
            log "✓ Found build #$build" "$GREEN"
            break
        fi
    done
fi

if [ -z "$LATEST_BUILD" ]; then
    LATEST_BUILD=$(echo "$BUILD_INFO" | jq -r '.builds[-1].build' 2>/dev/null)
    
    if [ -z "$LATEST_BUILD" ] || [ "$LATEST_BUILD" = "null" ]; then
        log "Cannot determine build. Using direct download link..." "$YELLOW"
        # Direct download URL pattern for PaperMC
        LATEST_BUILD=$(curl -s "https://papermc.io/api/v2/projects/paper/versions/$SELECTED_VERSION" | jq -r '.builds[-1]' 2>/dev/null)
    fi
fi

if [ -z "$LATEST_BUILD" ] || [ "$LATEST_BUILD" = "null" ]; then
    log "Using alternative download method..." "$YELLOW"
    # Last resort: download from papermc.io directly
    DOWNLOAD_URL="https://papermc.io/api/v3/projects/paper/versions/$SELECTED_VERSION/builds/latest/downloads/paper-$SELECTED_VERSION-latest.jar"
else
    DOWNLOAD_URL="https://api.papermc.io/v3/projects/paper/versions/$SELECTED_VERSION/builds/$LATEST_BUILD/downloads/paper-$SELECTED_VERSION-$LATEST_BUILD.jar"
fi

log "Downloading PaperMC..." "$BLUE"
log "Version: $SELECTED_VERSION" "$CYAN"
log "Build: ${LATEST_BUILD:-latest}" "$CYAN"
log "URL: $DOWNLOAD_URL" "$CYAN"
echo ""

# Download with progress
if wget --show-progress -O paper.jar "$DOWNLOAD_URL" 2>&1; then
    FILESIZE=$(stat -c%s paper.jar 2>/dev/null || echo 0)
    if [ "$FILESIZE" -gt 1000000 ]; then
        log "✓ Downloaded successfully ($(du -h paper.jar | cut -f1))" "$GREEN"
    else
        log "✗ File too small, trying curl..." "$YELLOW"
        curl -L -o paper.jar "$DOWNLOAD_URL"
    fi
else
    log "wget failed, trying curl..." "$YELLOW"
    curl -L -o paper.jar "$DOWNLOAD_URL"
fi

# Final verification
if [ ! -f paper.jar ] || [ $(stat -c%s paper.jar 2>/dev/null || echo 0) -lt 500000 ]; then
    log "✗ All download methods failed!" "$RED"
    log "Please check your internet connection" "$RED"
    log "Try manually: https://papermc.io/downloads" "$YELLOW"
    exit 1
fi

# Accept EULA
echo "eula=true" > eula.txt
log "✓ EULA accepted" "$GREEN"

# Create server.properties
cat > server.properties << EOF
server-port=25565
motd=PaperMC Server
gamemode=survival
difficulty=easy
max-players=20
view-distance=8
simulation-distance=5
online-mode=true
pvp=true
allow-flight=false
EOF
log "✓ Configuration created" "$GREEN"

# Create start script
cat > start.sh << SCRIPTEOF
#!/bin/bash
cd "\$(dirname "\$0")"
echo "════════════════════════════════"
echo "  Starting Minecraft Server"
echo "  Version: $SELECTED_VERSION"
echo "  RAM: $RAM_MIN - $RAM_MAX"
echo "════════════════════════════════"
screen -dmS minecraft java -Xms$RAM_MIN -Xmx$RAM_MAX -XX:+UseG1GC -jar paper.jar --nogui
echo ""
echo "✓ Server starting..."
echo "View console: screen -r minecraft"
echo "Detach: CTRL+A then D"
SCRIPTEOF
chmod +x start.sh

# Create stop script  
cat > stop.sh << 'STOPEOF'
#!/bin/bash
if screen -list | grep -q "minecraft"; then
    echo "Stopping server..."
    screen -S minecraft -p 0 -X stuff "say Server stopping!\r"
    screen -S minecraft -p 0 -X stuff "save-all\r"
    sleep 3
    screen -S minecraft -p 0 -X stuff "stop\r"
    echo "✓ Server stopped"
else
    echo "Server not running"
fi
STOPEOF
chmod +x stop.sh

# Success message
clear
echo -e "${GREEN}╔══════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ Installation Complete!      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Server Details:${NC}"
echo -e "  📁 Location: ${YELLOW}$SERVER_DIR${NC}"
echo -e "  🎮 Version:  ${YELLOW}$SELECTED_VERSION${NC}"
echo -e "  💾 RAM:      ${YELLOW}$RAM_MIN - $RAM_MAX${NC}"
echo ""
echo -e "${CYAN}Quick Commands:${NC}"
echo -e "  ${GREEN}Start:${NC}    bash ~/minecraft-server/start.sh"
echo -e "  ${GREEN}Stop:${NC}     bash ~/minecraft-server/stop.sh"
echo -e "  ${GREEN}Console:${NC}  screen -r minecraft"
echo ""

read -p "Start server now? (y/n): " answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    bash start.sh
    echo ""
    echo -e "${GREEN}Server is starting in background${NC}"
    echo -e "${YELLOW}Use: screen -r minecraft${NC}"
fi
