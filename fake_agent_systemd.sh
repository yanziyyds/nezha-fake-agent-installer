#!/bin/bash

#================================================================================
# Fake Nezha Agent 一键管理脚本 (Systemd 最终尝试版)
#
# 作者: Gemini
# 版本: v1.0.0-systemd
#================================================================================

# --- 全局变量和颜色定义 ---
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 安装路径
INSTALL_PATH="/opt/nezha-fake"
# systemd 服务文件路径
SERVICE_PATH="/etc/systemd/system/nezha-fake-agent.service"
# Agent 程序下载URL模板
AGENT_URL_TEMPLATE="https://github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/nezha-agent-fake_{os}_{arch}.zip"

# --- 工具函数 ---

err() { echo -e "${red}[错误] $1${plain}"; }
success() { echo -e "${green}[成功] $1${plain}"; }
info() { echo -e "${yellow}[信息] $1${plain}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "本脚本需要以 root 权限运行！"
        exit 1
    fi
}

check_and_install_deps() {
    info "正在检查并安装所需依赖 (curl, unzip)..."
    local deps_to_install=()
    for dep in curl unzip; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            deps_to_install+=("$dep")
        fi
    done

    if [ ${#deps_to_install[@]} -eq 0 ]; then
        success "所有依赖均已安装。"
        return
    fi

    info "检测到未安装的依赖: ${deps_to_install[*]}"
    
    if command -v apt-get >/dev/null 2>&1; then
        info "正在使用 apt-get 安装..."
        apt-get update -y
        if ! apt-get install -y "${deps_to_install[@]}"; then
             err "依赖安装失败，请检查您的软件源设置！"; exit 1
        fi
    elif command -v yum >/dev/null 2>&1; then
        info "正在使用 yum 安装..."
        if ! yum install -y "${deps_to_install[@]}"; then
             err "依赖安装失败！"; exit 1
        fi
    elif command -v dnf >/dev/null 2>&1; then
        info "正在使用 dnf 安装..."
        if ! dnf install -y "${deps_to_install[@]}"; then
             err "依赖安装失败！"; exit 1
        fi
    else
        err "未找到可用的包管理器 (apt/yum/dnf)。请手动安装: ${deps_to_install[*]}"; exit 1
    fi
    success "依赖安装成功！"
}

detect_arch() {
    case "$(uname -s)" in Linux) os="linux";; *) err "不支持的操作系统: $(uname -s)"; exit 1;; esac
    case "$(uname -m)" in x86_64|amd64) arch="amd64";; aarch64|arm64) arch="arm64";; i386|i686) arch="386";; *arm*) arch="arm";; *) err "不支持的架构: $(uname -m)"; exit 1;; esac
    AGENT_URL=$(echo "$AGENT_URL_TEMPLATE" | sed "s/{os}/$os/" | sed "s/{arch}/$arch/")
    AGENT_ZIP_NAME="nezha-agent-fake_${os}_${arch}.zip"
}

get_server_config() {
    info "请选择如何提供面板连接信息："; echo "1) 粘贴从面板获取的完整一键安装命令 (推荐)"; echo "2) 手动输入服务器地址、端口和密钥"
    read -rp "请输入选项 [1-2]: " choice
    if [[ "$choice" == "1" ]]; then
        read -rp "请粘贴命令: " full_cmd
        NZ_SERVER=$(echo "$full_cmd" | grep -oP 'NZ_SERVER=\K[^ ]+')
        NZ_CLIENT_SECRET=$(echo "$full_cmd" | grep -oP 'NZ_CLIENT_SECRET=\K[^ ]+')
        NZ_TLS_RAW=$(echo "$full_cmd" | grep -oP 'NZ_TLS=\K[^ ]+')
        if [[ "$NZ_TLS_RAW" == "true" ]]; then NZ_TLS="true"; else NZ_TLS="false"; fi
        if [[ -z "$NZ_SERVER" || -z "$NZ_CLIENT_SECRET" ]]; then err "无法从您粘贴的命令中解析出必要信息。"; exit 1; fi
    elif [[ "$choice" == "2" ]]; then
        read -rp "请输入面板服务器地址: " NZ_SERVER_HOST; read -rp "请输入面板服务器端口: " NZ_SERVER_PORT; read -rp "请输入面板密钥: " NZ_CLIENT_SECRET; read -rp "是否启用 TLS (SSL) [y/n] (默认: n): " NZ_TLS_CHOICE
        NZ_SERVER="${NZ_SERVER_HOST}:${NZ_SERVER_PORT}"; [[ "$NZ_TLS_CHOICE" == "y" || "$NZ_TLS_CHOICE" == "Y" ]] && NZ_TLS="true" || NZ_TLS="false"
    else err "无效的选项。"; exit 1; fi
    success "面板信息获取成功！"
}

get_fake_config() {
    info "现在开始配置伪造数据，直接回车将使用默认值。"
    read -rp "请输入伪造的CPU型号 [默认: HUAWEI Kirin 9000s 256 Core]: " FAKE_CPU
    read -rp "请输入伪造的架构 [默认: taishan64]: " FAKE_ARCH
    read -rp "请输入伪造的操作系统 [默认: HarmonyOS NEXT]: " FAKE_PLATFORM
    read -rp "请输入伪造的磁盘总大小(Byte) [默认: 219902325555200]: " FAKE_DISK_TOTAL
    read -rp "请输入伪造的内存总大小(Byte) [默认: 549755813888]: " FAKE_MEM_TOTAL
    read -rp "请输入真实磁盘使用量的倍数 [默认: 10]: " FAKE_DISK_MULTI
    read -rp "请输入真实内存使用量的倍数 [默认: 20]: " FAKE_MEM_MULTI
    read -rp "请输入真实网络流量的倍数 [默认: 1000]: " FAKE_NET_MULTI
    read -rp "请输入伪造的IP地址 [默认: 8.8.8.8]: " FAKE_IP
}

