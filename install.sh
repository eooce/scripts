#!/bin/bash

# Update package index and install dependencies
sudo apt-get update
sudo apt-get install -y jq openssl qrencode

curl -s https://raw.githubusercontent.com/eooce/xray-reality/master/default.json > config.json

# Extract the desired variables using jq
name=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
email=$(jq -r '.email' config.json)
port=$(jq -r '.port' config.json)
sni=$(jq -r '.sni' config.json)
path=$(jq -r '.path' config.json)

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --beta

json=$(curl -s https://raw.githubusercontent.com/eooce/xray-reality/master/config.json)

keys=$(xray x25519)
pk=$(echo "$keys" | awk '/Private key:/ {print $3}')
pub=$(echo "$keys" | awk '/Public key:/ {print $3}')
serverIp=$(curl -s ipv4.wtfismyip.com/text)
uuid=$(xray uuid)
shortId=$(openssl rand -hex 8)

url="vless://$uuid@$serverIp:$port?type=http&security=reality&encryption=none&pbk=$pub&fp=chrome&path=$path&sni=$sni&sid=$shortId#$name-reality"

newJson=$(echo "$json" | jq \
    --arg pk "$pk" \
    --arg uuid "$uuid" \
    --arg port "$port" \
    --arg sni "$sni" \
    --arg path "$path" \
    --arg email "$email" \
    '.inbounds[0].port= '"$(expr "$port")"' |
     .inbounds[0].settings.clients[0].email = $email |
     .inbounds[0].settings.clients[0].id = $uuid |
     .inbounds[0].streamSettings.realitySettings.dest = $sni + ":443" |
     .inbounds[0].streamSettings.realitySettings.serverNames += ["'$sni'", "www.'$sni'"] |
     .inbounds[0].streamSettings.realitySettings.privateKey = $pk |
     .inbounds[0].streamSettings.realitySettings.shortIds += ["'$shortId'"]')

echo "$newJson" | sudo tee /usr/local/etc/xray/config.json >/dev/null
sudo systemctl restart xray

echo ""
echo -e "\e[1;33mReality节点信息：\033[0m"
echo -e "\e[1;32m$url\033[0m"
echo ""
echo -e "\e[1;33mReality节点二维码：\033[0m"
qrencode -t ANSIUTF8 -m 2 -s 2 -o - "$url"

exit 0
