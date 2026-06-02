#!/bin/bash

# ==============================================================================
# Minecraft & Webmin Debian Installer Script
# ==============================================================================
# Designed for Debian VMs running on Proxmox.
# Supports Vanilla Java, Bedrock, and Forge Minecraft Servers.
# Configures a template systemd service with instance overrides.
# ==============================================================================

# Set strict error handling where appropriate, but allow manual error handling in logic
set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0;0m' # No Color

# Helper for cleanup on exit
cleanup() {
    local exit_code=$?
    trap - SIGINT SIGTERM ERR EXIT
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${RED}Installer failed with exit code $exit_code.${NC}"
    fi
    exit $exit_code
}

# Print banner
echo -e "${CYAN}"
echo "=========================================================="
echo "    MINECRAFT & WEBMIN PROXMOX DEBIAN INSTALLER           "
echo "=========================================================="
echo -e "${NC}"

# 1. Root Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root.${NC}"
   exit 1
fi

# 2. Dependency Check & Installation
echo -e "${BLUE}[*] Checking and installing base dependencies...${NC}"
apt-get update
apt-get install -y curl wget jq gnupg screen unzip lsb-release unattended-upgrades qemu-guest-agent

# 3. Create minecraft system user
if ! id "minecraft" &>/dev/null; then
    echo -e "${BLUE}[*] Creating system user 'minecraft'...${NC}"
    useradd -r -m -U -d /opt/minecraft -s /bin/bash minecraft
else
    echo -e "${GREEN}[+] System user 'minecraft' already exists.${NC}"
fi

# Ensure layout directories exist
mkdir -p /opt/minecraft/instances

# 4. User Inputs
echo -e "\n${YELLOW}--- Minecraft Installation Selection ---${NC}"
echo "1) Minecraft Java Edition (Vanilla)"
echo "2) Minecraft Bedrock Edition (Dedicated Server)"
echo "3) Minecraft Forge (Modded)"
read -rp "Select server type [1-3]: " TYPE_SEL

case "$TYPE_SEL" in
    1) TYPE="java" ;;
    2) TYPE="bedrock" ;;
    3) TYPE="forge" ;;
    *) echo -e "${RED}Invalid selection.${NC}"; exit 1 ;;
esac

