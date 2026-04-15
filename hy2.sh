#!/bin/bash
# Hysteria2 Installation Script
# Author: https://1024.day

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

if [[ $EUID -ne 0 ]]; then
    clear
    echo -e "${RED}Error: This script must be run as root!${RESET}" 1>&2
    exit 1
fi

# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DETECTED_OS=$NAME
        OS_VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        DETECTED_OS=$(lsb_release -si)
        OS_VERSION=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DETECTED_OS=$DISTRIB_ID
        OS_VERSION=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        DETECTED_OS=Debian
        OS_VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        DETECTED_OS=openSUSE
    elif [ -f /etc/redhat-release ]; then
        DETECTED_OS=$(cat /etc/redhat-release | awk '{print $1}')
    else
        DETECTED_OS=$(uname -s)
        OS_VERSION=$(uname -r)
    fi
}

# 安装必要的包
install_packages() {
    detect_os
    
    echo "检测到操作系统: $DETECTED_OS $OS_VERSION"
    
    if command -v apt-get &> /dev/null; then
        echo "使用 APT 包管理器..."
        apt-get update -y
        apt-get install -y curl wget openssl gawk ca-certificates
    elif command -v yum &> /dev/null; then
        echo "使用 YUM 包管理器..."
        yum update -y
        yum install -y epel-release
        yum install -y curl wget openssl gawk ca-certificates
    elif command -v dnf &> /dev/null; then
        echo "使用 DNF 包管理器..."
        dnf update -y
        dnf install -y curl wget openssl gawk ca-certificates
    elif command -v zypper &> /dev/null; then
        echo "使用 Zypper 包管理器..."
        zypper refresh
        zypper install -y curl wget openssl gawk ca-certificates
    elif command -v pacman &> /dev/null; then
        echo "使用 Pacman 包管理器..."
        pacman -Syu --noconfirm
        pacman -S --noconfirm curl wget openssl gawk ca-certificates
    else
        echo "错误: 未找到支持的包管理器!"
        echo "请手动安装以下依赖: curl wget openssl gawk ca-certificates"
        exit 1
    fi
}

# 检查并启用 systemd 服务
check_systemd() {
    if ! command -v systemctl &> /dev/null; then
        echo "警告: systemctl 未找到，可能不支持 systemd"
        echo "请手动管理 hysteria 服务"
        return 1
    fi
    return 0
}

# 生成随机密码
generate_password() {
    if [ -f /proc/sys/kernel/random/uuid ]; then
        HYSTERIA_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    else
        HYSTERIA_PASSWORD=$(openssl rand -hex 16)
    fi
}

# 获取端口
get_port() {
    read -t 15 -p "回车或等待15秒为随机端口，或者自定义端口请输入(1-65535): " SERVER_PORT
    if [ -z "$SERVER_PORT" ]; then
        if command -v shuf &> /dev/null; then
            SERVER_PORT=$(shuf -i 2000-65000 -n 1)
        else
            SERVER_PORT=$((RANDOM % 63000 + 2000))
        fi
    fi
    
    if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
        echo "错误: 端口必须是 1-65535 之间的数字"
        exit 1
    fi
}

