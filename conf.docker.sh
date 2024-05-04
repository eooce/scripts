#!/bin/bash
json=$(curl -s https://raw.githubusercontent.com/eooce/xray-reality/master/config.json)

keys=$(xray x25519)
name=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"_"$18}' | sed -e 's/ /_/g')
pk=$(echo "$keys" | awk '/Private key:/ {print $3}')
pub=$(echo "$keys" | awk '/Public key:/ {print $3}')
serverIp=$(curl -s ifconfig.me)
uuid=$(xray uuid)
shortId=$(openssl rand -hex 8)
url="vless://$uuid@$serverIp:443?path=%2F&security=reality&encryption=none&pbk=$pub&fp=chrome&type=http&sni=yahoo.com&sid=$shortId#$name_reality"

newJson=$(echo "$json" | jq \
    --arg pk "$pk" \
    --arg uuid "$uuid" \
    '.inbounds[0].streamSettings.realitySettings.privateKey = $pk | 
     .inbounds[0].settings.clients[0].id = $uuid |
     .inbounds[0].streamSettings.realitySettings.shortIds += ["'$shortId'"]')
echo "$newJson" | sudo tee /usr/local/etc/xray/config.json >/dev/null

sudo service xray restart


echo "$url" >> /root/reality.txt
cd~
cat reality.txt

exit 0
