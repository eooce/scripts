#!/bin/bash
export UUID=${UUID:-'1f685446-c968-49f0-9fe1-25847585b0b7'}
export NEZHA_SERVER=${NEZHA_SERVER:-'nz.abc.cn'} 
export NEZHA_PORT=${NEZHA_PORT:-'5555'}     
export NEZHA_KEY=${NEZHA_KEY:-''}  
export FILE_PATH=${FILE_PATH:-'./log'}
export SNI=${SNI:-'www.yahoo.com'}
export SERVER_PORT="${SERVER_PORT:-${PORT:-2024}}"  # 必填开放的端口

# Download Dependency Files
ARCH=$(uname -m) && DOWNLOAD_DIR="${FILE_PATH}" && mkdir -p "$DOWNLOAD_DIR" && FILE_INFO=()
if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
    FILE_INFO=("https://github.com/eooce/test/releases/download/ARM/web web" "https://github.com/eooce/test/releases/download/ARM/swith npm")
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    FILE_INFO=("https://github.com/eooce/test/releases/download/freebsd/web web" "https://github.com/eooce/test/releases/download/freebsd/swith npm")
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi
for entry in "${FILE_INFO[@]}"; do
    URL=$(echo "$entry" | cut -d ' ' -f 1)
    NEW_FILENAME=$(echo "$entry" | cut -d ' ' -f 2)
    FILENAME="$DOWNLOAD_DIR/$NEW_FILENAME"
    if [ -e "$FILENAME" ]; then
        echo -e "\e[1;32m$FILENAME already exists,Skipping download\e[0m"
    else
        curl -L -sS -o "$FILENAME" "$URL"
        echo -e "\e[1;32mDownloading $FILENAME\e[0m"
    fi
    chmod +x $FILENAME
done
wait

# Generating Configuration Files
generate_config() {

    X25519Key=$(./"${FILE_PATH}/web" x25519)
    PrivateKey=$(echo "${X25519Key}" | head -1 | awk '{print $3}')
    PublicKey=$(echo "${X25519Key}" | tail -n 1 | awk '{print $3}')
    shortid=$(openssl rand -hex 8)

  cat > ${FILE_PATH}/config.json << EOF
{
    "inbounds": [
        {
            "port": $SERVER_PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "1.1.1.1:443",
                    "xver": 0,
                    "serverNames": [
                        "$SNI"
                    ],
                    "privateKey": "$PrivateKey",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "$shortid"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]    
}
EOF
}
generate_config
wait

# running files
run() {
  if [ -e "${FILE_PATH}/npm" ]; then
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    if [[ "${tlsPorts[*]}" =~ "${NEZHA_PORT}" ]]; then
      NEZHA_TLS="--tls"
    else
      NEZHA_TLS=""
    fi
    if [ -n "$NEZHA_SERVER" ] && [ -n "$NEZHA_PORT" ] && [ -n "$NEZHA_KEY" ]; then
        nohup ${FILE_PATH}/npm -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} >/dev/null 2>&1 &
	sleep 1
       echo -e "\e[1;32mnpm is running\e[0m"
    else
        echo -e "\e[1;35mNEZHA variable is empty,skiping runing\e[0m"
    fi
  fi

  if [ -e "${FILE_PATH}/web" ]; then
    nohup ${FILE_PATH}/web -c ${FILE_PATH}/config.json >/dev/null 2>&1 &
    sleep 1
    echo -e "\e[1;32mweb is running\e[0m"
  fi

}
run

# get ip
IP=$(curl -s https://ipv4.icanhazip.com)

# get ipinfo
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

cat > ${FILE_PATH}/list.txt <<EOF

vless://${UUID}@${IP}:${SERVER_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PublicKey}&sid=${shortid}&type=tcp&headerType=none#$ISP

EOF
cat ${FILE_PATH}/list.txt
echo -e "\n\e[1;32m${FILE_PATH}/list.txt saved successfully\e[0m"
echo ""
sleep 10 
clear
echo -e "\n\e[1;32mRunning success!\e[0m"
rm -rf 00.sh ${FILE_PATH}/config.json ${FILE_PATH}/npm ${FILE_PATH}/web
exit 0
