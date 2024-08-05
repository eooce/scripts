#!/bin/bash

export VERSION=${VERSION:-'17.5'}  

red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
plain="\033[0m"

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 请root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "alpine"; then
    release="alpine"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未知系统！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="amd64"
    echo -e "${red}未知的系统架构: ${arch}${plain}"
fi


if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
if [[ "${release}" == "centos" ]]; then
    yum install epel-release -y
    yum install wget unzip -y
elif [[ "${release}" == "alpine" ]]; then
    apk update
    apk add wget unzip
else
    apt update
    apt install wget unzip -y
fi
}

Disable_automatic_updates() {
echo -e "${green}开始修改nezha-agent服务"
if [[ "${release}" == "alpine" ]]; then
    if [ -f /etc/init.d/nezha-agent ]; then
        echo -e "${green}/etc/init.d/nezha-agent服务存在,开始尝试禁用自动更新 ${plain}"
        sed -i '/command_args=/ s/"$/ --disable-auto-update --disable-force-update"/' /etc/init.d/nezha-agent
        echo -e "${green}=========================================== ${plain}"
        cat /etc/init.d/nezha-agent  
    else
        echo -e "${yellow}/etc/init.d/nezha-agent服务不存在,请尝试手动修改${plain}"
    fi
else
    if [ -f /etc/systemd/system/nezha-agent.service ]; then
        echo -e "${green}/etc/systemd/system/nezha-agent.service服务存在,开始尝试禁用自动更新${plain}"
        sudo sed -i '/^ExecStart=/ s/$/ --disable-auto-update --disable-force-update/' /etc/systemd/system/nezha-agent.service
        echo -e "${green}=========================================== ${plain}"   
        cat /etc/systemd/system/nezha-agent.service
    else
        echo -e "${yellow}/etc/systemd/system/nezha-agent.service服务不存在,请尝试手动修改${plain}"
    fi
fi
}

Downlond_agent(){
echo -e "${green}开始尝试降级Agent"
    if [ -f /opt/nezha/agent/nezha-agent ]; then
        echo -e "${green}=========================================== ${plain}"        
        echo -e "${green}/opt/nezha/agent/nezha-agent存在,开始尝试降级到${VERSION}${plain}"
        echo -e "${green}检测到系统为: ${release} 架构: ${arch} ${plain}"

        if [[ "${arch}" == "amd64" ]]; then
            wget https://github.com/nezhahq/agent/releases/download/v0.${VERSION}/nezha-agent_linux_amd64.zip && unzip nezha-agent_linux_amd64.zip && rm nezha-agent_linux_amd64.zip && mv nezha-agent /opt/nezha/agent/nezha-agent
        elif [[ "${arch}" == "arm64" ]]; then
            wget https://github.com/nezhahq/agent/releases/download/v0.${VERSION}/nezha-agent_linux_arm64.zip && unzip nezha-agent_linux_arm64.zip && rm nezha-agent_linux_arm64.zip && mv nezha-agent /opt/nezha/agent/nezha-agent
        fi
    else
       echo -e "${yellow}/opt/nezha/agent/nezha-agent不存在,请尝试手动降级${plain}"
    fi
}

restart_agent(){
echo -e "${green}开始尝试重启agent服务${plain}"
if [[ "${release}" == "centos" ]]; then
sudo systemctl daemon-reload
systemctl restart nezha-agent

elif [[ "${release}" == "alpine" ]]; then
    chmod +x /etc/init.d/nezha-agent
    rc-update add nezha-agent default
    rc-service nezha-agent restart
else
    sudo systemctl daemon-reload
    systemctl restart nezha-agent
fi

if [ $? -eq 0 ]; then
    echo -e "${green}nezha-agent服务已成功重启\n${plain}"
else
    echo -e "${red}nezha-agent服务重启失败\n${plain}"
fi
}

echo -e "${green}当前系统为: ${release} 架构: ${arch} ${plain}"

install_base
Disable_automatic_updates
sleep 1
        echo -e "${green}=========================================== ${plain}" 
        echo -e "${green}请自行判断配置是否正确 ${plain}" 
Downlond_agent
restart_agent
