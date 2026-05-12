#!/bin/bash

# Auroranet Server Installer for Ubuntu/Debian
# This script must be run with sudo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}== Auroranet Server Installation ==${NC}"

# 1. Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (sudo)${NC}"
  exit 1
fi

# 2. Update and Install dependencies
echo -e "${GREEN}[1/5] Installing system dependencies...${NC}"
apt-get update -y
apt-get install -y wget curl git sqlite3 wireguard build-essential

# 3. Install Go (if not present or too old)
if ! command -v go &> /dev/null || [[ "$(go version | awk '{print $3}' | cut -c 3-4)" -lt 22 ]]; then
    echo -e "${GREEN}Installing Go 1.22.0...${NC}"
    GO_VERSION="1.22.0"
    wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    ln -sf /usr/local/go/bin/go /usr/bin/go
    rm go${GO_VERSION}.linux-amd64.tar.gz
fi

# 4. Build the Core Backend
echo -e "${GREEN}[2/5] Building Auroranet Core...${NC}"
cd core
go build -o auroranet-server ./cmd/server/main.go
cd ..

# 5. Setup System User and Directories
echo -e "${GREEN}[3/5] Setting up system user and directories...${NC}"
if ! id "auroranet" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin auroranet
fi

mkdir -p /var/lib/auroranet
mkdir -p /etc/auroranet
cp core/auroranet-server /usr/local/bin/auroranet-server
chmod +x /usr/local/bin/auroranet-server

# Handle database initialization if it doesn't exist
if [ ! -f /var/lib/auroranet/auroranet.db ]; then
    # Create empty DB or copy existing schema
    # For now, let the server initialize it on first run
    touch /var/lib/auroranet/auroranet.db
fi

chown -R auroranet:auroranet /var/lib/auroranet
chown auroranet:auroranet /usr/local/bin/auroranet-server

# 6. Create Systemd Service
echo -e "${GREEN}[4/5] Creating systemd service...${NC}"
cat > /etc/systemd/system/auroranet.service <<EOF
[Unit]
Description=Auroranet Core Server
After=network.target

[Service]
Type=simple
User=auroranet
Group=auroranet
WorkingDirectory=/var/lib/auroranet
Environment="DASHBOARD_PASSWORD=admin"
ExecStart=/usr/local/bin/auroranet-server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 7. Start Service
echo -e "${GREEN}[5/5] Enabling and starting Auroranet service...${NC}"
systemctl daemon-reload
systemctl enable auroranet
# systemctl start auroranet # We don't start it immediately to let the user config things if needed

echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}Installation complete!${NC}"
echo -e "You can now start the server with: ${BLUE}sudo systemctl start auroranet${NC}"
echo -e "Once started, the dashboard will be available at: ${BLUE}http://$(hostname -I | awk '{print $1}'):8080${NC}"
echo -e "Default Dashboard password is 'admin' (Change it in /etc/systemd/system/auroranet.service)"
echo -e "Check status and logs with: ${BLUE}sudo systemctl status auroranet${NC}"
echo -e "${BLUE}======================================${NC}"