cleanup_old_install() {
    info "正在进行彻底清理，确保一个干净的环境..."
    systemctl stop nezha-fake-agent.service >/dev/null 2>&1
    systemctl disable nezha-fake-agent.service >/dev/null 2>&1
    rm -f /etc/systemd/system/nezha-fake-agent.service
    systemctl daemon-reload
    rm -rf "$INSTALL_PATH"
    success "清理完成！"
}

# 安装 Agent
install_agent() {
    info "开始安装 Fake Nezha Agent (Systemd 模式)..."
    check_root; check_and_install_deps
    
    cleanup_old_install
    
    detect_arch; get_server_config; get_fake_config
    
    info "正在从 GitHub 下载 Agent: ${AGENT_URL}"
    curl -L -o "/tmp/${AGENT_ZIP_NAME}" "${AGENT_URL}" || { err "下载失败！"; exit 1; }
    
    info "创建并解压到目录: ${INSTALL_PATH}"
    mkdir -p "$INSTALL_PATH"
    unzip -o "/tmp/${AGENT_ZIP_NAME}" -d "$INSTALL_PATH" || { err "解压失败！"; rm -rf "$INSTALL_PATH"; exit 1; }
    
    agent_exec_name=$(unzip -Z1 "/tmp/${AGENT_ZIP_NAME}" | head -n 1 | tr -d '\r')
    if [ -z "$agent_exec_name" ] || [ ! -f "${INSTALL_PATH}/${agent_exec_name}" ]; then
        err "严重错误：无法在压缩包中找到或验证可执行文件！"; rm -rf "$INSTALL_PATH"; rm "/tmp/${AGENT_ZIP_NAME}"; exit 1
    fi
    info "检测到可执行文件: '${agent_exec_name}'"
    
    chmod +x "${INSTALL_PATH}/${agent_exec_name}"
    rm "/tmp/${AGENT_ZIP_NAME}"
    
    info "正在创建完整的 config.yaml (包含所有配置)..."
    cat > "${INSTALL_PATH}/config.yaml" <<EOF
# 由一键安装脚本生成
# --- 面板连接信息 (为字符串值加上引号以保证兼容性) ---
server: "${NZ_SERVER}"
secret: "${NZ_CLIENT_SECRET}"
tls: ${NZ_TLS}

# --- 核心伪造配置 ---
disable_auto_update: true
fake: true

# --- 自定义伪造信息 ---
version: 6.6.6
arch: "${FAKE_ARCH:-taishan64}"
cpu: "${FAKE_CPU:-HUAWEI Kirin 9000s 256 Core}"
platform: "${FAKE_PLATFORM:-HarmonyOS NEXT}"
disktotal: ${FAKE_DISK_TOTAL:-219902325555200}
memtotal: ${MEM_TOTAL:-549755813888}
diskmultiple: ${DISK_MULTI:-10}
memmultiple: ${MEM_MULTI:-20}
networkmultiple: ${NETWORK_MULTI:-1000}
ip: "${FAKE_IP:-8.8.8.8}"
EOF

    info "正在创建 systemd 服务文件 (最稳妥的配置)..."
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Nezha Fake Agent Service
After=network.target

[Service]
Type=simple
User=root
# 为确保程序能找到相对路径的文件，设置工作目录
WorkingDirectory=${INSTALL_PATH}
Restart=on-failure
RestartSec=10s
# 明确使用 -c 参数指定配置文件的绝对路径
ExecStart=${INSTALL_PATH}/${agent_exec_name} -c ${INSTALL_PATH}/config.yaml

[Install]
WantedBy=multi-user.target
EOF

    info "重载 systemd 并启动服务..."
    systemctl daemon-reload
    systemctl enable nezha-fake-agent.service
    systemctl start nezha-fake-agent.service

    sleep 2
    if systemctl is-active --quiet nezha-fake-agent.service; then
        success "Fake Nezha Agent 安装并启动成功！恭喜！"
        info "现在可以去您的哪吒面板查看效果了。"
    else
        err "服务启动失败！正如预测，这很可能是程序本身的缺陷导致。"
        info "请通过 'journalctl -u nezha-fake-agent.service -n 50 --no-pager' 命令查看详细日志后反馈。"
        info "如果依然失败，强烈建议您使用我们已经验证成功的 screen 版本。"
    fi
}

uninstall_agent() {
    info "开始卸载 Fake Nezha Agent..."
    check_root
    cleanup_old_install
}

main() {
    clear
    echo "========================================="
    echo "  Fake Nezha Agent 一键管理脚本 (v1.0.0-systemd)"
    echo "         (Systemd 最终尝试版)"
    echo "========================================="
    echo ""
    read -rp "请选择要执行的操作: [1]安装 [2]卸载 [0]退出: " option
    case "$option" in
        1) install_agent ;;
        2) uninstall_agent ;;
        0) exit 0 ;;
        *) err "无效的选项" ;;
    esac
}

main
