#!/bin/bash

# 交互式内网穿透SSH配置脚本
# 功能：
# 1. 使用环境变量配置FRP参数（可自定义，有默认值）
# 2. 自动安装配置FRP客户端
# 3. 配置SSH并设置root密码

# 默认环境变量配置
export FRP_VERSION=${FRP_VERSION:-"0.54.0"}
export FRP_DIR=${FRP_DIR:-"/opt/frp"}
export SSH_PORT=${SSH_PORT:-"22"}

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
    echo "错误: 此脚本需要以root权限运行" >&2
    exit 1
fi

# 解除 SSH 和 Docker 服务的锁定，启用密码访问
systemctl unmask ssh containerd docker.socket docker
pkill dockerd
pkill containerd
systemctl start ssh containerd docker.socket docker &>/dev/null

# 交互式配置函数
function interactive_config {
    read -p "请输入中继服务器公网IP: " SERVER_IP
    while [ -z "$SERVER_IP" ]; do
        read -p "中继服务器IP不能为空，请重新输入: " SERVER_IP
    done
    
    read -p "请输入中继服务器FRP端口 [默认: 7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-"7000"}
    
    read -p "请输入认证TOKEN: " TOKEN
    while [ -z "$TOKEN" ]; do
        read -p "TOKEN不能为空，请重新输入: " TOKEN
    done
    
    read -p "请输入远程映射端口 [默认: 6000]: " REMOTE_SSH_PORT
    REMOTE_SSH_PORT=${REMOTE_SSH_PORT:-"6000"}
}