# 获取服务器IP
get_server_ips() {
    SERVER_IPV4=$(curl -s -4 --connect-timeout 5 https://api.ipify.org || echo "")
    SERVER_IPV6=$(curl -s -6 --connect-timeout 5 https://api64.ipify.org || echo "")
}

# 安装 Hysteria2
install_hysteria2() {
    echo "开始安装依赖包..."
    install_packages
    echo "生成随机密码..."
    generate_password
    echo "获取端口配置..."
    get_port
    echo "下载并安装 Hysteria2..."
    if ! bash <(curl -fsSL https://get.hy2.sh/); then
        echo "错误: Hysteria2 安装失败"
        exit 1
    fi
    echo "创建配置目录..."
    mkdir -p /etc/hysteria/
    echo "生成SSL证书..."
    if ! openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key \
        -out /etc/hysteria/server.crt \
        -subj "/CN=bing.com" -days 36500; then
        echo "错误: SSL证书生成失败"
        exit 1
    fi
    if id hysteria &> /dev/null; then
        chown hysteria:hysteria /etc/hysteria/server.key /etc/hysteria/server.crt
    fi
    chmod 600 /etc/hysteria/server.key
    chmod 644 /etc/hysteria/server.crt
    echo "创建 Hysteria2 配置文件..."
    cat > /etc/hysteria/config.yaml << EOF
listen: :$SERVER_PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $HYSTERIA_PASSWORD
  
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true

quic:
  initStreamReceiveWindow: 26843545 
  maxStreamReceiveWindow: 26843545 
  initConnReceiveWindow: 67108864 
  maxConnReceiveWindow: 67108864 
EOF
    echo "启动 Hysteria2 服务..."
    if check_systemd; then
        systemctl enable hysteria-server.service
        systemctl restart hysteria-server.service
        sleep 2
    else
        echo "请手动启动 Hysteria2 服务"
    fi
    cat > /etc/hysteria/hyclient.json << EOF
{
"server": "$(get_server_ip):${SERVER_PORT}",
"auth": "${HYSTERIA_PASSWORD}",
"tls": {
  "sni": "bing.com",
  "insecure": true
},
"quic": {
  "initStreamReceiveWindow": 26843545,
  "maxStreamReceiveWindow": 26843545,
  "initConnReceiveWindow": 67108864,
  "maxConnReceiveWindow": 67108864
}
}
EOF
    rm -f tcp-wss.sh hy2.sh
    clear
}

# 服务状态检查
check_service_status() {
    echo -e "${CYAN}===== 服务状态 =====${RESET}"
    if command -v systemctl &> /dev/null; then
        if systemctl is-active --quiet hysteria-server.service; then
            echo -e "${GREEN}✓ Hysteria2 服务运行正常${RESET}"
        else
            echo -e "${RED}✗ Hysteria2 服务未运行${RESET}"
        fi
    else
        if pgrep -f hysteria &> /dev/null; then
            echo -e "${GREEN}✓ Hysteria2 进程运行正常${RESET}"
        else
            echo -e "${RED}✗ Hysteria2 进程未运行${RESET}"
        fi
    fi
    echo -e "${CYAN}===================${RESET}"
}

# 输出客户端配置
show_client_config() {
    echo
    echo -e "${GREEN}===== Hysteria2 安装完成 =====${RESET}"
    echo
    echo -e "${CYAN}=========== 配置参数 =============${RESET}"
    [[ -n "$SERVER_IPV4" ]] && echo -e "IPv4 地址: ${YELLOW}${SERVER_IPV4}${RESET}"
    [[ -n "$SERVER_IPV6" ]] && echo -e "IPv6 地址: ${YELLOW}${SERVER_IPV6}${RESET}"
    echo -e "端口: ${YELLOW}${SERVER_PORT}${RESET}"
    # ... 其他参数 ...
    echo
    
    if [[ -n "$SERVER_IPV4" ]]; then
        echo -e "${CYAN}IPv4 连接链接:${RESET}"
        echo -e "${GREEN}hysteria2://${HYSTERIA_PASSWORD}@${SERVER_IPV4}:${SERVER_PORT}/?insecure=1&sni=bing.com#1024-Hy2-v4${RESET}"
        echo
    fi

    if [[ -n "$SERVER_IPV6" ]]; then
        echo -e "${CYAN}IPv6 连接链接:${RESET}"
        # IPv6 地址在 URL 中必须放在 [] 内部
        echo -e "${GREEN}hysteria2://${HYSTERIA_PASSWORD}@[${SERVER_IPV6}]:${SERVER_PORT}/?insecure=1&sni=bing.com#1024-Hy2-v6${RESET}"
        echo
    fi
}

# 主函数
main() {
    echo "Hysteria2 一键安装脚本"
    echo "支持的系统: Ubuntu/Debian/CentOS/RHEL/AlmaLinux/Rocky Linux/openSUSE/Arch Linux"
    echo
    
    install_hysteria2
    show_client_config
    check_service_status
}

# 执行主函数
main
