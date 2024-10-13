#!/bin/bash

# 更新系统并安装所需软件
apt update -y
apt install -y curl certbot

# 安装 Xray
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 获取域名输入
read -p "请输入你的域名（默认：www.bing.com）: " DOMAIN
DOMAIN=${DOMAIN:-www.bing.com}  # 如果未输入域名，则默认使用 www.bing.com

# 获取端口输入，若不输入则随机生成一个端口
read -p "请输入你想要使用的端口（按Enter键随机生成）: " PORT
if [ -z "$PORT" ]; then
    PORT=$((RANDOM % 65535 + 1))
    echo "未输入端口，已随机生成端口: $PORT"
fi

# 如果用户输入的是自定义域名，则生成TLS证书
if [[ "$DOMAIN" != "www.bing.com" ]]; then
    # 获取 Let’s Encrypt 证书
    certbot certonly --standalone -d $DOMAIN
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
else
    # 如果是默认的bing伪装域名，TLS证书用自签名（非强制）
    CERT_PATH="/usr/local/etc/xray/selfsigned.crt"
    KEY_PATH="/usr/local/etc/xray/selfsigned.key"

    # 生成自签名证书（仅用于伪装域名的情况）
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj "/CN=bing.com" -keyout $KEY_PATH -out $CERT_PATH
fi

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID 为: $UUID"

# 获取 VPS 的 IP 地址
SERVER_IP=$(curl -s ifconfig.me)

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
            "flow": "",
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
          "path": "/ws",  # 自定义 WebSocket 路径
          "headers": {
            "Host": "$DOMAIN"  # 使用伪装域名
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
ufw allow $PORT/tcp
ufw enable

# 启动 Xray 服务
systemctl start xray
systemctl enable xray

# 输出配置信息
echo "VLESS 服务器配置完成！"
echo "域名: $DOMAIN"
echo "UUID: $UUID"
echo "端口: $PORT"
echo "WebSocket 路径: /ws"
echo "VLESS 配置文件路径: /usr/local/etc/xray/config.json"

# 打印 VLESS 链接，带有别名 vps-vless
VLESS_URL="vless://$UUID@$SERVER_IP:$PORT?encryption=none&security=tls&sni=$DOMAIN&path=/ws&type=ws#vps-vless"
echo "VLESS 链接如下："
echo $VLESS_URL