read -rp "Enter Instance Name (e.g. server1): " INSTANCE_NAME
# Validate instance name
if [[ ! "$INSTANCE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}Invalid instance name. Use alphanumeric characters, dashes, or underscores only.${NC}"
    exit 1
fi

INSTANCE_DIR="/opt/minecraft/instances/$INSTANCE_NAME"
if [ -d "$INSTANCE_DIR" ]; then
    echo -e "${YELLOW}Warning: Directory $INSTANCE_DIR already exists!${NC}"
    read -rp "Do you want to overwrite it? (y/N): " OVERWRITE_SEL
    if [[ ! "$OVERWRITE_SEL" =~ ^[yY]$ ]]; then
        echo "Installation aborted."
        exit 1
    fi
fi

# Version prompt
if [ "$TYPE" = "bedrock" ]; then
    read -rp "Enter Bedrock version (default: latest): " MC_VERSION
    [ -z "$MC_VERSION" ] && MC_VERSION="latest"
else
    read -rp "Enter Minecraft version (e.g. 1.20.4): " MC_VERSION
    if [ -z "$MC_VERSION" ]; then
        echo -e "${RED}Minecraft version is required for Java/Forge.${NC}"
        exit 1
    fi
fi

# 5. Determine Java Version (only for Java / Forge)
JAVA_VERSION=""
if [ "$TYPE" = "java" ] || [ "$TYPE" = "forge" ]; then
    echo -e "${BLUE}[*] Determining correct Temurin Java version...${NC}"
    
    # Parse version components
    minor=$(echo "$MC_VERSION" | cut -d. -f2)
    patch=$(echo "$MC_VERSION" | cut -d. -f3)
    [ -z "$patch" ] && patch=0
    
    if ! [[ "$minor" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}Could not parse minor version from '$MC_VERSION'. Defaulting to Java 21.${NC}"
        JAVA_VERSION="21"
    elif [ "$minor" -le 12 ]; then
        JAVA_VERSION="8"
    elif [ "$minor" -le 16 ]; then
        JAVA_VERSION="11"
    elif [ "$minor" -eq 17 ]; then
        JAVA_VERSION="17" # Java 17 is standard and fully backward compatible for 1.17
    elif [ "$minor" -eq 18 ] || [ "$minor" -eq 19 ]; then
        JAVA_VERSION="17"
    elif [ "$minor" -eq 20 ]; then
        if [ "$patch" -ge 5 ]; then
            JAVA_VERSION="21"
        else
            JAVA_VERSION="17"
        fi
    else
        JAVA_VERSION="21"
    fi
    echo -e "${GREEN}[+] Selected Temurin Java Version: $JAVA_VERSION${NC}"
fi

# 6. Install Temurin JDK
if [ -n "$JAVA_VERSION" ]; then
    echo -e "${BLUE}[*] Setting up Adoptium Temurin GPG key and APT repository...${NC}"
    mkdir -p /etc/apt/keyrings
    wget -O - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/keyrings/adoptium.gpg > /dev/null
    
    # Resolve Debian codename
    if command -v lsb_release >/dev/null 2>&1; then
        CODENAME=$(lsb_release -cs)
    else
        CODENAME=$(grep -oP '(?<=VERSION_CODENAME=)[a-z]+' /etc/os-release || true)
        if [ -z "$CODENAME" ]; then
            CODENAME=$(grep -oP '(?<=VERSION_CODENAME=")[a-z]+(?=")' /etc/os-release || true)
        fi
    fi
    [ -z "$CODENAME" ] && CODENAME="bookworm"
    
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${CODENAME} main" | tee /etc/apt/sources.list.d/adoptium.list
    apt-get update
    
    echo -e "${BLUE}[*] Installing temurin-${JAVA_VERSION}-jdk...${NC}"
    apt-get install -y "temurin-${JAVA_VERSION}-jdk"
    echo -e "${GREEN}[+] Java installation complete.${NC}"
fi

# 7. Install Webmin
echo -e "${BLUE}[*] Setting up Webmin repository...${NC}"
if ! dpkg -s webmin >/dev/null 2>&1; then
    curl -o /tmp/setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
    sh /tmp/setup-repos.sh -f
    apt-get install -y webmin
    echo -e "${GREEN}[+] Webmin installed successfully.${NC}"
else
    echo -e "${GREEN}[+] Webmin is already installed.${NC}"
fi

# 8. Create Instance Directory
mkdir -p "$INSTANCE_DIR"

# 9. Download Minecraft Files
if [ "$TYPE" = "java" ]; then
    echo -e "${BLUE}[*] Fetching Minecraft Java Version Manifest...${NC}"
    VERSION_URL=$(curl -s "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json" | jq -r --arg ver "$MC_VERSION" '.versions[] | select(.id == $ver) | .url')
    
    if [ -z "$VERSION_URL" ] || [ "$VERSION_URL" = "null" ]; then
        echo -e "${RED}Error: Version $MC_VERSION was not found in the Mojang manifest.${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}[*] Fetching server download URL...${NC}"
    DOWNLOAD_URL=$(curl -s "$VERSION_URL" | jq -r '.downloads.server.url')
    
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        echo -e "${RED}Error: Server download URL not found for version $MC_VERSION.${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}[*] Downloading Minecraft Server Jar...${NC}"
    wget -q --show-progress "$DOWNLOAD_URL" -O "$INSTANCE_DIR/minecraft_server.jar"
    
elif [ "$TYPE" = "bedrock" ]; then
    DOWNLOAD_URL=""
    if [ "$MC_VERSION" = "latest" ]; then
        echo -e "${BLUE}[*] Fetching latest Bedrock Dedicated Server URL...${NC}"
        DOWNLOAD_URL=$(curl -s "https://net-secondary.web.minecraft-services.net/api/v1.0/download/links" | jq -r '.result.links[] | select(.downloadType=="serverBedrockLinux") | .downloadUrl')
    else
        DOWNLOAD_URL="https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-${MC_VERSION}.zip"
    fi
    
    echo -e "${BLUE}[*] Downloading Bedrock Server Zip...${NC}"
    # Bedrock files check User-Agent and redirect, download to tmp
    if ! wget -U "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BEDROCK-UPDATER" -q --show-progress "$DOWNLOAD_URL" -O /tmp/bedrock.zip; then
        echo -e "${YELLOW}Warning: Official download failed (version may not exist on Mojang's servers).${NC}"
        read -rp "Please enter a custom URL to download the Bedrock Server Zip (or leave empty to cancel): " CUSTOM_URL
        if [ -z "$CUSTOM_URL" ]; then
            echo "Installation aborted."
            exit 1
        fi
        wget -q --show-progress "$CUSTOM_URL" -O /tmp/bedrock.zip
    fi
    
    echo -e "${BLUE}[*] Extracting Bedrock Server...${NC}"
    unzip -q -o /tmp/bedrock.zip -d "$INSTANCE_DIR"
    rm -f /tmp/bedrock.zip

elif [ "$TYPE" = "forge" ]; then
    echo -e "${BLUE}[*] Fetching Forge Promotions Manifest...${NC}"
    # Use Mozilla User-Agent to bypass Cloudflare/scraping checks
    PROMO_JSON=$(curl -s -H "User-Agent: Mozilla/5.0" "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")
    
    FORGE_VERSION=""
    # Check recommended, then latest
    RECOMMENDED_KEY="${MC_VERSION}-recommended"
    LATEST_KEY="${MC_VERSION}-latest"
    
    FORGE_VERSION=$(echo "$PROMO_JSON" | jq -r --arg key "$RECOMMENDED_KEY" '.promos[$key] // empty')
    if [ -z "$FORGE_VERSION" ] || [ "$FORGE_VERSION" = "null" ]; then
        FORGE_VERSION=$(echo "$PROMO_JSON" | jq -r --arg key "$LATEST_KEY" '.promos[$key] // empty')
    fi
    
    if [ -z "$FORGE_VERSION" ] || [ "$FORGE_VERSION" = "null" ]; then
        echo -e "${YELLOW}Could not find an automatic Forge version for Minecraft $MC_VERSION.${NC}"
        read -rp "Please enter the specific Forge version string (e.g. 49.2.7): " FORGE_VERSION
        if [ -z "$FORGE_VERSION" ]; then
            echo "Installation aborted."
            exit 1
        fi
    else
        echo -e "${GREEN}[+] Found Forge Version: $FORGE_VERSION${NC}"
    fi
    
    FORGE_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}-${FORGE_VERSION}/forge-${MC_VERSION}-${FORGE_VERSION}-installer.jar"
    echo -e "${BLUE}[*] Downloading Forge Installer...${NC}"
    
    if ! wget -q --show-progress "$FORGE_URL" -O /tmp/forge-installer.jar; then
        echo -e "${YELLOW}Warning: Official Forge installer download failed.${NC}"
        read -rp "Please enter a custom URL to the Forge Installer Jar (or leave empty to cancel): " CUSTOM_URL
        if [ -z "$CUSTOM_URL" ]; then
            echo "Installation aborted."
            exit 1
        fi
        wget -q --show-progress "$CUSTOM_URL" -O /tmp/forge-installer.jar
    fi
    
    echo -e "${BLUE}[*] Running Forge Server Installer (this may take a few minutes)...${NC}"
    # Run installer inside the instance directory
    cd "$INSTANCE_DIR"
    java -jar /tmp/forge-installer.jar --installServer > /dev/null
    rm -f /tmp/forge-installer.jar
    
    # Check if modern Forge (generates run.sh) or older Forge (generates jar)
    if [ -f "$INSTANCE_DIR/run.sh" ]; then
        echo -e "${GREEN}[+] Modern Forge server installed.${NC}"
        chmod +x "$INSTANCE_DIR/run.sh"
        # Edit user_jvm_args.txt to set Xmx4G
        if [ -f "$INSTANCE_DIR/user_jvm_args.txt" ]; then
            # Remove any existing uncommented Xmx lines
            sed -i '/^-Xmx/d' "$INSTANCE_DIR/user_jvm_args.txt"
            echo "-Xmx4G" >> "$INSTANCE_DIR/user_jvm_args.txt"
        fi
    else
        # Older Forge. Try to find the forge jar and rename/symlink it to minecraft_server.jar
        FORGE_JAR=$(find "$INSTANCE_DIR" -name "forge-*.jar" ! -name "*installer*" ! -name "*universal*" | head -n 1)
        if [ -z "$FORGE_JAR" ]; then
            FORGE_JAR=$(find "$INSTANCE_DIR" -name "forge-*.jar" ! -name "*installer*" | head -n 1)
        fi
        
        if [ -n "$FORGE_JAR" ]; then
            echo -e "${GREEN}[+] Found Forge server jar: $(basename "$FORGE_JAR")${NC}"
            mv "$FORGE_JAR" "$INSTANCE_DIR/minecraft_server.jar"
        else
            echo -e "${YELLOW}Warning: Could not find the generated Forge jar file. You may need to rename it manually to minecraft_server.jar.${NC}"
        fi
    fi
    cd - > /dev/null
fi

# 10. Configure EULA (only for Java / Forge)
if [ "$TYPE" = "java" ] || [ "$TYPE" = "forge" ]; then
    echo "eula=true" > "$INSTANCE_DIR/eula.txt"
    echo -e "${GREEN}[+] Accepted Minecraft EULA (eula=true).${NC}"
fi

# 11. Systemd Service Configuration
echo -e "${BLUE}[*] Configuring Systemd Service Templates...${NC}"

# Create the master minecraft@.service template
cat << 'EOF' > /etc/systemd/system/minecraft@.service
[Unit]
Description=Minecraft Server: %i
After=network.target

[Service]
WorkingDirectory=/opt/minecraft/instances/%i

User=minecraft
Group=minecraft

Restart=always

ExecStart=/usr/bin/screen -DmS mc-%i /usr/bin/java -Xmx4G -jar minecraft_server.jar nogui

ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "say SERVER SHUTTING DOWN IN 15 SECONDS..."\015'
ExecStop=/bin/sleep 5
ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "say SERVER SHUTTING DOWN IN 10 SECONDS..."\015'
ExecStop=/bin/sleep 5
ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "say SERVER SHUTTING DOWN IN 5 SECONDS..."\015'
ExecStop=/bin/sleep 5
ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "save-all"\015'
ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "stop"\015'

[Install]
WantedBy=multi-user.target
EOF

# Set up specific instance overrides if needed
OVERRIDE_DIR="/etc/systemd/system/minecraft@${INSTANCE_NAME}.service.d"

if [ "$TYPE" = "bedrock" ]; then
    echo -e "${BLUE}[*] Setting up Bedrock Systemd Overrides...${NC}"
    mkdir -p "$OVERRIDE_DIR"
    cat << EOF > "$OVERRIDE_DIR/override.conf"
[Service]
ExecStart=
ExecStart=/usr/bin/screen -DmS mc-%i /bin/bash -c "LD_LIBRARY_PATH=. ./bedrock_server"
ExecStop=
ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "say SERVER SHUTTING DOWN IN 15 SECONDS..."\015'
ExecStop=/bin/sleep 5
ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "say SERVER SHUTTING DOWN IN 10 SECONDS..."\015'
ExecStop=/bin/sleep 5
ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "say SERVER SHUTTING DOWN IN 5 SECONDS..."\015'
ExecStop=/bin/sleep 5
ExecStop=/usr/bin/screen -p 0 -S mc-%i -X eval 'stuff "stop"\015'
EOF

elif [ "$TYPE" = "forge" ] && [ -f "$INSTANCE_DIR/run.sh" ]; then
    echo -e "${BLUE}[*] Setting up Forge Systemd Overrides (running via run.sh)...${NC}"
    mkdir -p "$OVERRIDE_DIR"
    cat << EOF > "$OVERRIDE_DIR/override.conf"
[Service]
ExecStart=
ExecStart=/usr/bin/screen -DmS mc-%i /bin/bash run.sh
EOF
fi

# Reload systemd configuration
systemctl daemon-reload

# 12. Adjust Permissions
echo -e "${BLUE}[*] Setting correct folder permissions...${NC}"
chown -R minecraft:minecraft /opt/minecraft

# 13. Enable and Start Service
echo -e "\n${YELLOW}--- Service Startup ---${NC}"
read -rp "Do you want to enable and start this server instance immediately? (Y/n): " START_SEL
[ -z "$START_SEL" ] && START_SEL="y"

if [[ "$START_SEL" =~ ^[yY]$ ]]; then
    echo -e "${BLUE}[*] Enabling and starting minecraft@${INSTANCE_NAME}...${NC}"
    systemctl enable "minecraft@${INSTANCE_NAME}"
    systemctl start "minecraft@${INSTANCE_NAME}"
    
    echo -e "${GREEN}[+] Instance started. You can attach to the console with: sudo -u minecraft screen -r mc-${INSTANCE_NAME}${NC}"
else
    echo -e "${BLUE}[*] Enabling service (not starting)...${NC}"
    systemctl enable "minecraft@${INSTANCE_NAME}"
    echo -e "${GREEN}[+] Enabled. Start manually with: systemctl start minecraft@${INSTANCE_NAME}${NC}"
fi

# Clear active traps before returning success
trap - SIGINT SIGTERM ERR EXIT

echo -e "\n${GREEN}=========================================================="
echo "    INSTALLATION COMPLETE!                                "
echo "=========================================================="
echo -e "Instance Name:  $INSTANCE_NAME"
echo -e "Server Type:    $TYPE"
echo -e "Directory:      $INSTANCE_DIR"
echo -e "Systemd Unit:   minecraft@$INSTANCE_NAME"
echo -e "Console access: sudo -u minecraft screen -r mc-$INSTANCE_NAME"
echo -e "Webmin Access:  https://<Server_IP>:10000/"
echo -e "==========================================================${NC}"
