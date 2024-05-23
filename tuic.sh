#!/bin/bash

# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Introduction animation
echo ""
echo ""
print_with_delay "Install Tuic-V5 by eooce" 0.1
echo ""
echo ""

# Check for and install required packages
install_packages() {
    packages="jq curl openssl"
    install=""

    for pkg in $packages; do
        if ! command -v $pkg &>/dev/null; then
            install="$install $pkg"
        fi
    done

    if [ -z "$install" ]; then
        echo -e "\e[1;32mAll packages are already installed\e[0m"
        return
    fi

    if command -v apt &>/dev/null; then
        pm="apt-get install -y -q"
    elif command -v dnf &>/dev/null; then
        pm="dnf install -y"
    elif command -v yum &>/dev/null; then
        pm="yum install -y"
    elif command -v apk &>/dev/null; then
        pm="apk add"
    else
        echo -e "\e[1;33m暂不支持的系统!\e[0m"
        exit 1
    fi
    $pm $install
}

# Check if the directory /root/tuic already exists
if [ -d "/root/tuic" ]; then
    echo -e "\e[1;32mTuic is already installed\e[0m"
    echo ""
    echo ""
    echo -e "\e[1;32m1: Reinstall\e[0m"
    echo ""
    echo -e "\e[1;32m2: Change config\e[0m"
    echo ""
    echo -e "\e[1;35m3: Uninstall\e[0m"
    echo ""
    read -p $'\033[1;91mEnter your choice: \033[0m' choice

    case $choice in
        1)
            rm -rf /root/tuic
            systemctl stop tuic
            pkill -f tuic-server
            systemctl disable tuic > /dev/null 2>&1
            rm /etc/systemd/system/tuic.service
            ;;
        2)   read -p $'\033[1;35mEnter a UUID (or press enter for a random UUID): \033[0m' new_uuid
            [ -z "$new_uuid" ] && new_uuid=$(openssl rand -hex 16 | awk '{print substr($0,1,8)"-"substr($0,9,4)"-"substr($0,13,4)"-"substr($0,17,4)"-"substr($0,21,12)}')
            password=$(jq -r '.users[]' /root/tuic/config.json)
            jq ".users = {\"""$new_uuid\":\"$password\"}" /root/tuic/config.json > temp.json && mv temp.json /root/tuic/config.json
            echo -e "\e[1;32mYour new UUID:$new_uuid\e[0m"
            
            read -p $'\033[1;35mEnter a new port (or press enter for a random port): \033[0m' new_port
            [ -z "$new_port" ] && new_port=$(shuf -i 10000-65000 -n 1)
            sed -i "s/\"\[::\]:[0-9]\+\"/\"\[::\]:$new_port\"/" /root/tuic/config.json
            echo -e "\e[1;32mYour new PORT:$new_port\e[0m"
            systemctl daemon-reload
            systemctl restart tuic
            public_ip=$(curl -s https://api.ipify.org)
            isp=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
            echo -e "\e[1;33m\nV2rayN、NekoBox\e[0m"
            echo -e "\e[1;32mtuic://$new_uuid:$password@$public_ip:$new_port?congestion_control=bbr&alpn=h3&sni=www.bing.com&udp_relay_mode=native&allow_insecure=1#$isp\e[0m"
            echo ""
            exit 0
            ;;
        3)
            rm -rf /root/tuic
            systemctl stop tuic
            pkill -f tuic-server
            systemctl disable tuic > /dev/null 2>&1
            rm /etc/systemd/system/tuic.service
            rm tuic.sh
            echo -e "\e[1;32mTuic uninstalled successfully!\e[0m"
            echo ""
            exit 0
            ;;
        *)
            echo -e "\e[1;33mExit Installation\e[0m"
            rm tuic.sh
            exit 0
            ;;
    esac
fi

# Install packages if is not already installed
install_packages
echo -e "\e[1;32mInstallation is in progress, please wait...\e[0m"

# Detect the architecture of the server
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "x86_64-unknown-linux-gnu"
            ;;
        i686)
            echo "i686-unknown-linux-gnu"
            ;;
        armv7l)
            echo "armv7-unknown-linux-gnueabi"
            ;;
        aarch64)
            echo "aarch64-unknown-linux-gnu"
            ;;
        *)
            echo -e "\e[1;33mUnsupported architecture: $arch\e[0m"
            exit 1
            ;;
    esac
}

server_arch=$(detect_arch)
latest_release_version=$(curl -s "https://api.github.com/repos/etjec4/tuic/releases/latest" | jq -r ".tag_name")

# Build the download URL based on the latest release version and detected architecture
download_url="https://github.com/etjec4/tuic/releases/download/$latest_release_version/$latest_release_version-$server_arch"

# Download the binary with verbose output
mkdir -p /root/tuic
cd /root/tuic
wget -O tuic-server -q "$download_url"
if [[ $? -ne 0 ]]; then
    echo "Failed to download the tuic binary"
    exit 1
fi
chmod 755 tuic-server

# Create self-signed certs
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /root/tuic/server.key -out /root/tuic/server.crt -subj "/CN=bing.com" -days 36500

# Prompt user for port and password
echo ""
read -p $'\033[1;35mEnter a port between 10000 to 65000(or press enter for a random port): \033[0m' port
echo ""
[ -z "$port" ] && port=$((RANDOM % 55001 + 10000))
echo -e "\e[1;32mTuic port:$port\e[0m"

read -p $'\033[1;35mEnter a password (or press enter for a random password): \033[0m' password
[ -z "$password" ] && password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 8 | head -n 1)
echo -e "\e[1;32mTuic password:$password\e[0m"

# Generate UUID
UUID=$(openssl rand -hex 16 | awk '{print substr($0,1,8)"-"substr($0,9,4)"-"substr($0,13,4)"-"substr($0,17,4)"-"substr($0,21,12)}')
echo -e "\e[1;32mTuic UUID:$UUID\e[0m"

# Ensure UUID generation is successful
if [ -z "$UUID" ]; then
    echo -e "\e[1;91mError: Failed to generate UUID\e[0m"
    exit 1
fi

# Create config.json
cat > config.json <<EOL
{
  "server": "[::]:$port",
  "users": {
    "$UUID": "$password"
  },
  "certificate": "/root/tuic/server.crt",
  "private_key": "/root/tuic/server.key",
  "congestion_control": "bbr",
  "alpn": ["h3", "spdy/3.1"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": false,
  "dual_stack": true,
  "auth_timeout": "3s",
  "task_negotiation_timeout": "3s",
  "max_idle_time": "10s",
  "max_external_packet_size": 1500,
  "gc_interval": "3s",
  "gc_lifetime": "15s",
  "log_level": "warn"
}
EOL

# Create a systemd service for tuic
cat > /etc/systemd/system/tuic.service <<EOL
[Unit]
Description=tuic service
Documentation=TUIC v5
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root/tuic
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/root/tuic/tuic-server -c /root/tuic/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start tuic
systemctl daemon-reload
systemctl start tuic
systemctl enable tuic > /dev/null 2>&1
systemctl restart tuic

# Print the v2rayN config and nekoray/nekobox URL
public_ip=$(curl -s https://api.ipify.org)

# get ipinfo
isp=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

# nekoray/nekobox URL
echo -e "\e[1;33m\nV2rayN、NekoBox\e[0m"
echo -e "\e[1;32mtuic://$UUID:$password@$public_ip:$port?congestion_control=bbr&alpn=h3&sni=www.bing.com&udp_relay_mode=native&allow_insecure=1#$isp\e[0m"
echo ""
