#!/bin/bash
export PORT=${PORT:-'8880'}
export UUID=$(cat /proc/sys/kernel/random/uuid)

# 检查是否为root下运行
[[ $EUID -ne 0 ]] && echo -e '\033[1;35m请在root用户下运行脚本\033[0m' && sleep 2 && exit 1

# 获取IP地址
getIP() {
    local serverIP
    serverIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s https://ipv6.icanhazip.com)
    fi
    echo "${serverIP}"
}

# 安装xray
install_xray() {
    if command -v apt &>/dev/null; then
        apt-get update -y
        apt-get install -y gawk curl openssl qrencode
    elif command -v dnf &>/dev/null; then
        dnf update -y
        dnf install -y epel-release gawk curl openssl qrencode
    elif command -v yum &>/dev/null; then
        yum update -y
        yum install -y epel-release gawk curl openssl qrencode
    else
        echo -e "${red}暂不支持你的系统!${re}"
        return 1
    fi
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}


reconfig() {
    reX25519Key=$(/usr/local/bin/xray x25519)
    rePrivateKey=$(echo "${reX25519Key}" | head -1 | awk '{print $3}')
    rePublicKey=$(echo "${reX25519Key}" | tail -n 1 | awk '{print $3}')
    shortId=$(openssl rand -hex 8)

    # 重新配置Xray
    cat >/usr/local/etc/xray/config.json <<EOF
{
    "inbounds": [
        {
            "port": $PORT,
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
                        "www.apple.com"
                    ],
                    "privateKey": "$rePrivateKey",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "$shortId"
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

    # 启动Xray服务
    systemctl enable xray.service && systemctl restart xray.service

    # 获取ipinfo
    ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

    # 删除运行脚本
    rm -f tcp-wss.sh install-release.sh reality.sh 

    url="vless://${UUID}@$(getIP):${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pbk=${rePublicKey}&sid=${shortId}&type=tcp&headerType=none#$ISP"

    echo ""
    echo -e "\e[1;32mreality 安装成功\033[0m"
    echo ""
    echo -e "\e[1;32m${url}\033[0m"
    echo ""
    qrencode -t ANSIUTF8 -m 2 -s 2 -o - "$url"
    echo ""   

}

install_xray
reconfig
