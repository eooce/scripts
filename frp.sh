#!/bin/bash
# 集成式FRP内网穿透配置脚本（带信息保存功能）
# 安装服务端/客户端时自动保存配置到/home/frp/info.txt
# 官方服务端口示例配置：https://github.com/fatedier/frp/blob/dev/conf/frps_full_example.toml
# 官方客户端口示例配置：https://github.com/fatedier/frp/blob/dev/conf/frpc_full_example.toml

red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# 环境变量
export FRP_VERSION=${FRP_VERSION:-'0.62.1'}  
export FRP_DIR=${FRP_DIR:-'/home/frp'} 
export SSH_PORT=${SSH_PORT:-'22'} 
export INFO_FILE="${FRP_DIR}/info.txt"

check_root() {
    [ "$(id -u)" != "0" ] && { red "错误: 此脚本需要以root权限运行"; exit 1; }
}

get_server_ip() {
    local ipv4=$(curl -s --max-time 2 ipv4.ip.sb)
    if [ -n "$ipv4" ]; then
        echo "$ipv4"
    else
        ipv6=$(curl -s --max-time 2 ipv6.ip.sb)
        echo "[$ipv6]"
    fi
}

get_arch() {
    ARCH=$(uname -m)
    case ${ARCH} in
        x86_64|amd64) echo "amd64";;
        arm64|aarch64) echo "arm64";;
        *) red "不支持的架构: ${ARCH}"; exit 1;;
    esac
}

init_frp_dir() {
    mkdir -p "${FRP_DIR}" || { red "创建FRP目录失败"; exit 1; }
    cd "${FRP_DIR}" || exit 1
}

