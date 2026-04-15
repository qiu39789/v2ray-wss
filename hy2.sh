#!/bin/bash
# Hysteria2 Dual-Stack Version (Improved IP Detection)

# 1. 增强型双栈 IP 获取函数
get_server_ips() {
    echo "正在获取服务器公网 IP..."
    # 尝试多个来源获取 IPv4
    SERVER_IPV4=$(curl -s4m 5 https://api.ipify.org || curl -s4m 5 https://ifconfig.me || curl -s4m 5 https://icanhazip.com)
    
    # 尝试多个来源获取 IPv6
    SERVER_IPV6=$(curl -s6m 5 https://api64.ipify.org || curl -s6m 5 https://ifconfig.co || curl -s6m 5 https://icanhazip.com)

    # 如果 curl 还是没获取到，尝试从本地网卡抓取
    if [[ -z "$SERVER_IPV4" ]]; then
        SERVER_IPV4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
    fi
    if [[ -z "$SERVER_IPV6" ]]; then
        SERVER_IPV6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9:]+' | grep -v '::1' | grep -v '^fe80' | head -n 1)
    fi
}

# 2. 安装 Hy2
install_hy2() {
    echo "正在下载安装 Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/)
    
    # 随机端口
    SERVER_PORT=$(shuf -i 2000-65000 -n 1)
    # 随机密码
    HY_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    
    mkdir -p /etc/hysteria
    # 生成自签名证书
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=bing.com" -days 36500

    # 写入配置
    cat > /etc/hysteria/config.yaml <<EOF
listen: :$SERVER_PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $HY_PASSWORD
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF
    
    # 启动服务
    systemctl enable hysteria-server
    systemctl restart hysteria-server
}

# 3. 输出结果
show_results() {
    clear
    echo "=========== Hy2 双栈配置 ==========="
    if [[ -n "$SERVER_IPV4" ]]; then
        echo "IPv4 地址: $SERVER_IPV4"
    else
        echo "IPv4 地址: 未检测到 (请手动替换链接中的IP)"
    fi
    
    if [[ -n "$SERVER_IPV6" ]]; then
        echo "IPv6 地址: $SERVER_IPV6"
    else
        echo "IPv6 地址: 未检测到"
    fi
    
    echo "端口: $SERVER_PORT (UDP)"
    echo "密码: $HY_PASSWORD"
    echo "===================================="
    
    # 即使 IP 没获取到，也显示出模板链接
    local display_v4=${SERVER_IPV4:-"你的IPv4"}
    local display_v6=${SERVER_IPV6:-"你的IPv6"}

    echo "IPv4 链接:"
    echo "hysteria2://$HY_PASSWORD@$display_v4:$SERVER_PORT/?insecure=1&sni=bing.com#Hy2_v4"
    echo ""
    
    if [[ -n "$SERVER_IPV6" || "$display_v6" != "你的IPv6" ]]; then
        echo "IPv6 链接:"
        echo "hysteria2://$HY_PASSWORD@[$display_v6]:$SERVER_PORT/?insecure=1&sni=bing.com#Hy2_v6"
    fi
    echo "===================================="
    echo "注意：请确保防火墙已开启 UDP $SERVER_PORT 端口"
}

# 执行
get_server_ips
install_hy2
show_results