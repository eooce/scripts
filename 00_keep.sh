#!/bin/bash

SCRIPT_PATH="/root/00_keep.sh"  # 脚本路径

export HOST=${HOST:-'s11.serv00.com'}   # serv00服务器或IP
export TCP_PORT=${TCP_PORT:-'1234'}     # 四合一vmess端口
export UDP1_PORT=${UDP1_PORT:-'5678'}   # 四合一hy2端口
export UDP2_PORT=${UDP2_PORT:-'6789'}   # 四合一tuic端口

export SSH_USER=${SSH_USER:-'abcd'}  # serv00或ct8账号
export SSH_PASS=${SSH_PASS:-'12345678'}  # serv00或ct8密码

# 最大尝试检测次数
MAX_ATTEMPTS=5

attempt=0

# 根据对应系统安装依赖
install_packages() {
    if [ -f /etc/debian_version ]; then
        package_manager="DEBIAN_FRONTEND=noninteractive apt-get install -y"
    elif [ -f /etc/redhat-release ]; then
        package_manager="yum install -y"
    elif [ -f /etc/fedora-release ]; then
        package_manager="dnf install -y"
    elif [ -f /etc/alpine-release ]; then
        package_manager="apk add"
    else
        echo -e"${red}不支持的系统架构！${reset}"
        exit 1
    fi
    $package_manager sshpass curl netcat-openbsd cron > /dev/null
}
install_packages
clear

# 添加定时任务的函数
add_cron_job() {
  if ! crontab -l | grep -q "$SCRIPT_PATH"; then
    (crontab -l; echo "*/2 * * * * /bin/bash $SCRIPT_PATH >> /root/keep.log 2>&1") | crontab -
    echo -e "\e[1;32m已添加定时任务，每两分钟执行一次\e[0m"
  else
    echo -e "\e[1;35m定时任务已存在，跳过添加计划任务\e[0m"
  fi
}
add_cron_job

# 检测 TCP 端口是否通畅
check_tcp_port() {
  nc -zv $HOST $TCP_PORT &> /dev/null
  return $?
}

# 连接ssh并执行远程命令
run_remote_command() {
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$HOST \
    "VMESS_PORT=$TCP_PORT HY2_PORT=$UDP1_PORT TUIC_PORT=$UDP2_PORT bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sb_00.sh)"
}

# 循环检测
while [ $attempt -lt $MAX_ATTEMPTS ]; do
  if check_tcp_port; then
    echo -e "\e[1;32m程序已运行，TCP 端口 $TCP_PORT 通畅\e[0m\n"
    exit 0
  else
    echo -e "\e[1;33mTCP 端口 $TCP_PORT 不通畅，进程可能不存在，休眠30s后重试\e[0m"
    sleep 30
    attempt=$((attempt+1))
  fi
done

# 如果达到最大尝试次数，连接服务器并执行远程命令
if [ $attempt -ge $MAX_ATTEMPTS ]; then
  echo -e "\e[1;33m多次检测失败，尝试通过 SSH 连接并执行命令\e[0m"
  if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$HOST -q exit; then
    echo -e "\e[1;32mSSH远程连接成功!\e[0m"
    output=$(run_remote_command)
    echo -e "\e[1;35m远程命令执行结果：\e[0m\n"
    echo "$output"
  else
    echo -e "\e[1;33m连接失败，请检查你的账户和密码\e[0m\n"
  fi
fi
