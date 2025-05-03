#!/bin/bash

# 集成式FRP内网穿透配置脚本（带卸载功能）
# 功能：
# 1. 安装客户端或服务端
# 2. 卸载FRP
# 3. 交互式配置
# 4. 自动设置SSH

red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# 全局配置
export FRP_VERSION=${FRP_VERSION:-'0.62.1'}  
export FRP_DIR=${FRP_DIR:-'/opt/frp'} 
export SSH_PORT=${SSH_PORT:-'22'} 

# 检查root权限
check_root() {
    [ "$(id -u)" != "0" ] && { red "错误: 此脚本需要以root权限运行"; exit 1; }
}

# 获取服务器IP（优先IPv4，无则IPv6）
get_server_ip() {
    local ipv4=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [ -n "$ipv4" ]; then
        echo "$ipv4"
    else
        ip -6 addr show scope global | grep -oP '(?<=inet6\s)[\da-f:]+' | head -1
    fi
}

# 检测系统架构
get_arch() {
    ARCH=$(uname -m)
    case ${ARCH} in
        x86_64|amd64) echo "amd64";;
        arm64|aarch64) echo "arm64";;
        *) red "不支持的架构: ${ARCH}"; exit 1;;
    esac
}

# 初始化FRP目录
init_frp_dir() {
    mkdir -p "${FRP_DIR}" || { red "创建FRP目录失败"; exit 1; }
    cd "${FRP_DIR}" || exit 1
}

# 下载和解压FRP
download_frp() {
    local ARCH=$1
    FRP_PACKAGE="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    
    [ ! -f "${FRP_PACKAGE}" ] && {
        yellow "下载frp v${FRP_VERSION}..."
        wget -q --show-progress "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_PACKAGE}" || {
            red "下载frp失败"; exit 1
        }
    }
    
    [ ! -d "frp_${FRP_VERSION}_linux_${ARCH}" ] && {
        tar -zxvf "${FRP_PACKAGE}" >/dev/null || { red "解压frp失败"; exit 1; }
    }
    
    ln -sf "frp_${FRP_VERSION}_linux_${ARCH}" current
    rm -f "${FRP_PACKAGE}"
}

# 设置root密码
set_root_password() {
    reading "请输入root密码 [提示: 回车留空将自动生成]: " ROOT_PWD
    [ -z "$ROOT_PWD" ] && {
        ROOT_PWD=$(openssl rand -hex 8)
        yellow "正在设置root密码,随机root密码为: $ROOT_PWD"
    }

    # 重置SSH配置
    lsof -i:22 | awk '/IPv4/{print $2}' | xargs kill -9 2>/dev/null || true
    echo -e '\nPermitRootLogin yes\nPasswordAuthentication yes' >> /etc/ssh/sshd_config
    echo "root:${ROOT_PWD}" | chpasswd || { red "root密码设置失败"; exit 1; }

    # 重启SSH服务
    systemctl unmask ssh containerd docker.socket docker 
    pkill dockerd
    pkill containerd
    systemctl restart ssh containerd docker.socket docker &>/dev/null

    [ "$(systemctl is-active ssh)" = "active" ] && green "SSH服务运行正常" || { red "SSH服务未运行"; exit 1; }
}

# 客户端配置
client_config() {
    reading "请输入中继服务器公网IP: " SERVER_IP
    while [ -z "$SERVER_IP" ]; do
        reading "中继服务器IP不能为空，请重新输入: " SERVER_IP
    done
    
    reading "请输入中继服务器FRP端口 [默认: 7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-"7000"}
    
    reading "请输入认证TOKEN: " TOKEN
    while [ -z "$TOKEN" ]; do
        reading "TOKEN不能为空，请重新输入: " TOKEN
    done
    
    reading "请输入远程映射端口 [默认: 6000]: " REMOTE_SSH_PORT
    REMOTE_SSH_PORT=${REMOTE_SSH_PORT:-"6000"}
}

# 服务端配置
server_config() {
    reading "请输入FRP服务端监听端口 [默认: 7000]: " BIND_PORT
    BIND_PORT=${BIND_PORT:-"7000"}
    
    reading "请输入认证TOKEN [回车将自动随机生成]: " TOKEN
    [ -z "$TOKEN" ] && {
        TOKEN=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 16)
    }
    
    reading "请输入管理端口 [默认: 7500]: " DASHBOARD_PORT
    DASHBOARD_PORT=${DASHBOARD_PORT:-"7500"}
    
    reading "请输入管理用户名 [默认: admin]: " DASHBOARD_USER
    DASHBOARD_USER=${DASHBOARD_USER:-"admin"}
    
    reading "请输入管理密码 [默认: 随机生成]: " DASHBOARD_PWD
    [ -z "$DASHBOARD_PWD" ] && DASHBOARD_PWD=$(openssl rand -hex 8)

}

# 显示配置确认
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

