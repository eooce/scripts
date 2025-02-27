#!/bin/bash

re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(yellow "$1")" "$2"; }

WORKDIR="nezha"
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
KEEP_PATH="${HOME}/domains/keep.${USERNAME}.serv00.net/public_nodejs" 
mkdir -p "$WORKDIR" && chmod +x "$WORKDIR"

# 获取命令行参数
dashboard_version=${1:-"v1"}  # 默认值为 v1
custom_domain=${2:-"${USERNAME}.serv00.net"}  # 默认值为用户名的域名

choose_verison() {
    if [[ "$dashboard_version" == "v0" ]]; then
        dashboard_version="v0"
    elif [[ "$dashboard_version" == "v1" ]]; then
        dashboard_version="v1"
    else
        red "无效的选项, 请重新输入"
        exit 1
    fi
}

check_port () {
  clear
  purple "\n正在安装中,请稍等..."
  port_list=$(devil port list)
  tcp_ports=$(echo "$port_list" | grep -c "tcp")
  udp_ports=$(echo "$port_list" | grep -c "udp")

  if [[ $tcp_ports -lt 2 ]]; then
      red "没有足够的TCP端口,正在调整..."

      if [[ $udp_ports -ge 3 ]]; then
          udp_ports_to_delete=$(echo "$port_list" | awk '/udp/ {print $1}' | head -n 2)
          for udp_port in $udp_ports_to_delete; do
              devil port del udp $udp_port  >/dev/null 2>&1
              green "已删除udp端口: $udp_port"
          done
      elif [[ $udp_ports -eq 2 ]]; then
          udp_port_to_delete=$(echo "$port_list" | awk '/udp/ {print $1}' | head -n 1)
          devil port del udp $udp_port_to_delete  >/dev/null 2>&1
          green "已删除udp端口: $udp_port_to_delete"
      fi

      tcp_ports_to_add=$((2 - tcp_ports))
      for ((i=1; i<=tcp_ports_to_add; i++)); do
          while true; do
              tcp_port=$(shuf -i 10000-65535 -n 1)
              result=$(devil port add tcp $tcp_port 2>&1)
              if [[ $result == *"succesfully"* ]]; then
                  green "已添加TCP端口: $tcp_port"
                  if [[ $i -eq 1 ]]; then
                      tcp_port1=$tcp_port
                  else
                      tcp_port2=$tcp_port
                  fi
                  break
              else
                  yellow "端口 $tcp_port 不可用，尝试其他端口..."
              fi
          done
      done

      green "端口已自动为你调整完成, 将断开SSH连接, 请重新连接SSH并重新执行脚本"
      devil binexec on >/dev/null 2>&1
      kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1
  else
      tcp_ports=$(echo "$port_list" | awk '/tcp/ {print $1}')
      tcp_port1=$(echo "$tcp_ports" | sed -n '1p')
      tcp_port2=$(echo "$tcp_ports" | sed -n '2p')
  fi

  export DASHBOARD_PORT=$tcp_port1
  export AGENT_PORT=$tcp_port2
}

get_ip() {
  IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
  API_URL="https://status.eooce.com/api"
  IP=""
  THIRD_IP=${IP_LIST[2]}
  RESPONSE=$(curl -s --max-time 2 "${API_URL}/${THIRD_IP}")
  if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
      IP=$THIRD_IP
  else
      FIRST_IP=${IP_LIST[0]}
      RESPONSE=$(curl -s --max-time 2 "${API_URL}/${FIRST_IP}")
      
      if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
          IP=$FIRST_IP
      else
          IP=${IP_LIST[1]}
      fi
  fi
  echo "$IP"
}

check_cmd() {
  if command -v curl &>/dev/null; then
        DOWNLOAD_CMD="curl -sLO"
  elif command -v wget &>/dev/null; then
        DOWNLOAD_CMD="wget -q"
  else
        red "Error: Neither curl nor wget found. cannot download!"
        exit 1
  fi
}

seetting_web () {
    dashboard_doamin="$custom_domain"

    devil www del $dashboard_doamin >/dev/null 2>&1
    green "初始化站点..."
    if devil www add $dashboard_doamin proxy localhost $DASHBOARD_PORT 2>&1 | grep -q "succesfully"; then
        green "创建面板站点成功"
        devil www options $dashboard_doamin sslonly on  >/dev/null 2>&1
        devil ssl www add $available_ip le le $dashboard_doamin >/dev/null 2>&1 
        green "面板强制HTTPS设置成功"
    else
        red "网站创建失败！请执行以下所有命令后重装(可一起运行): \ndevil www del $USERNAME.serv00.net\nrm -rf $HOME/$USERNAME/domains/*\nshopt -s extglob dotglob\nrm -rf $HOME/!(domains|mail|repo|backup)\n"
        exit 1
    fi
}

