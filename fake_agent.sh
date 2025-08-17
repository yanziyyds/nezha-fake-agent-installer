#!/bin/bash

#================================================================================
# Fake Nezha Agent 一键安装/卸载脚本 (Yan-开机自启稳定版)
#
# 作者: Gemini
# 版本: v1.0.0
#================================================================================

# --- 全局变量和颜色定义 ---
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 会话名称
SESSION_NAME="nezha-fake"
# 安装路径
INSTALL_PATH="/opt/nezha-fake"
# Agent 程序下载URL模板
AGENT_URL_TEMPLATE="https://gh-proxy.com/github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/nezha-agent-fake_{os}_{arch}.zip"

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

# 检查并安装依赖 (包含 screen)
check_and_install_deps() {
    info "正在检查并安装所需依赖 (curl, unzip, screen, cron)..."
    local deps_to_install=()
    # 检查 cron/crontab 是否存在
    if ! command -v crontab >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            deps_to_install+=("cron")
        elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
            deps_to_install+=("cronie")
        fi
    fi

    for dep in curl unzip screen; do
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
    read -rp "请输入伪造的CPU型号 [默认: Intel Xeon Platinum 8369B]: " FAKE_CPU
    read -rp "请输入伪造的架构 [默认: x86_64]: " FAKE_ARCH
    read -rp "请输入伪造的操作系统 [默认: CentOS 7.9]: " FAKE_PLATFORM
    read -rp "请输入伪造的磁盘总大小(Byte) [默认: 219902325555200]: " FAKE_DISK_TOTAL
    read -rp "请输入伪造的内存总大小(Byte) [默认: 549755813888]: " FAKE_MEM_TOTAL
    read -rp "请输入真实磁盘使用量的倍数 [默认: 10]: " FAKE_DISK_MULTI
    read -rp "请输入真实内存使用量的倍数 [默认: 20]: " FAKE_MEM_MULTI
    read -rp "请输入真实网络流量的倍数 [默认: 1000]: " FAKE_NET_MULTI
    read -rp "请输入伪造的IP地址 [默认: 1.1.1.1]: " FAKE_IP
}

# 彻底清理旧环境
cleanup_old_install() {
    info "正在进行彻底清理，确保一个干净的环境..."
    # 强制杀死可能存在的 screen 会话
    if screen -ls | grep -q "$SESSION_NAME"; then
        info "发现旧的 screen 会话，正在终止..."
        screen -S "$SESSION_NAME" -X quit
    fi
    # 删除旧的安装目录
    rm -rf "$INSTALL_PATH"
    # 清理旧的 systemd 服务
    rm -f /etc/systemd/system/nezha-fake-agent.service >/dev/null 2>&1
    systemctl daemon-reload
    # 清理 crontab 中的旧条目
    (crontab -l 2>/dev/null | grep -v "${INSTALL_PATH}" | crontab -)
    success "清理完成！"
}

# 安装 Agent
install_agent() {
    info "开始安装 Fake Nezha Agent..."
    check_root
    check_and_install_deps
    
    # 先执行彻底清理
    cleanup_old_install

    detect_arch
    get_server_config
    get_fake_config
    
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
    
    info "正在根据官方示例创建 config.yaml..."
    cat > "${INSTALL_PATH}/config.yaml" <<EOF
# 由一键安装脚本生成
disable_auto_update: true
fake: true
version: 6.6.6
arch: x86_64
cpu: "Intel Xeon Platinum 8369B"  # 阿里云8代ECS常用CPU
platform: "CentOS 7.9"            # 企业常用系统
disktotal: 107374182400           # 100GB（普通云盘）
memtotal: 34359738368             # 32GB（典型900元档内存）
diskmultiple: 10                   # 不放大磁盘使用量
memmultiple: 10                    # 不放大内存使用量
networkmultiple: 10000               # 流量放大10倍（模拟高带宽）
ip: 43.131.225.61                 # 内网IP（或换成真实公网IP）
EOF

    # 准备启动命令
    start_cmd="env NZ_SERVER=\"${NZ_SERVER}\" NZ_CLIENT_SECRET=\"${NZ_CLIENT_SECRET}\" NZ_TLS=\"${NZ_TLS}\" ${INSTALL_PATH}/${agent_exec_name} -c ${INSTALL_PATH}/config.yaml"

    info "正在启动 screen 会话以在后台运行 Agent..."
    screen -dmS "$SESSION_NAME" bash -c "${start_cmd}"

    sleep 2
    if screen -ls | grep -q "$SESSION_NAME"; then
        info "Agent 已在 screen 会话中成功启动！"
        # 添加开机自启
        info "正在添加开机自启任务..."
        (crontab -l 2>/dev/null | grep -v "${INSTALL_PATH}"; echo "@reboot screen -dmS ${SESSION_NAME} bash -c '${start_cmd}'") | crontab -
        
        success "Fake Nezha Agent 安装并配置开机自启成功！"
        info "现在可以去您的哪吒面板查看效果了。"
        info ""
        info "--- Agent 管理命令 ---"
        info "查看运行日志: screen -r ${SESSION_NAME}"
        info "(查看后按 Ctrl+A, 再按 D 即可退出日志界面)"
        info "停止 Agent:  screen -S ${SESSION_NAME} -X quit"
        info "手动启动:    screen -dmS ${SESSION_NAME} bash -c '${start_cmd}'"
        info "--------------------"
    else
        err "服务启动失败！这非常意外。"
        err "请尝试手动运行启动命令查看报错: "
        err "${start_cmd}"
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
    echo "  Fake Nezha Agent 一键管理脚本 (v1.0.0)"
    echo "         (Yan-开机自启稳定版)"
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
