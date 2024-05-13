#!/bin/bash

# 检查是否为root下运行
[[ $EUID -ne 0 ]] && echo -e "注意: 请在root用户下运行脚本" && sleep 2 && exit 1

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

# 安装必要的软件包
$PACKAGE_INSTALL unzip wget curl

# 一键安装Hysteria2
bash <(curl -fsSL https://get.hy2.sh/)

# 生成自签证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=bing.com" -days 36500 && sudo chown hysteria /etc/hysteria/server.key && sudo chown hysteria /etc/hysteria/server.crt

# 随机生成端口和密码
RANDOM_PORT=$(shuf -i 2000-65000 -n 1)
RANDOM_PSK=$(openssl rand -base64 12)

# 生成配置文件
cat << EOF > /etc/hysteria/config.yaml
listen: :$RANDOM_PORT # 监听随机端口

# 使用自签证书
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: "$RANDOM_PSK" # 设置随机密码
  
masquerade:
  type: proxy
  proxy:
    url: https://bing.com # 伪装网址
    rewriteHost: true
EOF

# 启动Hysteria2
systemctl start hysteria-server.service
systemctl restart hysteria-server.service

# 设置开机自启
systemctl enable hysteria-server.service

# 获取本机IP地址
HOST_IP=$(curl -s http://checkip.amazonaws.com)

# 获取ipinfo
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

# 输出所需信息
echo "Hysteria2 安装成功"
echo ""
echo "V2rayN"
echo "hysteria2://$RANDOM_PSK@$HOST_IP:$RANDOM_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP"
echo ""
echo "Surge"
echo "$ISP = hysteria2, $HOST_IP, $RANDOM_PORT, password = $RANDOM_PSK, skip-cert-verify=true, sni=www.bing.com"
echo ""
echo "Clash"
cat << EOF
- name: $ISP
  type: hysteria2
  server: $HOST_IP
  port: $RANDOM_PORT
  password: $RANDOM_PSK
  alpn:
    - h3
  sni: www.bing.com
  skip-cert-verify: true
  fast-open: true
EOF