download_v1() {
$DOWNLOAD_CMD https://github.com/eooce/test/releases/download/freebsd/v1_dashboard.zip >/dev/null 2>&1
mv v1_dashboard.zip $WORKDIR/v1_dashboard.zip >/dev/null 2>&1
cd $WORKDIR >/dev/null 2>&1
unzip v1_dashboard.zip >/dev/null 2>&1
rm -rf v1_dashboard.zip >/dev/null 2>&1
mv v1_dashboard dashboard >/dev/null 2>&1
chmod +x dashboard >/dev/null 2>&1
./dashboard >/dev/null 2>&1 &
sleep 1
} 

change_config () {
pkill dashboard >/dev/null 2>&1
sed -i '' "s/^language: .*/language: zh_CN/"  data/config.yaml
sed -i '' "s/^sitename: .*/sitename: 哪吒面板/"  data/config.yaml
sed -i '' "s/^listenport: [0-9]*/listenport: $DASHBOARD_PORT/" data/config.yaml
sed -i '' "s|^installhost: .*|installhost: \"${USERNAME}.serv00.net:$DASHBOARD_PORT\"|" data/config.yaml

}

run_dashboard() {
    if [[ ! -f "./dashboard" ]]; then  
        red "错误: dashboard 文件不存在，请检查路径"
        exit 1
    fi

    chmod +x "./dashboard" >/dev/null 2>&1 &
    nohup "./dashboard" >/dev/null 2>&1 &

    sleep 5

    if pgrep -x dashboard > /dev/null; then
        green "\n哪吒面板正在运行"
        green "哪吒面板安装完成\n\n访问: https://$dashboard_doamin 查看  面板使用的端口：$DASHBOARD_PORT, v1面板后台默认用户名和密码为admin,请及时修改\n\n"
    else
        red "\n哪吒面板运行失败..."
        red "请删除nezha文件夹重新运行"
        exit 1
    fi
}

install_keepalive () {
    purple "正在安装全自动保活服务中,请稍等......"
    [ -d "$KEEP_PATH" ] || mkdir -p "$KEEP_PATH"
    $DOWNLOAD_CMD "https://00.ssss.nyc.mn/dashboard.js" >/dev/null 2>&1
    mv dashboard.js "$KEEP_PATH/app.js" >/dev/null 2>&1
    devil www add keep.${USERNAME}.serv00.net nodejs /usr/local/bin/node18 > /dev/null 2>&1
    # ip_address=$(devil vhost list | sed -n '5p' | awk '{print $1}')
    # devil ssl www add $ip_address le le keep.${USERNAME}.serv00.net > /dev/null 2>&1
    ln -fs /usr/local/bin/node18 ~/bin/node > /dev/null 2>&1
    ln -fs /usr/local/bin/npm18 ~/bin/npm > /dev/null 2>&1
    mkdir -p ~/.npm-global
    npm config set prefix '~/.npm-global'
    echo 'export PATH=~/.npm-global/bin:~/bin:$PATH' >> $HOME/.bash_profile && source $HOME/.bash_profile
    rm -rf $HOME/.npmrc > /dev/null 2>&1
    cd ${KEEP_PATH} && npm install dotenv axios --silent > /dev/null 2>&1
    rm $HOME/domains/keep.${USERNAME}.serv00.net/public_nodejs/public/index.html > /dev/null 2>&1
    rm $HOME/domains/${USERNAME}.serv00.net/public_html/index.html > /dev/null 2>&1
    # devil www options keep.${USERNAME}.serv00.net sslonly on > /dev/null 2>&1
    if devil www restart keep.${USERNAME}.serv00.net 2>&1 | grep -q "succesfully"; then
        green "\n哪吒面板全自动保活服务安装成功\n\n"
        purple "访问 http://keep.${USERNAME}.serv00.net/stop 结束进程\n"
        purple "访问 http://keep.${USERNAME}.serv00.net/list 全部进程列表\n"
        yellow "访问 http://keep.${USERNAME}.serv00.net/start 调起保活程序\n"
        purple "访问 http://keep.${USERNAME}.serv00.net/status 查看进程状态\n\n"
        curl -sk "https://keep.${USERNAME}.serv00.net/start" | grep -q "running" && green "\n哪吒面板运行正常,全自动保活任务添加成功\n" || red "\n存在未运行的进程,请访问 http://keep.${USERNAME}.serv00.net/status 检查,建议执行以下命令后重装: \ndevil www del $USERNAME.serv00.net\ndevil www del keep.$USERNAME.serv00.net\nrm -rf $HOME/$USERNAME/domains/*\nshopt -s extglob dotglob\nrm -rf $HOME/!(domains|mail|repo|backup)\n"
        purple "如果需要Telegram通知,请先在Telegram @Botfather 申请 Bot-Token,并带CHAT_ID和BOT_TOKEN环境变量运行\n\n"
    else
        red "全自动保活服务安装失败: \n${yellow}devil www del $USERNAME.serv00.net\ndevil www del keep.$USERNAME.serv00.net\nrm -rf $HOME/$USERNAME/domains/*\nshopt -s extglob dotglob\nrm -rf $HOME/!(domains|mail|repo)\n${red}请依次执行上述命令后重新安装!"
    fi
}