download_frp() {
    local ARCH=$1
    FRP_PACKAGE="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    
    [ ! -f "${FRP_PACKAGE}" ] && {
        yellow "下载frp v${FRP_VERSION}..."
        wget -q --show-progress "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_PACKAGE}" || {
            red "下载frp失败"; exit 1
        }
    }
    
    tar -zxvf "${FRP_PACKAGE}" >/dev/null || { red "解压frp失败"; exit 1; }
    mv frp_${FRP_VERSION}_linux_${ARCH}/* ${FRP_DIR}/
    rm -rf frp_${FRP_VERSION}_linux_${ARCH} ${FRP_PACKAGE}
}

set_root_password() {
    reading "请输入root密码 [提示: 回车留空将随机生成]: " ROOT_PWD
    [ -z "$ROOT_PWD" ] && {
        ROOT_PWD=$(openssl rand -hex 8)
        yellow "正在设置root密码,随机root密码为: $ROOT_PWD"
    }

    lsof -i:22 | awk '/IPv4/{print $2}' | xargs kill -9 2>/dev/null || true
    echo -e '\nPermitRootLogin yes\nPasswordAuthentication yes' >> /etc/ssh/sshd_config
    echo "root:${ROOT_PWD}" | chpasswd || { red "root密码设置失败"; exit 1; }

    systemctl unmask ssh containerd docker.socket docker &>/dev/null
    pkill dockerd &>/dev/null
    pkill containerd &>/dev/null
    systemctl restart ssh containerd docker.socket docker &>/dev/null

    [ "$(systemctl is-active ssh)" = "active" ] && green "SSH服务运行正常" || { red "SSH服务未运行"; exit 1; }
}

save_config_info() {
    local mode=$1
    shift
    
    echo "=== FRP ${mode} 配置信息 ===" > "$INFO_FILE"
    echo "生成时间: $(date "+%Y-%m-%d %H:%M:%S")" >> "$INFO_FILE"
    for item in "$@"; do
        IFS='|' read -r name value <<< "$item"
        echo "${name}: ${value}" >> "$INFO_FILE"
    done
    echo "=========================" >> "$INFO_FILE"
}

show_config() {
    local mode=$1
    shift
    
    yellow "\n============= ${mode}配置确认 ============="
    for item in "$@"; do
        IFS='|' read -r name value <<< "$item"
        purple "${name}: ${value}"
    done
    purple "===================================="
    
    reading "确认以上配置是否正确？(y/n) [默认: y]: " CONFIRM
    CONFIRM=${CONFIRM:-"y"}
    [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]] && { yellow "配置已取消"; exit 1; }
}

show_info() {
    clear
    if [ -f "$INFO_FILE" ]; then
        echo ""
        cat "$INFO_FILE"
        
        # 判断服务类型
        local service_name status_display
        if grep -q "服务端" "$INFO_FILE"; then
            service_name="frps"
        else
            service_name="frpc"
        fi

        # 获取服务状态
        status=$(systemctl is-active "$service_name")
        if [ "$status" = "active" ]; then
            status_display="\e[1;32mactive\033[0m" 
        else
            status_display="\e[1;31minactive\033[0m" 
        fi

        # 服务状态
        echo -e "\e[1;35m服务运行状态: ${status_display}\033[0m\n\n" 
        
    else
        red "未找到配置信息文件，请先安装FRP服务\n"
    fi
    
    read -rsn1 -p "$(red "按任意键返回主菜单...")"
    echo
    main_menu
}

server_config() {
    reading "请输入FRP服务端监听端口 [默认: 7000]: " BIND_PORT
    BIND_PORT=${BIND_PORT:-"7000"}
    green "服务端监听端口为：$BIND_PORT"
    
    reading "请输入认证TOKEN [回车将自动随机生成]: " TOKEN
    [ -z "$TOKEN" ] && TOKEN=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 16)
    green "验证token为：$TOKEN"
    
    reading "请输入web端口 [默认: 7500]: " DASHBOARD_PORT
    DASHBOARD_PORT=${DASHBOARD_PORT:-"7500"}
    green "web端口为：$DASHBOARD_PORT"
    
    reading "请输入web用户名 [默认: admin]: " DASHBOARD_USER
    DASHBOARD_USER=${DASHBOARD_USER:-"admin"}
    green "web登录用户名为：$DASHBOARD_USER"
    
    reading "请输入web登录密码 [默认: 回车将随机生成]: " DASHBOARD_PWD
    [ -z "$DASHBOARD_PWD" ] && DASHBOARD_PWD=$(openssl rand -hex 8)
    green "web登录密码为：$DASHBOARD_PWD"
}

install_server() {
    yellow "\n开始安装FRP服务端 v${FRP_VERSION}..."
    
    ARCH=$(get_arch)
    init_frp_dir
    download_frp "$ARCH"
    
    cat > ${FRP_DIR}/frps.toml <<EOF
bindAddr = "0.0.0.0"
bindPort = ${BIND_PORT}
quicBindPort = ${BIND_PORT}

auth.method = "token"
auth.token = "${TOKEN}"

webServer.addr = "0.0.0.0"
webServer.port = ${DASHBOARD_PORT}
webServer.user = "${DASHBOARD_USER}"
webServer.password = "${DASHBOARD_PWD}"

log.to = "/var/log/frps.log"
log.level = "info"
log.maxDays = 3

enablePrometheus = true
EOF

    cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=Frp Server Service
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=${FRP_DIR}/frps -c ${FRP_DIR}/frps.toml
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now frps >/dev/null 2>&1

    if [ "$(systemctl is-active frps)" = "active" ]; then
        echo -e "\n\e[1;35m服务状态: \e[1;32mactive\033[0m\n" 
        local SERVER_IP=$(get_server_ip)
        green "\nFRP服务端安装完成!\n"
        save_config_info "服务端" \
            "FRP版本号|${FRP_VERSION}" \
            "安装目录|${FRP_DIR}" \
            "监听IP|${SERVER_IP}" \
            "监听端口|${BIND_PORT}" \
            "认证TOKEN|${TOKEN}" \
            "web端口|${DASHBOARD_PORT}" \
            "web登录用户名|${DASHBOARD_USER}" \
            "web登录密码|${DASHBOARD_PWD}"
        yellow "====== 客户端与服务端通信信息 ======"
        green "监听端口: ${BIND_PORT}"
        green "监听IP: ${SERVER_IP}"
        green "认证TOKEN: ${TOKEN}\n"
        purple "====== web管理信息 ======"
        green "Web地址: http://${SERVER_IP}:${DASHBOARD_PORT}"
        green "用户名: ${DASHBOARD_USER}"
        green "登录密码: ${DASHBOARD_PWD}\n"
    else
        red "FRP服务端启动失败"
        systemctl status frps
        exit 1
    fi
}

client_config() {
    reading "请输入中继服务器公网IP: " SERVER_IP
    while [ -z "$SERVER_IP" ]; do
        reading "中继服务器IP不能为空，请重新输入: " SERVER_IP
    done
    green "FRP继服务器IP为：$SERVER_IP"
    
    reading "请输入中继服务器FRP端口 [默认: 7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-"7000"}
    green "FRP中继服务器通信端口为：$SERVER_PORT"
    
    reading "请输入认证TOKEN: " TOKEN
    while [ -z "$TOKEN" ]; do
        reading "TOKEN不能为空，请重新输入: " TOKEN
    done
    green "认证token为：$TOKEN"
    
    reading "请输入ssh远程映射端口 [默认: 6000]: " REMOTE_SSH_PORT
    REMOTE_SSH_PORT=${REMOTE_SSH_PORT:-"6000"}
    green "ssh远程映射端口为：$REMOTE_SSH_PORT"
}

install_client() {
    yellow "\n开始安装FRP客户端 v${FRP_VERSION}..."
    
    ARCH=$(get_arch)
    init_frp_dir
    download_frp "$ARCH"
    
    cat > ${FRP_DIR}/frpc.toml <<EOF
serverAddr = "${SERVER_IP}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${TOKEN}"

log.to = "/var/log/frpc.log"
log.level = "error"
log.maxDays = 3

transport.poolCount = 5
transport.heartbeatInterval = 10
transport.heartbeatTimeout = 30
transport.dialServerKeepalive = 10
transport.dialServerTimeout = 30
transport.tcpMuxKeepaliveInterval = 10

[[proxies]]
name = "ssh_$(hostname)"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${SSH_PORT}
remotePort = ${REMOTE_SSH_PORT}

# [[proxies]]
# name = "tcp-example"
# type = "tcp"
# localIP = "127.0.0.1"
# localPort = 60000
# remotePort = 60000

# [[proxies]]
# name = "udp-example"
# type = "udp"
# localIP = "127.0.0.1"
# localPort = 60001
# remotePort = 60001

EOF

    cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=Frp Client Service
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=${FRP_DIR}/frpc -c ${FRP_DIR}/frpc.toml
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now frpc >/dev/null 2>&1

    if [ "$(systemctl is-active frpc)" = "active" ]; then
        echo -e "\n\e[1;35m服务状态: \e[1;32mactive\033[0m\n"
        save_config_info "客户端" \
            "FRP版本号|${FRP_VERSION}" \
            "安装目录|${FRP_DIR}" \
            "中继服务器IP|${SERVER_IP}" \
            "中继服务器端口|${SERVER_PORT}" \
            "认证TOKEN|${TOKEN}" \
            "本地SSH端口|${SSH_PORT}" \
            "远程映射端口|${REMOTE_SSH_PORT}" \
            "root密码|${ROOT_PWD}"
        green "FRP客户端安装完成!\n"
        purple "====== SSH连接信息 ======"
        green "服务器IP: ${SERVER_IP}"
        green "SSH端口: ${REMOTE_SSH_PORT}"
        green "SSH用户: root"
        green "SSH密码: ${ROOT_PWD}"
        yellow "\n温馨提示: 确保服务端已开放端口 ${SERVER_PORT} 和 ${REMOTE_SSH_PORT}\n"
    else
        red "FRP客户端启动失败"
        systemctl status frpc
        exit 1
    fi
}

uninstall_frp() {
    yellow "\n开始卸载FRP..."
    
    systemctl stop frpc frps 2>/dev/null
    systemctl disable frpc frps 2>/dev/null
    rm -f /etc/systemd/system/frpc.service /etc/systemd/system/frps.service >/dev/null 2>&1
    systemctl daemon-reload
    
    [ -d "${FRP_DIR}" ] && {
        rm -rf "${FRP_DIR}"
        green "已删除FRP安装目录: ${FRP_DIR}"
    }
    
    rm -f /var/log/frps.log /var/log/frpc.log
    clear
    green "FRP卸载完成"
}

main_menu() {
    clear
    purple "\n======== FRP 管理脚本 ========\n"
    green "1. 安装 FRP 服务端 (公网服务器)\n"
    green "2. 安装 FRP 客户端 (内网服务器)\n"
    purple "3. 显示当前配置信息\n"
    red "4. 卸载 FRP\n"
    yellow "0. 退出脚本\n"
    yellow "=========================="
    
    reading "请选择操作 [0-4]: " CHOICE
    case $CHOICE in
        1)
            server_config
            show_config "服务端" \
                "FRP版本号|${FRP_VERSION}" \
                "安装目录|${FRP_DIR}" \
                "监听端口|${BIND_PORT}" \
                "认证TOKEN|${TOKEN}" \
                "web端口|${DASHBOARD_PORT}" \
                "web登录用户名|${DASHBOARD_USER}" \
                "web登录密码|${DASHBOARD_PWD}" 
            install_server
            ;;
        2)
            set_root_password
            client_config
            show_config "客户端" \
                "FRP版本号|${FRP_VERSION}" \
                "安装目录|${FRP_DIR}" \
                "中继服务器IP|${SERVER_IP}" \
                "中继服务器端口|${SERVER_PORT}" \
                "认证TOKEN|${TOKEN}" \
                "本地SSH端口|${SSH_PORT}" \
                "远程映射端口|${REMOTE_SSH_PORT}" \
                "root密码|${ROOT_PWD}"
            install_client
            ;;
        3)
            show_info
            ;;
        4)
            uninstall_frp
            exit 0
            ;;
        0)
            clear
            exit 0
            ;;
        *)
            red "无效选择，请重新输入"
            sleep 1
            main_menu
            ;;
    esac
    
    read -rsn1 -p "$(red "按任意键返回主菜单...")"
    echo
    main_menu
}

check_root
main_menu
