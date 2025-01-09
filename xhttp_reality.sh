#!/bin/bash
export PORT=${PORT:-$(shuf -i 2000-65000 -n 1)}
export UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}

# 检查是否为root下运行
[[ $EUID -ne 0 ]] && echo -e '\033[1;35m请在root用户下运行脚本\033[0m' && sleep 1 && exit 1

# 安装依赖
Install_dependencies() {
    echo -e "\e[1;32m开始全自动安装xhttp-reality中,请稍等...\e[0m"
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
    serverIP=$(curl -s --max-time 2 ip.sb)
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s --max-time 1 ipv6.ip.sb)
    else
        echo -e "\e[1;33m无法获取到你的服务器IP\e[0m"
        exit 1
    fi
    echo "${serverIP}"
}

# 安装xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 配置Xray
main() {
    reX25519Key=$(/usr/local/bin/xray x25519)
    rePrivateKey=$(echo "${reX25519Key}" | head -1 | awk '{print $3}')
    rePublicKey=$(echo "${reX25519Key}" | tail -n 1 | awk '{print $3}')
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
            "id": "$UUID"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "target": "www.nazhumi.com:443",
          "xver": 0,
          "serverNames": [
            "www.nazhumi.com"
          ],
          "privateKey": "$rePrivateKey",
          "shortIds": [
            "$shortId"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
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

    url="vless://${UUID}@$(getIP):${PORT}?encryption=none&security=reality&sni=www.nazhumi.com&fp=chrome&pbk=${rePublicKey}&sid=${shortId}&allowInsecure=1&type=xhttp&mode=auto#$ISP"
        
    echo -e "\n\e[1;32mxhttp-reality 安装成功\033[0m\n"
    echo -e "\e[1;32m${url}\033[0m\n"
    qrencode -t ANSIUTF8 -m 2 -s 2 -o - "$url"
    echo ""   

}
main