# 重置SSH配置并设置root密码
function set_root_password {
    read -p "请输入root密码 [提示: 回车留空将自动生成]: " ROOT_PWD
    if [ -z "$ROOT_PWD" ]; then
        ROOT_PWD=$(openssl rand -hex 8)
        echo "正在设置root密码,随机root密码为: $ROOT_PWD"
    else
        echo "root:$ROOT_PWD" | chpasswd root
    fi    
    if [ $? -eq 0 ]; then
        echo "root密码设置成功"
    else
        echo "root密码设置失败"
    fi

    # 备份原有配置
    if [ -f "/etc/ssh/sshd_config" ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    fi
    
    # 创建新的SSH配置
    cat > /etc/ssh/sshd_config <<'EOF'
# This is the sshd server system-wide configuration file.  See
# sshd_config(5) for more information.

# This sshd was compiled with PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games

# The strategy used for options in the default sshd_config shipped with
# OpenSSH is to specify options with their default value where
# possible, but leave them commented.  Uncommented options override the
# default value.

# Include /etc/ssh/sshd_config.d/*.conf

#Port 22
#AddressFamily any
#ListenAddress 0.0.0.0
#ListenAddress ::

#HostKey /etc/ssh/ssh_host_rsa_key
#HostKey /etc/ssh/ssh_host_ecdsa_key
#HostKey /etc/ssh/ssh_host_ed25519_key

# Ciphers and keying
#RekeyLimit default none

# Logging
#SyslogFacility AUTH
#LogLevel INFO

# Authentication:

#LoginGraceTime 2m
PermitRootLogin yes
#StrictModes yes
#MaxAuthTries 6
#MaxSessions 10

#PubkeyAuthentication yes

# Expect .ssh/authorized_keys2 to be disregarded by default in future.
#AuthorizedKeysFile     .ssh/authorized_keys .ssh/authorized_keys2

#AuthorizedPrincipalsFile none

#AuthorizedKeysCommand none
#AuthorizedKeysCommandUser nobody

# For this to work you will also need host keys in /etc/ssh/ssh_known_hosts
#HostbasedAuthentication no
# Change to yes if you don't trust ~/.ssh/known_hosts for
# HostbasedAuthentication
#IgnoreUserKnownHosts no
# Don't read the user's ~/.rhosts and ~/.shosts files
#IgnoreRhosts yes

# To disable tunneled clear text passwords, change to no here!
PasswordAuthentication yes
#PermitEmptyPasswords no

# Change to yes to enable challenge-response passwords (beware issues with
# some PAM modules and threads)
KbdInteractiveAuthentication no

# Kerberos options
#KerberosAuthentication no
#KerberosOrLocalPasswd yes
#KerberosTicketCleanup yes
#KerberosGetAFSToken no

# GSSAPI options
#GSSAPIAuthentication no
#GSSAPICleanupCredentials yes
#GSSAPIStrictAcceptorCheck yes
#GSSAPIKeyExchange no

# Set this to 'yes' to enable PAM authentication, account processing,
# and session processing. If this is enabled, PAM authentication will
# be allowed through the KbdInteractiveAuthentication and
# PasswordAuthentication.  Depending on your PAM configuration,
# PAM authentication via KbdInteractiveAuthentication may bypass
# the setting of "PermitRootLogin without-password".
# If you just want the PAM account and session checks to run without
# PAM authentication, then enable this but set PasswordAuthentication
# and KbdInteractiveAuthentication to 'no'.
UsePAM yes

#AllowAgentForwarding yes
#AllowTcpForwarding yes
#GatewayPorts no
X11Forwarding yes
#X11DisplayOffset 10
#X11UseLocalhost yes
#PermitTTY yes
PrintMotd no
#PrintLastLog yes
#TCPKeepAlive yes
#PermitUserEnvironment no
#Compression delayed
#ClientAliveInterval 0
#ClientAliveCountMax 3
#UseDNS no
#PidFile /run/sshd.pid
#MaxStartups 10:30:100
#PermitTunnel no
#ChrootDirectory none
#VersionAddendum none

# no default banner path
#Banner none

# Allow client to pass locale environment variables
AcceptEnv LANG LC_*

# override default of no subsystems
Subsystem       sftp    /usr/lib/openssh/sftp-server

# Example of overriding settings on a per-user basis
#Match User anoncvs
#       X11Forwarding no
#       AllowTcpForwarding no
#       PermitTTY no
#       ForceCommand cvs server
EOF

    # 重启SSH服务
    systemctl restart ssh
    echo "SSH配置已重置并重启服务"

}

# 显示配置确认信息
function show_config {
    echo -e "\n============= 配置确认 ============="
    echo "FRP版本号:       $FRP_VERSION"
    echo "安装目录:        $FRP_DIR"
    echo "中继服务器IP:    $SERVER_IP"
    echo "中继服务器端口:  $SERVER_PORT"
    echo "认证TOKEN:       $TOKEN"
    echo "本地SSH端口:     $SSH_PORT"
    echo "远程映射端口:    $REMOTE_SSH_PORT"
    echo "===================================="
    
    read -p "确认以上配置是否正确？(y/n) [默认: y]: " CONFIRM
    CONFIRM=${CONFIRM:-"y"}
    if [[ "${CONFIRM,,}" != "y" && "${CONFIRM,,}" != "yes" ]]; then
        echo "配置已取消，请重新运行脚本"
        exit 1
    fi
}

# 安装FRP客户端
function install_frp {
    echo -e "\n开始安装FRP客户端 v${FRP_VERSION}..."
    
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
            echo "不支持的架构: ${ARCH}"
            exit 1
            ;;
    esac

    # 下载frp
    FRP_PACKAGE="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    if [ ! -f "${FRP_PACKAGE}" ]; then
        echo "下载frp v${FRP_VERSION}..."
        wget "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_PACKAGE}" || {
            echo "下载frp失败"
            exit 1
        }
    fi

    # 解压frp
    if [ ! -d "frp_${FRP_VERSION}_linux_${ARCH}" ]; then
        tar -zxvf ${FRP_PACKAGE} || {
            echo "解压frp失败"
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
    echo -e "\nFRP服务状态:"
    systemctl status frpc --no-pager
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
echo -e "\n安装完成!"
echo "现在可以通过以下ssh配置连接到此服务器:"
echo "host: ${SERVER_IP}"
echo "ssh port: ${REMOTE_SSH_PORT}"
echo "root password: $ROOT_PWD"
echo "\n\n重要提示："
echo "1. 请确保中继服务器已正确配置FRP服务端"
echo "2. 确保中继服务器的防火墙已开放 ${SERVER_PORT} 和 ${REMOTE_SSH_PORT} 端口"
echo "3. 如需修改配置，请编辑 ${FRP_DIR}/current/frpc.ini 后执行: systemctl restart frpc"
echo "4. 新的SSH配置已启用root密码登录"