#!/bin/bash

# 确保以root运行
if [[ $EUID -ne 0 ]]; then
    echo "错误: 此脚本必须以root身份运行!"
    exit 1
fi

# 获取双栈 IP
SERVER_IPV4=$(curl -s -4 --connect-timeout 5 https://api.ipify.org || echo "")
SERVER_IPV6=$(curl -s -6 --connect-timeout 5 https://api64.ipify.org || echo "")

# 安装 Xray (如果没装)
if [ ! -f "/usr/local/bin/xray" ]; then
    echo "正在安装 Xray..."
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
fi

# 密钥提取逻辑（改进版）
echo "正在生成 Reality 密钥..."
KEYS=$(/usr/local/bin/xray x25519)
RE_PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | cut -d ' ' -f 3)
RE_PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | cut -d ' ' -f 3)

# 检查密钥是否成功获取
if [[ -z "$RE_PRIVATE_KEY" ]]; then
    echo "错误: 密钥提取失败，尝试第二种格式提取..."
    RE_PRIVATE_KEY=$(echo "$KEYS" | awk -F': ' '/Private/ {print $2}' | tr -d ' ')
    RE_PUBLIC_KEY=$(echo "$KEYS" | awk -F': ' '/Public/ {print $2}' | tr -d ' ')
fi

if [[ -z "$RE_PRIVATE_KEY" ]]; then
    echo "严重错误: 无法生成 Reality 密钥，请检查 /usr/local/bin/xray 是否可用。"
    exit 1
fi

# 变量设置
PORT_NUMBER=443
UUID=$(cat /proc/sys/kernel/random/uuid)
SERVER_SNI="www.amazon.com"

# 写入配置文件
cat > /usr/local/etc/xray/config.json <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "::",
            "port": $PORT_NUMBER,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$SERVER_SNI:443",
                    "xver": 0,
                    "serverNames": [
                        "$SERVER_SNI"
                    ],
                    "privateKey": "$RE_PRIVATE_KEY",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "88"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        }
    ]
}
EOF

# 重启服务
systemctl restart xray
sleep 2

# 检查服务状态
if systemctl is-active --quiet xray; then
    clear
    echo "=========== Reality 安装成功 ==========="
    [[ -n "$SERVER_IPV4" ]] && echo "IPv4 地址: $SERVER_IPV4"
    [[ -n "$SERVER_IPV6" ]] && echo "IPv6 地址: $SERVER_IPV6"
    echo "端口: $PORT_NUMBER"
    echo "UUID: $UUID"
    echo "Public Key: $RE_PUBLIC_KEY"
    echo "========================================"
    
    if [[ -n "$SERVER_IPV4" ]]; then
        echo "IPv4 链接:"
        echo "vless://$UUID@$SERVER_IPV4:$PORT_NUMBER?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$RE_PUBLIC_KEY&sid=88&type=tcp&headerType=none#Reality_v4"
        echo ""
    fi
    if [[ -n "$SERVER_IPV6" ]]; then
        echo "IPv6 链接:"
        echo "vless://$UUID@[$SERVER_IPV6]:$PORT_NUMBER?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$RE_PUBLIC_KEY&sid=88&type=tcp&headerType=none#Reality_v6"
    fi
else
    echo "错误: Xray 服务启动失败，请再次运行 journalctl -u xray --no-pager | tail -n 20 查看原因。"
fi