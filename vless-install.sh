#!/bin/bash

# 确保以 root 用户权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户权限运行此脚本。"
  exit 1
fi

# 更新系统并安装所需软件
apt update -y
apt install -y curl certbot socat

# 安装 Xray
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 获取域名输入，确保域名已经解析到 VPS IP
read -p "请输入你的域名（确保域名已经解析到 VPS IP）: " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "域名不能为空，请重新运行脚本并输入域名。"
  exit 1
fi

# 获取端口输入，若不输入则默认使用 443 端口
read -p "请输入你想要使用的端口（默认 443）: " PORT
PORT=${PORT:-443}

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID 为: $UUID"

# 获取 VPS 的 IPv4 地址
SERVER_IP=$(curl -4 -s https://ifconfig.me)
if [[ -z "$SERVER_IP" ]]; then
  echo "无法获取服务器的 IPv4 地址，请检查网络连接。"
  exit 1
fi
echo "服务器的 IP 地址为: $SERVER_IP"

# 申请 Let’s Encrypt 证书
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m your-email@example.com

# 证书路径
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

# 确保证书生成成功
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  echo "证书生成失败，请检查域名是否正确解析到 VPS。"
  exit 1
fi

# 生成 Xray 配置文件
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

# 创建 systemd 服务文件
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
LimitNPROC=1000
LimitNOFILE=1000000
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd，启动并启用 Xray 服务
systemctl daemon-reload
systemctl start xray
systemctl enable xray

# 检查 Xray 服务状态
if systemctl is-active --quiet xray; then
  echo "Xray 服务启动成功。"
else
  echo "Xray 服务启动失败，请检查日志。"
  exit 1
fi

# 输出配置信息
echo "=============================="
echo "VLESS 服务器配置完成！"
echo "域名: $DOMAIN"
echo "UUID: $UUID"
echo "端口: $PORT"
echo "WebSocket 路径: /ws"
echo "服务器 IP 地址: $SERVER_IP"
echo "VLESS 配置文件路径: /usr/local/etc/xray/config.json"
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
