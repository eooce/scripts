#!/bin/bash
export PORT=${PORT:-'8880'}
export UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}

# 检查是否为root下运行
[[ $EUID -ne 0 ]] && echo -e '\033[1;35m请在root用户下运行脚本\033[0m' && sleep 1 && exit 1

# 安装依赖
Install_dependencies() {
    packages="gawk curl openssl qrencode"
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
Install_dependencies

# 获取IP地址
getIP() {
    local serverIP
    serverIP=$(curl -s --max-time 3 ipv4.ip.sb 2>/dev/null)
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s --max-time 3 ipv6.ip.sb 2>/dev/null)
        if [[ -n "${serverIP}" ]]; then
            serverIP="[${serverIP}]"
        fi
    fi
    
    # 如果外部服务都获取失败，尝试从网卡获取
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
        if [[ -z "${serverIP}" ]]; then
            serverIP=$(ip -6 route get 2001:4860:4860::8888 2>/dev/null | grep -oP 'src \K\S+' | head -1)
            if [[ -n "${serverIP}" ]]; then
                serverIP="[${serverIP}]"
            fi
        fi
        
        if [[ -z "${serverIP}" ]]; then
            serverIP=$(ifconfig 2>/dev/null | grep -oP 'inet \K[0-9.]+' | grep -v '127.0.0.1' | head -1)
            
            if [[ -z "${serverIP}" ]]; then
                serverIP=$(hostname -I 2>/dev/null | awk '{print $1}')
            fi
        fi
    fi
    echo "${serverIP}"
}

# 安装xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 配置Xray
reconfig() {
    reX25519Key=$(/usr/local/bin/xray x25519)
    rePrivateKey=$(echo "${reX25519Key}" | grep "PrivateKey:" | awk '{print $2}')
    rePublicKey=$(echo "${reX25519Key}" | grep "Password:" | awk '{print $2}')
    shortId=$(openssl rand -hex 8)

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
                        "www.nazhumi.com"
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
    IP=$(getIP)
    url="vless://${UUID}@${IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.nazhumi.com&fp=chrome&pbk=${rePublicKey}&sid=${shortId}&type=tcp&headerType=none#$ISP"

    echo ""
    echo -e "\e[1;32mreality 安装成功\033[0m"
    echo ""
    echo -e "\e[1;32m${url}\033[0m"
    echo ""
    qrencode -t ANSIUTF8 -m 2 -s 2 -o - "$url"
    echo ""   

}
reconfig