# 安装FRP客户端
install_client() {
    yellow "\n开始安装FRP客户端 v${FRP_VERSION}..."
    
    ARCH=$(get_arch)
    init_frp_dir
    download_frp "$ARCH"
    
    # 创建frpc配置
    cat > current/frpc.ini <<EOF
[common]
server_addr = ${SERVER_IP}
server_port = ${SERVER_PORT}
token = ${TOKEN}

[ssh-$(hostname)]
type = tcp
local_ip = 127.0.0.1
local_port = ${SSH_PORT}
remote_port = ${REMOTE_SSH_PORT}
EOF

    # 创建systemd服务
    cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=Frp Client Service
After=network.target

[Service]
Type=simple
User=nobody
Restart=on-failure
RestartSec=5s
ExecStart=${FRP_DIR}/current/frpc -c ${FRP_DIR}/current/frpc.ini
ExecReload=${FRP_DIR}/current/frpc reload -c ${FRP_DIR}/current/frpc.ini

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now frpc >/dev/null 2>&1

    if [ "$(systemctl is-active frpc)" = "active" ]; then
        green "\nFRP客户端安装完成!"
        yellow "连接信息:"
        green "服务器IP: ${SERVER_IP}"
        green "SSH端口: ${REMOTE_SSH_PORT}"
        green "密码: ${ROOT_PWD}"
        yellow "\n提示: 确保服务端已开放端口 ${SERVER_PORT} 和 ${REMOTE_SSH_PORT}\n"
    else
        red "FRP客户端启动失败"
        systemctl status frpc
        exit 1
    fi
}

# 安装FRP服务端
install_server() {
    yellow "\n开始安装FRP服务端 v${FRP_VERSION}..."
    
    ARCH=$(get_arch)
    init_frp_dir
    download_frp "$ARCH"
    
    # 创建frps配置
    cat > current/frps.ini <<EOF
[common]
bind_port = ${BIND_PORT}
token = ${TOKEN}

dashboard_port = ${DASHBOARD_PORT}
dashboard_user = ${DASHBOARD_USER}
dashboard_pwd = ${DASHBOARD_PWD}
enable_prometheus = true

log_file = /var/log/frps.log
log_level = info
log_max_days = 3
EOF

    # 创建systemd服务
    cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=Frp Server Service
After=network.target

[Service]
Type=simple
User=nobody
Restart=on-failure
RestartSec=5s
ExecStart=${FRP_DIR}/current/frps -c ${FRP_DIR}/current/frps.ini
ExecReload=${FRP_DIR}/current/frps reload -c ${FRP_DIR}/current/frps.ini

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now frps >/dev/null 2>&1

    if [ "$(systemctl is-active frps)" = "active" ]; then
        local SERVER_IP=$(get_server_ip)
        green "\nFRP服务端安装完成!\n"
        yellow "管理信息:"
        green "监听端口: ${BIND_PORT}"
        green "Web管理地址: http://${SERVER_IP}:${DASHBOARD_PORT}"
        green "用户名: ${DASHBOARD_USER}"
        green "登录密码: ${DASHBOARD_PWD}\n"
    else
        red "FRP服务端启动失败"
        systemctl status frps
        exit 1
    fi
}

# 卸载FRP
uninstall_frp() {
    yellow "\n开始卸载FRP..."
    
    # 停止服务
    systemctl stop frpc frps 2>/dev/null
    systemctl disable frpc frps 2>/dev/null
    
    # 删除服务文件
    rm -f /etc/systemd/system/frpc.service /etc/systemd/system/frps.service
    systemctl daemon-reload
    
    # 删除安装目录
    [ -d "${FRP_DIR}" ] && {
        rm -rf "${FRP_DIR}"
        green "已删除FRP安装目录: ${FRP_DIR}"
    }
    
    # 删除日志文件
    rm -f /var/log/frps.log /var/log/frpc.log
    clear
    green "FRP卸载完成"
}

# 主菜单
main_menu() {
    clear
    yellow "====== FRP 管理脚本 ======"
    purple "1. 安装 FRP 客户端 (内网服务器)"
    purple "2. 安装 FRP 中继服务端 (公网服务器)"
    purple "3. 卸载 FRP"
    purple "4. 退出脚本"
    yellow "=========================="
    
    reading "请选择操作 [1-4]: " CHOICE
    case $CHOICE in
        1)
            set_root_password
            client_config
            show_config "客户端" \
                "FRP版本号|${FRP_VERSION}" \
                "安装目录|${FRP_DIR}" \
                "中继服务器IP|${SERVER_IP}" \
                "中继服务器端口|${SERVER_PORT}" \
                "认证TOKEN|${TOKEN}" \
                "本地SSH端口|${SSH_PORT}" \
                "远程映射端口|${REMOTE_SSH_PORT}"
            install_client
            ;;
        2)
            server_config
            show_config "服务端" \
                "FRP版本号|${FRP_VERSION}" \
                "安装目录|${FRP_DIR}" \
                "监听端口|${BIND_PORT}" \
                "认证TOKEN|${TOKEN}" \
                "管理端口|${DASHBOARD_PORT}" \
                "管理用户名|${DASHBOARD_USER}" \
                "管理密码|${DASHBOARD_PWD}" 
            install_server
            ;;
        3)
            uninstall_frp
            exit 0
            ;;
        4)
            yellow "退出脚本"
            exit 0
            ;;
        *)
            red "无效选择，请重新输入"
            sleep 1
            main_menu
            ;;
    esac
    
    reading "按回车键返回主菜单..." _
    main_menu
}

check_root
main_menu
