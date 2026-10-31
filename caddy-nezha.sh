#!/bin/bash
#=====================================================
# 一键安装 Caddy 并反代哪吒面板 (HTTPS)
# 支持任意 systemd 发行版，自动检测 amd64 / arm64
#=====================================================
set -euo pipefail

if [[ "$(id -u)" != "0" ]]; then
  echo "❌ 请用 root 用户运行"
  exit 1
fi

command -v systemctl >/dev/null 2>&1 || { echo "❌ 需要 systemd"; exit 1; }

echo "============================"
echo "  Caddy + 哪吒面板反代"
echo "============================"

# 输入域名并校验格式
read -rp "请输入你的域名 (例如 tz.yanzi.love): " DOMAIN
if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$ ]]; then
  echo "❌ 域名格式不正确"
  exit 1
fi

# 输入哪吒面板端口并校验范围
read -rp "请输入哪吒面板端口 (默认 8008): " NEZHA_PORT
NEZHA_PORT=${NEZHA_PORT:-8008}
if [[ ! "$NEZHA_PORT" =~ ^[0-9]+$ ]] || [[ "$NEZHA_PORT" -lt 1 || "$NEZHA_PORT" -gt 65535 ]]; then
  echo "❌ 端口必须是 1-65535 的数字"
  exit 1
fi

echo ">>> 域名: $DOMAIN"
echo ">>> 哪吒面板端口: $NEZHA_PORT"

# 架构检测（不再硬编码 amd64）
case "$(uname -m)" in
  x86_64|amd64) CADDY_ARCH="amd64" ;;
  aarch64|arm64) CADDY_ARCH="arm64" ;;
  armv7l) CADDY_ARCH="armv7" ;;
  *) echo "❌ 不支持的架构: $(uname -m)"; exit 1 ;;
esac

# 下载 Caddy 二进制（失败即退出，不继续）
echo ">>> 下载 Caddy ($CADDY_ARCH)..."
if ! curl -fsSL -o /usr/bin/caddy -L "https://caddyserver.com/api/download?os=linux&arch=${CADDY_ARCH}"; then
  echo "❌ Caddy 下载失败"
  exit 1
fi
chmod +x /usr/bin/caddy

# 创建配置目录
mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy

# 备份已有配置
if [[ -f /etc/caddy/Caddyfile ]]; then
  cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"
fi

# 写入配置文件
cat >/etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    encode gzip
    reverse_proxy 127.0.0.1:${NEZHA_PORT}
}
EOF

# 校验配置，失败则退出（备份已保留）
if ! /usr/bin/caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; then
  echo "❌ Caddyfile 校验失败，旧配置备份已保留"
  exit 1
fi

# 写入 systemd 服务（已有则备份）
if [[ -f /etc/systemd/system/caddy.service ]]; then
  cp /etc/systemd/system/caddy.service "/etc/systemd/system/caddy.service.bak.$(date +%s)"
fi
cat >/etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target

[Service]
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
Restart=on-failure
RestartSec=3

User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# 启动并设置开机自启
systemctl daemon-reload
systemctl enable caddy
if ! systemctl restart caddy; then
  echo "❌ Caddy 启动失败，请用 journalctl -u caddy 查看日志"
  exit 1
fi

echo "========================================"
echo "✅ 配置完成！"
echo "现在可以用: https://${DOMAIN} 访问哪吒面板"
echo "证书会由 Caddy 自动申请和续签"
echo "注意：服务器防火墙需放行 80/443 端口（ACME 验证需要 80）"
echo "========================================"
