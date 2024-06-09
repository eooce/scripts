#!/bin/bash

# Variables
INSTALL_DIR="/root/juicity"
CONFIG_FILE="$INSTALL_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/juicity.service"
JUICITY_SERVER="$INSTALL_DIR/juicity-server"

# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i = 0; i < ${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Introduction animation
echo ""
echo ""
print_with_delay "juicity-install by eooce " 0.1
echo ""
echo ""

# Install required packages
install_packages() {
    packages="unzip jq uuid-runtime"
    install=""

    for pkg in $packages; do
        if ! command -v $pkg &>/dev/null; then
            install="$install $pkg"
        fi
    done

    if [ -z "$install" ]; then
        echo -e "${green}All packages are already installed${re}"
        return
    fi

    if command -v apt &>/dev/null; then
        pm="apt-get install -y -q"
    elif command -v yum &>/dev/null; then
        pm="yum install -y"
    elif command -v dnf &>/dev/null; then
        pm="dnf install -y"
    elif command -v apk &>/dev/null; then
        pm="apk add"
    else
        echo -e "${red}暂不支持的系统!${re}"
        exit 1
    fi
    $pm $install
}
install_packages

# Check for an existing installation
if [[ -d $INSTALL_DIR && -f $SERVICE_FILE ]]; then
    echo "Juicity already installed. Choose an option:"
    echo ""
    echo ""
    echo "1. Reinstall"
    echo ""
    echo "2. Modify"
    echo ""
    echo "3. Uninstall"
    echo ""
    read -p "Enter your choice (1/2/3): " choice

    case $choice in
        1)
            echo "Reinstalling..."
            sudo systemctl stop juicity
            sudo systemctl disable juicity > /dev/null 2>&1
            rm -rf $INSTALL_DIR
            rm -f $SERVICE_FILE
            ;;
        2)
            read -p "Enter new listen port: " PORT
            sed -i "s/\"listen\": \":.*\"/\"listen\": \":$PORT\"/" $CONFIG_FILE
            sudo systemctl restart juicity
            SHARE_LINK=$($JUICITY_SERVER generate-sharelink -c $CONFIG_FILE)
            echo "New Share Link: $SHARE_LINK"
            exit 0
            ;;
        3)
            sudo systemctl stop juicity
            sudo systemctl disable juicity > /dev/null 2>&1
            rm -rf $INSTALL_DIR
            rm -f $SERVICE_FILE
            echo "Uninstalled successfully!"
            exit 0
            ;;
        *)
            echo "Invalid choice!"
            exit 1
            ;;
    esac
fi

# Detect Architecture
ARCH=$(uname -m)
BINARY_NAME="juicity-linux"

case "$ARCH" in
    "x86_64")
        BINARY_NAME+="-x86_64.zip"
        ;;
    "arm64")
        BINARY_NAME+="-arm64.zip"
        ;;
    "armv7")
        BINARY_NAME+="-armv7.zip"
        ;;
    "mips32")
        BINARY_NAME+="-mips32.zip"
        ;;
    "mips64")
        BINARY_NAME+="-mips64.zip"
        ;;
    "riscv64")
        BINARY_NAME+="-riscv64.zip"
        ;;
    "i686")
        BINARY_NAME+="-x86_32.zip"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

LATEST_RELEASE_URL=$(curl --silent "https://api.github.com/repos/juicity/juicity/releases" | jq -r ".[0].assets[] | select(.name == \"$BINARY_NAME\") | .browser_download_url")

# Download and extract
mkdir -p $INSTALL_DIR
curl -sL $LATEST_RELEASE_URL -o "$INSTALL_DIR/juicity.zip"
unzip -q "$INSTALL_DIR/juicity.zip" -d $INSTALL_DIR

# Delete all files except juicity-server
find $INSTALL_DIR ! -name 'juicity-server' -type f -exec rm -f {} +

# Set permissions
chmod +x $JUICITY_SERVER

# Create config.json
echo ""
read -p "Enter listen port (or press enter to randomize between 10000 and 65535): " PORT
echo ""
[[ -z "$PORT" ]] && PORT=$((RANDOM % 55536 + 10000))
echo ""
read -p "Enter password (or press enter to generate one): " PASSWORD
echo ""
if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    echo "Generated Password: $PASSWORD"
fi
UUID=$(uuidgen)

# Generate keys
openssl ecparam -genkey -name prime256v1 -out "$INSTALL_DIR/private.key"
openssl req -new -x509 -days 36500 -key "$INSTALL_DIR/private.key" -out "$INSTALL_DIR/fullchain.cer" -subj "/CN=www.speedtest.net"

cat > $CONFIG_FILE <<EOL
{
  "listen": ":$PORT",
  "users": {
    "$UUID": "$PASSWORD"
  },
  "certificate": "$INSTALL_DIR/fullchain.cer",
  "private_key": "$INSTALL_DIR/private.key",
  "congestion_control": "bbr",
  "log_level": "info"
}
EOL

# Create systemd service file
cat > $SERVICE_FILE <<EOL
[Unit]
Description=juicity-server Service
Documentation=https://github.com/juicity/juicity
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$JUICITY_SERVER run -c $CONFIG_FILE
StandardOutput=file:$INSTALL_DIR/juicity-server.log
StandardError=file:$INSTALL_DIR/juicity-server.log
Restart=on-failure
LimitNPROC=512
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable juicity > /dev/null 2>&1
sudo systemctl start juicity

# Modified share link output
SHARE_LINK=$($JUICITY_SERVER generate-sharelink -c $CONFIG_FILE)
echo ""
echo ""
echo -e "\e[1;32m$SHARE_LINK\033[0m"
echo ""
echo ""
