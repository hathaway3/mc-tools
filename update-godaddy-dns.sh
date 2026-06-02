#!/bin/bash

# ==============================================================================
# GoDaddy Minecraft DNS Updater Script
# ==============================================================================
# Automates setting up A and SRV records on GoDaddy for Minecraft servers.
# Supports both root domains (@) and subdomains (e.g. mc.domain.com).
# ==============================================================================

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0;0m' # No Color

cleanup() {
    local exit_code=$?
    trap - SIGINT SIGTERM ERR EXIT
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${RED}DNS update failed.${NC}"
    fi
    exit $exit_code
}

echo -e "${CYAN}"
echo "=========================================================="
echo "    GODADDY MINECRAFT DNS CONFIGURATION TOOL             "
echo "=========================================================="
echo -e "${NC}"

# Check dependencies
for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}Error: '$cmd' is required but not installed. Please install it first.${NC}"
        exit 1
    fi
done

# 1. Credentials Prompts
read -rp "Enter GoDaddy API Key: " GD_KEY
if [ -z "$GD_KEY" ]; then
    echo -e "${RED}API Key is required.${NC}"
    exit 1
fi

read -rp "Enter GoDaddy API Secret: " GD_SECRET
if [ -z "$GD_SECRET" ]; then
    echo -e "${RED}API Secret is required.${NC}"
    exit 1
fi

read -rp "Enter your Domain Name (e.g. example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Domain name is required.${NC}"
    exit 1
fi

read -rp "Enter Subdomain for Minecraft (default: mc, use @ for root domain): " SUBDOMAIN
[ -z "$SUBDOMAIN" ] && SUBDOMAIN="mc"

read -rp "Enter Minecraft Server Port (default: 25565): " PORT
[ -z "$PORT" ] && PORT="25565"

# 2. IP Address Resolution
echo -e "${BLUE}[*] Resolving current public IP address...${NC}"
DETECTED_IP=$(curl -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 https://ifconfig.me || true)

if [ -z "$DETECTED_IP" ]; then
    echo -e "${YELLOW}Warning: Could not automatically detect your public IP.${NC}"
    read -rp "Please enter the public IP of your server: " IP
else
    echo -e "${GREEN}[+] Detected Public IP: $DETECTED_IP${NC}"
    read -rp "Use this IP? (Y/n): " USE_IP_SEL
    [ -z "$USE_IP_SEL" ] && USE_IP_SEL="y"
    if [[ "$USE_IP_SEL" =~ ^[yY]$ ]]; then
        IP="$DETECTED_IP"
    else
        read -rp "Enter the public IP of your server: " IP
    fi
fi

if [ -z "$IP" ]; then
    echo -e "${RED}IP address is required.${NC}"
    exit 1
fi

# 3. Formulate SRV and Target domains
TARGET_HOST=""
SRV_NAME=""
if [ "$SUBDOMAIN" = "@" ]; then
    TARGET_HOST="$DOMAIN"
    SRV_NAME="_minecraft._tcp"
    FULL_DOMAIN="$DOMAIN"
else
    TARGET_HOST="$SUBDOMAIN.$DOMAIN"
    SRV_NAME="_minecraft._tcp.$SUBDOMAIN"
    FULL_DOMAIN="$SUBDOMAIN.$DOMAIN"
fi

echo -e "\n${YELLOW}--- DNS Configuration Summary ---${NC}"
echo -e "A Record:   $SUBDOMAIN.$DOMAIN -> $IP"
echo -e "SRV Record: $SRV_NAME.$DOMAIN -> points to $TARGET_HOST on port $PORT"
read -rp "Do you want to apply these changes to GoDaddy? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 0
fi

# 4. Push A Record to GoDaddy
echo -e "${BLUE}[*] Creating/Updating A Record on GoDaddy...${NC}"
A_PAYLOAD=$(jq -n --arg ip "$IP" '[{"data": $ip, "ttl": 600}]')

set +e
A_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Authorization: sso-key ${GD_KEY}:${GD_SECRET}" \
  -H "Content-Type: application/json" \
  -d "$A_PAYLOAD" \
  "https://api.godaddy.com/v1/domains/${DOMAIN}/records/A/${SUBDOMAIN}")
set -e

if [ "$A_RESPONSE" -eq 200 ] || [ "$A_RESPONSE" -eq 201 ]; then
    echo -e "${GREEN}[+] A Record successfully updated!${NC}"
else
    echo -e "${RED}Error: Failed to update A Record. HTTP Code: $A_RESPONSE${NC}"
    exit 1
fi

# 5. Push SRV Record to GoDaddy
echo -e "${BLUE}[*] Creating/Updating SRV Record on GoDaddy...${NC}"
SRV_PAYLOAD=$(jq -n \
  --arg host "$TARGET_HOST" \
  --argjson port "$PORT" \
  '[{"data": $host, "port": $port, "priority": 0, "protocol": "_tcp", "service": "_minecraft", "ttl": 600, "weight": 5}]')

set +e
SRV_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Authorization: sso-key ${GD_KEY}:${GD_SECRET}" \
  -H "Content-Type: application/json" \
  -d "$SRV_PAYLOAD" \
  "https://api.godaddy.com/v1/domains/${DOMAIN}/records/SRV/${SRV_NAME}")
set -e

if [ "$SRV_RESPONSE" -eq 200 ] || [ "$SRV_RESPONSE" -eq 201 ]; then
    echo -e "${GREEN}[+] SRV Record successfully updated!${NC}"
else
    echo -e "${RED}Error: Failed to update SRV Record. HTTP Code: $SRV_RESPONSE${NC}"
    exit 1
fi

# Disable cleanup trap before final success
trap - SIGINT SIGTERM ERR EXIT

echo -e "\n${GREEN}=========================================================="
echo "    DNS UPDATE COMPLETE!                                  "
echo "=========================================================="
echo -e "Domain config succeeded. Players can now connect to:"
echo -e "${CYAN}$FULL_DOMAIN${NC}"
echo -e "==========================================================${NC}"
