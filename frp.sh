#!/bin/bash

# 交互式内网穿透SSH配置脚本
# 功能：
# 1. 使用环境变量配置FRP参数（可自定义，有默认值）
# 2. 自动安装配置FRP客户端
# 3. 配置SSH并设置root密码

red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# 默认环境变量配置
export FRP_VERSION=${FRP_VERSION:-"0.54.0"}
export FRP_DIR=${FRP_DIR:-"/opt/frp"}
export SSH_PORT=${SSH_PORT:-"22"}

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
    red "错误: 此脚本需要以root权限运行" >&2
    exit 1
fi

# 交互式配置函数
function interactive_config {
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

# 重置SSH配置并设置root密码
function set_root_password {
    reading "请输入root密码 [提示: 回车留空将自动生成]: " ROOT_PWD
    if [ -z "$ROOT_PWD" ]; then
        ROOT_PWD=$(openssl rand -hex 8)
        yellow "正在设置root密码,随机root密码为: $ROOT_PWD"
    else
        ROOT_PWD=$ROOT_PWD
    fi    

    lsof -i:22 | awk '/IPv4/{print $2}' | xargs kill -9 2>/dev/null || true
    echo -e '\nPermitRootLogin yes\nPasswordAuthentication yes' >> /etc/ssh/sshd_config
    echo root:$ROOT_PWD | chpasswd root

    if [ $? -eq 0 ]; then
        green "root密码设置成功"
    else
        red "root密码设置失败"
    fi

    systemctl unmask ssh containerd docker.socket docker
    pkill dockerd
    pkill containerd
    systemctl start ssh containerd docker.socket docker &>/dev/null

    # 检查ssh是否运行
    [ "$(systemctl is-active ssh)" = "active" ] && green "SSH服务运行正常" && return 0 || red "SSH服务未运行,请执行 systemctl status ssh 检查" && exit 1

}

# 显示配置确认信息
function show_config {
    yellow "\n============= 配置确认 ============="
    purple "FRP版本号:       $FRP_VERSION"
    purple "安装目录:        $FRP_DIR"
    purple "中继服务器IP:    $SERVER_IP"
    purple "中继服务器端口:  $SERVER_PORT"
    purple "认证TOKEN:       $TOKEN"
    purple "本地SSH端口:     $SSH_PORT"
    purple "远程映射端口:    $REMOTE_SSH_PORT"
    purple "===================================="
    
    reading "确认以上配置是否正确？(y/n) [默认: y]: " CONFIRM
    CONFIRM=${CONFIRM:-"y"}
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        yellow "配置已取消，请重新运行脚本"
        exit 1
    fi
}

# 安装FRP客户端
function install_frp {
    yellow "\n开始安装FRP客户端 v${FRP_VERSION}..."
    
    # 创建frp安装目录
    mkdir -p ${FRP_DIR}
    cd ${FRP_DIR} || exit 1

    # 检测系统架构
    ARCH=$(uname -m)
    case ${ARCH} in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            red "不支持的架构: ${ARCH}"
            exit 1
            ;;
    esac

    # 下载frp
    FRP_PACKAGE="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    if [ ! -f "${FRP_PACKAGE}" ]; then
        yellow "下载frp v${FRP_VERSION}..."
        wget "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_PACKAGE}" &>/dev/null || {
            red "下载frp失败"
            exit 1
        }
    fi

    # 解压frp
    if [ ! -d "frp_${FRP_VERSION}_linux_${ARCH}" ]; then
        tar -zxvf ${FRP_PACKAGE} &>/dev/null || {
            red "解压frp失败"
            exit 1
        }
    fi

    # 创建软链接
    ln -sf "frp_${FRP_VERSION}_linux_${ARCH}" current

    rm -rf frp_${FRP_VERSION}_linux_${ARCH}.tar.gz
    # 创建frpc配置
    cat > ${FRP_DIR}/current/frpc.ini <<EOF
[common]
server_addr = ${SERVER_IP}
server_port = ${SERVER_PORT}
token = ${TOKEN}

[ssh]
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

    # 重载systemd
    systemctl daemon-reload

    # 启动frpc服务
    systemctl enable frpc
    systemctl start frpc

    # 检查服务状态
    [ "$(systemctl is-active frpc)" = "active" ] && green "FRP运行正常" && return 0 || red "FRP运行未运行,请执行 systemctl status frpc 检查" && exit 1
}

# 1. 设置root密码
set_root_password

# 2. 交互式配置
interactive_config

# 3. 显示配置确认
show_config

# 4. 安装FRP客户端
install_frp

# 完成信息
green "\n安装完成!"
yellow "现在可以通过以下ssh配置连接到此服务器:\n"
green "host: ${SERVER_IP}"
green "port: ${REMOTE_SSH_PORT}"
green "password: $ROOT_PWD"
yellow "\n\n重要提示："
yellow "1. 请确保中继服务器已正确配置FRP服务端"
yellow "2. 确保中继服务器的防火墙已开放 ${SERVER_PORT} 和 ${REMOTE_SSH_PORT} 端口"
yellow "3. 如需修改配置，请编辑 ${FRP_DIR}/current/frpc.ini 后执行: systemctl restart frpc"
yellow "4. 新的SSH配置已启用root密码登录"