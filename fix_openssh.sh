#!/bin/bash

OPENSSH_VERSION="9.8p1"
[ -f /etc/os-release ] && . /etc/os-release && OS=$ID || { echo -e "\e[1;91m无法检测操作系统类型。\e[0m"; exit 1; }

wait_for_lock() {
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo -e "\e[1;33m等待dpkg锁释放...\e[0m"
        sleep 1
    done
}

fix_dpkg() {
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a
}

install_dependencies() {
    wait_for_lock
    case $OS in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt update
            DEBIAN_FRONTEND=noninteractive apt install -y build-essential zlib1g-dev libssl-dev libpam0g-dev wget ntpdate -o Dpkg::Options::="--force-confnew"
            ;;
        centos|rhel|fedora)
            yum install -y epel-release
            yum groupinstall -y "Development Tools"
            yum install -y zlib-devel openssl-devel pam-devel wget ntpdate
            ;;
        alpine)
            apk add build-base zlib-dev openssl-dev pam-dev wget ntpdate
            ;;
        *)
            echo -e "\e[1;91m不支持的操作系统：$OS\e[0m"
            exit 1
            ;;
    esac
}

sync_time() {
    ntpdate time.nist.gov
}

check_openssh_version() {
    current_version=$(ssh -V 2>&1 | awk '{print $1}' | cut -d_ -f2 | cut -d'p' -f1)

    min_version=8.5
    max_version=9.7

    if awk -v ver="$current_version" -v min="$min_version" -v max="$max_version" 'BEGIN{if(ver>=min && ver<=max) exit 0; else exit 1}'; then
      echo -e "\e[1;91mSSH版本: $current_version  在8.5到9.7之间，需要更新。\e[0m"
    else
      echo -e "\e[1;32mSSH版本: $current_version  不在8.5到9.7之间，无需更新!\e[0m"
      exit 1
    fi

}

install_openssh() {
    wget --no-check-certificate https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz
    tar -xzf openssh-${OPENSSH_VERSION}.tar.gz
    cd openssh-${OPENSSH_VERSION}
    ./configure
    make
    make install
}

restart_ssh() {
    case $OS in
        ubuntu|debian)
            systemctl restart ssh
            ;;
        centos|rhel|fedora|rocky|almalinux)
            systemctl restart sshd
            ;;
        alpine)
            rc-service sshd restart
            ;;
        *)
            echo -e "\e[1;91m不支持的操作系统：$OS\e[0m"
            exit 1
            ;;
    esac
}

set_path_priority() {
    NEW_SSH_PATH=$(which sshd) 
    NEW_SSH_DIR=$(dirname "$NEW_SSH_PATH")

    if [[ ":$PATH:" != *":$NEW_SSH_DIR:"* ]]; then
        export PATH="$NEW_SSH_DIR:$PATH"
        echo "export PATH=\"$NEW_SSH_DIR:\$PATH\"" >> ~/.bashrc
    fi
}

verify_installation() {
    echo -e "\e[1;32mSSH版本信息：\e[0m"
    ssh -V
    sshd -V
}

clean_up() {
    cd ..
    rm -rf openssh-${OPENSSH_VERSION}*
}

main() {
    if [[ $OS == "ubuntu" || $OS == "debian" ]]; then
        fix_dpkg
    fi
    check_openssh_version
    install_dependencies
    sync_time
    install_openssh
    restart_ssh
    set_path_priority
    verify_installation
    clean_up
}
main
