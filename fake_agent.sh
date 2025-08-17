#!/bin/bash
#================================================================================
# Fake Nezha Agent 一键安装/卸载脚本 (Yan-增强版)
#
# 作者: Gemini + ChatGPT
# 版本: v1.1.0
#================================================================================

# --- 全局变量和颜色定义 ---
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

SESSION_NAME="nezha-fake"
INSTALL_PATH="/opt/nezha-fake"
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

# 检查并安装依赖
check_and_install_deps() {
    info "正在检查并安装所需依赖 (curl, unzip, screen, cron/systemd)..."
    local deps_to_install=()

    # 检查 cron/systemd
    if ! command -v systemctl >/dev/null 2>&1 && ! command -v crontab >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            deps_to_install+=("cron")
        elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
            deps_to_install+=("cronie")
        elif command -v apk >/dev/null 2>&1; then
            deps_to_install+=("dcron")
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
        apt-get update -y
        apt-get install -y "${deps_to_install[@]}" || { err "依赖安装失败！"; exit 1; }
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${deps_to_install[@]}" || { err "依赖安装失败！"; exit 1; }
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${deps_to_install[@]}" || { err "依赖安装失败！"; exit 1; }
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache "${deps_to_install[@]}" || { err "依赖安装失败！"; exit 1; }
    else
        err "未找到可用的包管理器，请手动安装: ${deps_to_install[*]}"
        exit 1
    fi
    success "依赖安装成功！"
}

detect_arch() {
    case "$(uname -s)" in
        Linux) os="linux";;
        *) err "不支持的操作系统: $(uname -s)"; exit 1;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64";;
        aarch64|arm64) arch="arm64";;
        i386|i686) arch="386";;
        *arm*) arch="arm";;
        *) err "不支持的架构: $(uname -m)"; exit 1;;
    esac
    AGENT_URL=$(echo "$AGENT_URL_TEMPLATE" | sed "s/{os}/$os/" | sed "s/{arch}/$arch/")
    AGENT_ZIP_NAME="nezha-agent-fake_${os}_${arch}.zip"
}

get_server_config() {
    while true; do
        echo "请选择如何提供面板连接信息："
        echo "1) 粘贴从面板获取的一键安装命令 (推荐)"
        echo "2) 手动输入服务器地址、端口和密钥"
        read -rp "请输入选项 [1-2]: " choice
        if [[ "$choice" == "1" ]]; then
            read -rp "请粘贴命令: " full_cmd
            NZ_SERVER=$(echo "$full_cmd" | grep -oP 'NZ_SERVER=\K[^ ]+')
            NZ_CLIENT_SECRET=$(echo "$full_cmd" | grep -oP 'NZ_CLIENT_SECRET=\K[^ ]+')
            NZ_TLS_RAW=$(echo "$full_cmd" | grep -oP 'NZ_TLS=\K[^ ]+')
            if [[ "$NZ_TLS_RAW" == "true" ]]; then NZ_TLS="true"; else NZ_TLS="false"; fi
        elif [[ "$choice" == "2" ]]; then
            read -rp "请输入面板服务器地址: " NZ_SERVER_HOST
            read -rp "请输入面板服务器端口: " NZ_SERVER_PORT
            read -rp "请输入面板密钥: " NZ_CLIENT_SECRET
            read -rp "是否启用 TLS (SSL) [y/n] (默认: n): " NZ_TLS_CHOICE
            NZ_SERVER="${NZ_SERVER_HOST}:${NZ_SERVER_PORT}"
            [[ "$NZ_TLS_CHOICE" == "y" || "$NZ_TLS_CHOICE" == "Y" ]] && NZ_TLS="true" || NZ_TLS="false"
        else
            err "无效选项，请重试。"
            continue
        fi
        if [[ -n "$NZ_SERVER" && -n "$NZ_CLIENT_SECRET" ]]; then
            success "面板信息获取成功！"
            break
        else
            err "信息解析失败，请重试。"
        fi
    done
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
    read -rp "请输入真实网络流量的倍数 [默认: 1]: " FAKE_NET_MULTI
    read -rp "请输入伪造的IP地址 [默认: 1.1.1.1]: " FAKE_IP
}

