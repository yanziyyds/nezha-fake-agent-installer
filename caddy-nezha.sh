#!/bin/bash
#=====================================================
# CentOS 7 一键安装 Caddy 并反代哪吒面板 (HTTPS)
#=====================================================

if [ "$(id -u)" != "0" ]; then
  echo "❌ 请用 root 用户运行"
  exit 1
fi

echo "============================"
echo "  CentOS7 Caddy + 哪吒面板"
echo "============================"

# 输入域名
read -rp "请输入你的域名 (例如 tz.yanzi.love): " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "❌ 域名不能为空"
  exit 1
fi

# 输入哪吒面板端口
read -rp "请输入哪吒面板端口 (默认 8008): " NEZHA_PORT
NEZHA_PORT=${NEZHA_PORT:-8008}

echo ">>> 域名: $DOMAIN"
echo ">>> 哪吒面板端口: $NEZHA_PORT"

# 下载 Caddy 二进制
echo ">>> 下载 Caddy..."
curl -o /usr/bin/caddy -L "https://caddyserver.com/api/download?os=linux&arch=amd64"
chmod +x /usr/bin/caddy

# 创建配置目录
mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy

# 写入配置文件
cat >/etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    encode gzip
    reverse_proxy 127.0.0.1:${NEZHA_PORT}
}
EOF

# 写入 systemd 服务
cat >/etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target

[Service]
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
Restart=on-abnormal

User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# 启动并设置开机自启
systemctl daemon-reexec
systemctl enable caddy
systemctl restart caddy

echo "========================================"
echo "✅ 配置完成！"
echo "现在可以用: https://${DOMAIN} 访问哪吒面板"
echo "证书会由 Caddy 自动申请和续签"
echo "========================================"
