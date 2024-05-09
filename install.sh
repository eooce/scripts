#!/bin/bash
sudo apt-get update
sudo apt-get install -y jq openssl qrencode

# Extract the desired variables
export NAME=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
export PORT=${PORT:-'8880'}
export SNI=${SNI:-'www.yahoo.com'}  
export PATH=${PATH:-'%2F'}

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --beta

json=$(curl -s https://raw.githubusercontent.com/eooce/xray-reality/master/config.json)

keys=$(xray x25519)
pk=$(echo "$keys" | awk '/Private key:/ {print $3}')
pub=$(echo "$keys" | awk '/Public key:/ {print $3}')
serverIp=$(curl -s ipv4.wtfismyip.com/text)
uuid=$(xray uuid)
shortId=$(openssl rand -hex 8)

newJson=$(echo "$json" | jq \
    --arg pk "$pk" \
    --arg uuid "$uuid" \
    --arg port "$PORT" \
    --arg sni "$SNI" \
    --arg path "$PATH" \
    '.inbounds[0].port= '"$(expr "$PORT")"' |
     .inbounds[0].settings.clients[0].id = $uuid |
     .inbounds[0].streamSettings.realitySettings.dest = $sni + ":443" |
     .inbounds[0].streamSettings.realitySettings.serverNames += ["'$SNI'", "www.'$SNI'"] |
     .inbounds[0].streamSettings.realitySettings.privateKey = $pk |
     .inbounds[0].streamSettings.realitySettings.shortIds += ["'$shortId'"]')

echo "$newJson" | sudo tee /usr/local/etc/xray/config.json >/dev/null
sudo systemctl restart xray

url="vless://$uuid@$serverIp:$PORT?type=http&security=reality&encryption=none&pbk=$pub&fp=chrome&path=%2F&sni=$SNI&sid=$shortId#$NAME"

echo ""
echo -e "\e[1;33mReality节点信息：\033[0m"
echo -e "\e[1;32m$url\033[0m"
echo ""
echo -e "\e[1;33mReality节点二维码：\033[0m"
qrencode -t ANSIUTF8 -m 2 -s 2 -o - "$url"
echo ""

exit 0