# 彻底清理旧环境
cleanup_old_install() {
    info "正在清理旧环境..."
    if screen -ls | grep -q "$SESSION_NAME"; then
        screen -S "$SESSION_NAME" -X quit
    fi
    rm -rf "$INSTALL_PATH"
    rm -f /etc/systemd/system/nezha-fake-agent.service
    systemctl daemon-reload >/dev/null 2>&1
    (crontab -l 2>/dev/null | grep -v "${INSTALL_PATH}" | crontab -)
    success "清理完成！"
}

install_agent() {
    check_root
    check_and_install_deps
    cleanup_old_install
    detect_arch
    get_server_config
    get_fake_config

    info "下载 Agent: ${AGENT_URL}"
    curl -L -o "/tmp/${AGENT_ZIP_NAME}" "${AGENT_URL}" || { err "下载失败！"; exit 1; }

    mkdir -p "$INSTALL_PATH"
    unzip -o "/tmp/${AGENT_ZIP_NAME}" -d "$INSTALL_PATH" || { err "解压失败！"; rm -rf "$INSTALL_PATH"; exit 1; }
    rm "/tmp/${AGENT_ZIP_NAME}"

    agent_exec_name=$(ls "$INSTALL_PATH" | head -n1)
    chmod +x "${INSTALL_PATH}/${agent_exec_name}"

    # 写入配置文件
    cat > "${INSTALL_PATH}/config.yaml" <<EOF
disable_auto_update: true
fake: true
version: 6.6.6
arch: ${FAKE_ARCH:-x86_64}
cpu: "${FAKE_CPU:-Intel Xeon Platinum 8369B}"
platform: "${FAKE_PLATFORM:-CentOS 7.9}"
disktotal: ${FAKE_DISK_TOTAL:-219902325555200}
memtotal: ${FAKE_MEM_TOTAL:-549755813888}
diskmultiple: ${FAKE_DISK_MULTI:-10}
memmultiple: ${FAKE_MEM_MULTI:-20}
networkmultiple: ${FAKE_NET_MULTI:-1}
ip: ${FAKE_IP:-1.1.1.1}
EOF

    start_cmd="env NZ_SERVER=\"${NZ_SERVER}\" NZ_CLIENT_SECRET=\"${NZ_CLIENT_SECRET}\" NZ_TLS=\"${NZ_TLS}\" ${INSTALL_PATH}/${agent_exec_name} -c ${INSTALL_PATH}/config.yaml"

    echo "请选择运行方式："
    echo "1) 使用 systemd (推荐, 更稳定)"
    echo "2) 使用 screen+cron (兼容性好)"
    read -rp "请输入选项 [1-2]: " run_choice

    if [[ "$run_choice" == "1" ]]; then
        cat > /etc/systemd/system/nezha-fake-agent.service <<SERVICE
[Unit]
Description=Fake Nezha Agent
After=network.target

[Service]
Type=simple
ExecStart=$start_cmd
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE
        systemctl daemon-reload
        systemctl enable --now nezha-fake-agent
        success "安装完成，已通过 systemd 启动并设置开机自启！"
    else
        screen -dmS "$SESSION_NAME" bash -c "${start_cmd}"
        (crontab -l 2>/dev/null | grep -v "${INSTALL_PATH}"; echo "@reboot screen -dmS ${SESSION_NAME} bash -c '${start_cmd}'") | crontab -
        success "安装完成，已通过 screen 启动并配置开机自启！"
    fi
}

uninstall_agent() {
    check_root
    cleanup_old_install
    success "Fake Nezha Agent 已卸载。"
}

main() {
    clear
    echo "========================================="
    echo "  Fake Nezha Agent 一键管理脚本 (v1.1.0)"
    echo "         (Yan-增强版)"
    echo "========================================="
    echo ""
    read -rp "请选择操作: [1]安装 [2]卸载 [0]退出: " option
    case "$option" in
        1) install_agent ;;
        2) uninstall_agent ;;
        0) exit 0 ;;
        *) err "无效的选项" ;;
    esac
}

main
