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
print_with_delay "INSTALL Tuic-V5 by eooce" 0.2
echo ""
echo ""

# Check for and install required packages
install_required_packages() {
    REQUIRED_PACKAGES=("curl" "jq" "openssl" "uuid-runtime")
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            apt-get update > /dev/null 2>&1
            apt-get install -y $pkg > /dev/null 2>&1
        fi
    done
}

# Check if the directory /root/tuic already exists
if [ -d "/root/tuic" ]; then
    echo -e "\e[1;32mtuic seems to be already installed\e[0m"
    echo ""
    echo ""
    echo -e "\e[1;32m1: Reinstall\e[0m"
    echo ""
    echo -e "\e[1;32m2: Modify\e[0m"
    echo ""
    echo -e "\e[1;33m3: Uninstall\e[0m"
    echo ""
    read -p "Enter your choice: " choice

    case $choice in
        1)
            rm -rf /root/tuic
            systemctl stop tuic
            pkill -f tuic-server
            systemctl disable tuic > /dev/null 2>&1
            rm /etc/systemd/system/tuic.service
            ;;
        2)
            cd /root/tuic
            current_port=$(jq -r '.server' config.json | cut -d':' -f2)
            current_password=$(jq -r ".users.\"$current_uuid\"")
            echo ""
            read -p "Enter a new port (or press enter to keep the current one [$current_port]): " new_port
            [ -z "$new_port" ] && new_port=$current_port
            echo ""
            read -p "Enter a new password (or press enter to keep the current one [$current_password]): " new_password
            [ -z "$new_password" ] && new_password=$current_password
            jq ".server = \"[::]:$new_port\"" config.json > temp.json && mv temp.json config.json
            jq ".users = {\"$current_uuid\":\"$new_password\"}" config.json > temp.json && mv temp.json config.json
            systemctl daemon-reload
            systemctl restart tuic
            public_ip=$(curl -s https://api.ipify.org)
            echo -e "\nNekoBox/NekoRay URL:"
            echo "tuic://$current_uuid:$new_password@$public_ip:$new_port/?congestion_control=bbr&alpn=h3,spdy/3.1&udp_relay_mode=native&allow_insecure=1"
            echo ""
            exit 0
            ;;
        3)
            rm -rf /root/tuic
            systemctl stop tuic
            pkill -f tuic-server
            systemctl disable tuic > /dev/null 2>&1
            rm /etc/systemd/system/tuic.service
            echo -e "\e[1;32mtuic uninstalled successfully!\e[0m"
            echo ""
            exit 0
            ;;
        *)
            echo -e "\e[1;33mInvalid choice\e[0m"
            exit 1
            ;;
    esac
fi

# Install required packages if not already installed
echo -e "\e[1;32mInstallation is in progress, please wait...\e[0m"
install_required_packages

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
    echo "Failed to download the tuic binary."
    exit 1
fi
chmod 755 tuic-server

# Create self-signed certs
openssl ecparam -genkey -name prime256v1 -out ca.key
openssl req -new -x509 -days 36500 -key ca.key -out ca.crt -subj "/CN=bing.com"

# Prompt user for port and password
echo ""
read -p "Enter a port (or press enter for a random port between 10000 and 65000): " port
echo ""
[ -z "$port" ] && port=$((RANDOM % 55001 + 10000))
echo ""
read -p "Enter a password (or press enter for a random password): " password
echo ""
[ -z "$password" ] && password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 8 | head -n 1)

# Generate UUID
UUID=$(uuidgen)

# Ensure UUID generation is successful
if [ -z "$UUID" ]; then
    echo "Error: Failed to generate UUID."
    exit 1
fi

# Create config.json
cat > config.json <<EOL
{
  "server": "[::]:$port",
  "users": {
    "$UUID": "$password"
  },
  "certificate": "/root/tuic/ca.crt",
  "private_key": "/root/tuic/ca.key",
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
systemctl enable tuic > /dev/null 2>&1
systemctl start tuic

# Print the v2rayN config and nekoray/nekobox URL
public_ip=$(curl -s https://api.ipify.org)

# get ipinfo
isp=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

# nekoray/nekobox URL
echo -e "\nV2rayN、NekoBox:"
echo -e "\e[1;32mtuic://$UUID:$password@$public_ip:$port?congestion_control=bbr&alpn=h3&sni=www.bing.com&udp_relay_mode=native&allow_insecure=1#$isp\e[0m"
echo ""

exit 0
