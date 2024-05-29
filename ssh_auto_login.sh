#!/bin/bash

# 根据对应系统安装依赖
distro=$(lsb_release -si)

install_cmd=""

case "$distro" in
    Debian|Ubuntu)
        install_cmd="apt-get install -y"
        ;;
    CentOS)
        install_cmd="yum install -y"
        ;;
    Alpine)
        install_cmd="apk add"
        ;;
    *)
        echo "Unknown system: $distro"
        exit 1
        ;;
esac
$install_cmd sshpass

# 服务器列表，格式为 "user@hostname:port:password"
servers=(
    "user@hostname:port:password"
    "user@hostname:port:password"
    "user@hostname:port:password"
    "user@hostname:port:password"
    # 添加更多服务器
)

# 遍历服务器列表并尝试登录
for server in "${servers[@]}"
do
    host=$(echo $server | cut -d':' -f1)
    port=$(echo $server | cut -d':' -f2)
    password=$(echo $server | cut -d':' -f3)
    
    sshpass -p $password ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p $port $host "exit" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        if [[ ! " ${successful_connections[@]} " =~ " ${server} " ]]; then
            echo -e "\e[1;32mSuccessfully logged into $host \033[0m"
            successful_connections+=("$server")
        fi
    else
        echo -e "\e[1;91mFailed to log into $host \033[0m"
    fi
done   

sleep 2

# 断开成功的连接
for connection in "${successful_connections[@]}"
do
    host=$(echo $connection | cut -d':' -f1)
    port=$(echo $connection | cut -d':' -f2)
    sshpass -p $password ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p $port $host "exit" >/dev/null 2>&1
    echo -e "\e[1;32mDisconnected from $host\033[0m"
done

# 添加任务，每7天登录一次
(crontab -l 2>/dev/null; echo "0 0 */7 * * /bin/bash /root/ssh_auto_login.sh >> /root/login.log 2>&1") | crontab -
echo -e "\e[1;32mAuto login ssh task is created\033[0m"
