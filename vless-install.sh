#!/bin/bash

# 确保脚本以 root 用户权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户权限运行此脚本。"
  exit 1
fi

# 更新系统并安装所需软件
apt update -y
apt install -y curl certbot openssl

# 安装 Xray
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 获取域名输入，默认使用 www.bing.com 作为伪装域名
read -p "请输入你的域名（默认：www.bing.com）: " DOMAIN
DOMAIN=${DOMAIN:-www.bing.com}

# 获取端口输入，若不输入则随机生成一个端口
read -p "请输入你想要使用的端口（按Enter键随机生成）: " PORT
if [ -z "$PORT" ]; then
    PORT=$(shuf -i 10000-65535 -n 1)
    echo "未输入端口，已随机生成端口: $PORT"
else
    # 检查端口是否为有效数字
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
       echo "错误: 端口号无效。"
       exit 1
    fi
fi

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID 为: $UUID"

# 获取 VPS 的 IPv4 地址
SERVER_IP=$(curl -4 -s https://ifconfig.me)
if [[ -z "$SERVER_IP" ]]; then
    echo "无法获取服务器的IPv4地址，请检查网络连接。"
    exit 1
fi
echo "服务器的IPv4地址为: $SERVER_IP"

# 创建 Xray 配置文件
cat > /usr/local/etc/xray/config.json << EOF
{
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/selfsigned.crt",
              "keyFile": "/usr/local/etc/xray/selfsigned.key"
            }
          ]
        },
        "wsSettings": {
          "path": "/ws",
          "headers": {
            "Host": "$DOMAIN"
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 生成自签名证书（用于伪装流量）
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/CN=$DOMAIN" \
    -keyout "/usr/local/etc/xray/selfsigned.key" \
    -out "/usr/local/etc/xray/selfsigned.crt"

# 启动 Xray 服务
systemctl restart xray
systemctl enable xray

# 输出配置信息
echo "=============================="
echo "VLESS 服务器配置完成！"
echo "域名: $DOMAIN"
echo "UUID: $UUID"
echo "端口: $PORT"
echo "WebSocket 路径: /ws"
echo "服务器IPv4地址: $SERVER_IP"
echo "=============================="

# 打印 VLESS 链接，带有别名 vps-vless
VLESS_URL="vless://$UUID@$SERVER_IP:$PORT?encryption=none&security=tls&sni=$DOMAIN&path=/ws&type=ws#vps-vless"
echo "VLESS 链接如下："
echo "$VLESS_URL"