install_nezha_dashboard() {
    check_cmd
    choose_verison
    check_port
    seetting_web 
    if [ "$dashboard_version" == "v0" ]; then
        clear
        green "哪吒v0端口面版使用的端口: $DASHBOARD_PORT, 哪吒agent端口: $AGENT_PORT"
        [[ -d $WORKDIR ]] && mkdir -p $WORKDIR >/dev/null 2>&1
        mkdir -p ${WORKDIR}/data >/dev/null 2>&1
        $DOWNLOAD_CMD "https://github.com/eooce/test/releases/download/freebsd/v0_dashboard.zip"  -o "$WORKDIR/dashboard.zip" >/dev/null 2>&1
        unzip $WORKDIR/dashboard.zip -d $WORKDIR >/dev/null 2>&1
        rm -rf $WORKDIR/dashboard.zip >/dev/null 2>&1
        if [[ -f "$WORKDIR/dashboard" ]]; then
            green "开始安装哪吒面板..."
            chmod +x $WORKDIR/dashboard
            nohup ./$WORKDIR/dashboard >/dev/null 2>&1
            sleep 5
            echo "关于 Gitee Oauth2 应用：在 https://gitee.com/oauth/applications 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback"
            reading "请输入 OAuth2 提供商(github/gitlab/jihulab/gitee，默认 github): " nz_oauth2_type
            [[ -z "$nz_oauth2_type" ]] && nz_oauth2_type=github
            green "你使用的是 $nz_oauth2_type"
            reading "请输入 Oauth2 应用的 Client ID: " nz_github_oauth_client_id
            green "你的Client ID为: $nz_github_oauth_client_id"
            reading "请输入 Oauth2 应用的 Client Secret: " nz_github_oauth_client_secret
            green "你的Client Secret为: $nz_github_oauth_client_secret"
            reading "请输入 GitHub/Gitee 登录名作为管理员，多个以逗号隔开: " nz_admin_logins
            green "${nz_oauth2_type}管理员登录名为: $nz_admin_logins"
            reading "请输入站点标题: " nz_site_title 
            green "你的站点标题为：$nz_site_title"

            if [ -z "$nz_admin_logins" ] || [ -z "$nz_github_oauth_client_id" ] || [ -z "$nz_github_oauth_client_secret" ] || [ -z "$nz_site_title" ]; then
                red "error! 所有选项都不能为空"
                return 1
                rm -rf ${WORKDIR}
                exit
            fi

            sed -i '' "s/nz_language/zh-CN/" ${WORKDIR}/data/config.yaml >/dev/null 2>&1
            sed -i '' "s/80/${DASHBOARD_PORT}/" ${WORKDIR}/data/config.yaml >/dev/null 2>&1
            sed -i '' "s/nz_grpc_port/${AGENT_PORT}/" ${WORKDIR}/data/config.yaml >/dev/null 2>&1
            sed -i '' "s/nz_site_title/${nz_site_title}/" ${WORKDIR}/data/config.yaml >/dev/null 2>&1
            sed -i '' "s/nz_oauth2_type/${nz_oauth2_type}/" ${WORKDIR}/data/config.yaml >/dev/null 2>&1
            sed -i '' "s/nz_admin_logins/${nz_admin_logins}/" ${WORKDIR}/data/config.yaml >/dev/null 2>&1
            sed -i '' "s/nz_github_oauth_client_id/${nz_github_oauth_client_id}/" ${WORKDIR}/data/config.yaml >/dev/null 2>&1
            sed -i '' "s/nz_github_oauth_client_secret/${nz_github_oauth_client_secret}/" ${WORKDIR}/data/config.yaml >/dev/null 2>&1

            run_dashboard
            yellow "温馨提醒: 添加agnet到面板的agent通信端口为: AGENT_PORT\n\n"
            install_keepalive
        else
            red "Error: Failed to download v0_dashboard"
            exit 1
        fi
    else
        green "哪吒v1面版使用的端口: $DASHBOARD_PORT"
        [[ -e "${WORKDIR}/dashboard" ]] && green "哪吒面板已经安装过,直接运行..." && cd nezha && run_dashboard || download_v1 && change_config && run_dashboard && install_keepalive && red "后台初始用户名和密码是admin/admin 请及时修改你的密码\n\n" && pkill bash >/dev/null 2>&1
    fi
}

install_nezha_dashboard
