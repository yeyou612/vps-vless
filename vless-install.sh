#!/bin/bash

# 确保脚本以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root用户运行此脚本。"
  exit 1
fi

# 更新系统并安装所需软件
apt update -y
apt install -y curl certbot ufw openssl

# 安装 Xray
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 获取域名输入，默认使用 www.bing.com
read -p "请输入你的域名（默认：www.bing.com）: " DOMAIN
DOMAIN=${DOMAIN:-www.bing.com}

# 获取端口输入，若不输入则随机生成一个端口（10000-65535，以避免常见端口冲突）
read -p "请输入你想要使用的端口（按Enter键随机生成）: " PORT
if [ -z "$PORT" ]; then
    PORT=$(shuf -i 10000-65535 -n 1)
    echo "未输入端口，已随机生成端口: $PORT"
else
    # 检查端口是否为有效数字
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] ; then
       echo "错误: 端口号无效。"
       exit 1
    fi
fi

# 如果用户输入的是自定义域名，则生成TLS证书
if [[ "$DOMAIN" != "www.bing.com" ]]; then
    # 获取 Let’s Encrypt 证书
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m your-email@example.com
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
else
    # 如果是默认的bing伪装域名，TLS证书用自签名（非强制）
    CERT_PATH="/usr/local/etc/xray/selfsigned.crt"
    KEY_PATH="/usr/local/etc/xray/selfsigned.key"

    # 生成自签名证书（仅用于伪装域名的情况）
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/CN=bing.com" \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH"
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
              "certificateFile": "$CERT_PATH",
              "keyFile": "$KEY_PATH"
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

# 配置防火墙
echo "配置防火墙，允许端口 $PORT 通过..."
ufw allow "$PORT"/tcp
ufw allow ssh
ufw --force enable

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
echo "VLESS 配置文件路径: /usr/local/etc/xray/config.json"
echo "服务器IPv4地址: $SERVER_IP"
echo "=============================="

# 打印 VLESS 链接，带有别名 vps-vless
VLESS_URL="vless://$UUID@$SERVER_IP:$PORT?encryption=none&security=tls&sni=$DOMAIN&path=/ws&type=ws#vps-vless"
echo "VLESS 链接如下："
echo "$VLESS_URL"

# 提供 V2RayN 导入格式
echo "=============================="
echo "你可以将以下链接复制到 V2RayN 或其他支持 VLESS 的客户端："
echo "$VLESS_URL"
echo "=============================="
