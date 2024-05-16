#!/bin/bash

# 随机生成端口和密码
[ -z "$HY2_PORT" ] && HY2_PORT=$(shuf -i 2000-65000 -n 1)
[ -z "$RANDOM_PSK" ] && RANDOM_PSK=$(openssl rand -base64 12)

# 检查是否为root下运行
[[ $EUID -ne 0 ]] && echo -e '\033[1;35m请在root用户下运行脚本\033[0m' && sleep 1 && exit 1

# 判断系统及定义系统安装依赖方式
DISTRO=$(cat /etc/os-release | grep '^ID=' | awk -F '=' '{print $2}' | tr -d '"')
case $DISTRO in
  "debian"|"ubuntu")
    PACKAGE_UPDATE="apt-get update"
    PACKAGE_INSTALL="apt-get install -y"
    PACKAGE_REMOVE="apt-get remove -y"
    PACKAGE_UNINSTALL="apt-get autoremove -y"
    ;;
  "centos"|"fedora"|"rhel")
    PACKAGE_UPDATE="yum -y update"
    PACKAGE_INSTALL="yum -y install"
    PACKAGE_REMOVE="yum -y remove"
    PACKAGE_UNINSTALL="yum -y autoremove"
    ;;
  *)
    echo "不支持的 Linux 发行版"
    exit 1
    ;;
esac

# 安装依赖
$PACKAGE_INSTALL unzip wget curl

# 安装Hysteria2
bash <(curl -fsSL https://get.hy2.sh/)

# 生成自签证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=bing.com" -days 36500 && sudo chown hysteria /etc/hysteria/server.key && sudo chown hysteria /etc/hysteria/server.crt

# 生成hy2配置文件
cat << EOF > /etc/hysteria/config.yaml
listen: :$HY2_PORT  # 监听随机端口

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: "$RANDOM_PSK" # 设置随机密码

fastOpen: true

masquerade:
  type: proxy
  proxy:
    url: https://bing.com # 伪装域名
    rewriteHost: true

transport:
  udp:
    hopInterval: 30s
EOF

# 启动Hysteria2
systemctl start hysteria-server.service
systemctl restart hysteria-server.service

# 设置开机自启
systemctl enable hysteria-server.service

# 获取本机IP地址
ipv4=$(curl -s https://ipv4.icanhazip.com)
if [ -n "$ipv4" ]; then
    HOST_IP="$ipv4"
else
    ipv6=$(curl -s https://ipv6.icanhazip.com)
    if [ -n "$ipv6" ]; then
        HOST_IP="$ipv6"
    else
        echo -e "\e[1;35m无法获取IPv4或IPv6地址\033[0m"
        exit 1
    fi
fi
echo -e "\e[1;32m本机IP: $HOST_IP\033[0m"

# 获取ipinfo
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

# 输出hy2信息
echo -e "\e[1;32mHysteria2安装成功\033[0m"
echo ""
echo -e "\e[1;33mV2rayN或Nekobox\033[0m"
echo -e "\e[1;32mhysteria2://$RANDOM_PSK@$HOST_IP:$HY2_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP\033[0m"
echo ""
echo -e "\e[1;33mSurge\033[0m"
echo -e "\e[1;32m$ISP = hysteria2, $HOST_IP, $HY2_PORT, password = $RANDOM_PSK, skip-cert-verify=true, sni=www.bing.com\033[0m"
echo ""
echo -e "\e[1;33mClash\033[0m"
cat << EOF
- name: $ISP
  type: hysteria2
  server: $HOST_IP
  port: $HY2_PORT
  password: $RANDOM_PSK
  alpn:
    - h3
  sni: www.bing.com
  skip-cert-verify: true
  fast-open: true
EOF
