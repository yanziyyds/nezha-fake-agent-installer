#!/bin/bash

#================================================================================
# Fake Nezha Agent 一键安装/卸载脚本
#
# 功能:
#   - 自动安装依赖 (curl, unzip)
#   - 自动检测系统架构并从 GitHub 下载最新版 Fake Agent
#   - 支持通过粘贴官方命令自动解析或手动输入面板信息
#   - 交互式配置伪造的服务器参数
#   - 使用 systemd 创建服务，确保稳定后台运行和开机自启
#   - 提供完整的卸载功能，一键清除所有相关文件和服务
#
# 作者: Gemini
# 版本: 1.4 (增加自动依赖安装功能)
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

# 打印错误信息
err() {
    echo -e "${red}[错误] $1${plain}"
}

# 打印成功信息
success() {
    echo -e "${green}[成功] $1${plain}"
}

# 打印提示信息
info() {
    echo -e "${yellow}[信息] $1${plain}"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "本脚本需要以 root 权限运行！"
        exit 1
    fi
}

# 检查并安装依赖 (新功能)
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
    
    # 自动安装
    if command -v apt-get >/dev/null 2>&1; then
        info "正在使用 apt-get 安装..."
        apt-get update
        if ! apt-get install -y "${deps_to_install[@]}"; then
             err "依赖安装失败，请检查您的软件源设置！"
             exit 1
        fi
    elif command -v yum >/dev/null 2>&1; then
        info "正在使用 yum 安装..."
        if ! yum install -y "${deps_to_install[@]}"; then
             err "依赖安装失败！"
             exit 1
        fi
    elif command -v dnf >/dev/null 2>&1; then
        info "正在使用 dnf 安装..."
        if ! dnf install -y "${deps_to_install[@]}"; then
             err "依赖安装失败！"
             exit 1
        fi
    else
        err "未找到可用的包管理器 (apt/yum/dnf)。"
        err "请手动安装以下依赖: ${deps_to_install[*]}"
        exit 1
    fi

    # 再次检查
    for dep in "${deps_to_install[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            err "依赖 '$dep' 安装失败！请手动安装后重试。"
            exit 1
        fi
    done

    success "依赖安装成功！"
}


# 检测系统架构
detect_arch() {
    local sys_os
    local sys_arch

    case "$(uname -s)" in
        Linux)
            sys_os="linux"
            ;;
        *)
            err "不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64 | amd64)
            sys_arch="amd64"
            ;;
        aarch64 | arm64)
            sys_arch="arm64"
            ;;
        i386 | i686)
            sys_arch="386"
            ;;
        armv7* | arm)
            sys_arch="arm"
            ;;
        *)
            err "不支持的系统架构: $(uname -m)"
            exit 1
            ;;
    esac

    # 将结果组合成可用的URL
    AGENT_URL=$(echo "$AGENT_URL_TEMPLATE" | sed "s/{os}/$sys_os/" | sed "s/{arch}/$sys_arch/")
    AGENT_ZIP_NAME="nezha-agent-fake_${sys_os}_${sys_arch}.zip"
}

# 获取面板服务器信息
get_server_config() {
    info "请选择如何提供面板连接信息："
    echo "1) 粘贴从面板获取的完整一键安装命令 (推荐)"
    echo "2) 手动输入服务器地址、端口和密钥"
    read -rp "请输入选项 [1-2]: " choice

    if [[ "$choice" == "1" ]]; then
        read -rp "请粘贴命令: " full_cmd
        # 使用 grep 和 -oP (Perl-compatible) 正则表达式提取
        NZ_SERVER=$(echo "$full_cmd" | grep -oP 'NZ_SERVER=\K[^ ]+')
        NZ_CLIENT_SECRET=$(echo "$full_cmd" | grep -oP 'NZ_CLIENT_SECRET=\K[^ ]+')
        NZ_TLS_RAW=$(echo "$full_cmd" | grep -oP 'NZ_TLS=\K[^ ]+')
        
        # 处理TLS选项
        if [[ "$NZ_TLS_RAW" == "true" ]]; then
            NZ_TLS="true"
        else
            NZ_TLS="false" # 默认或明确设置为false
        fi

        if [[ -z "$NZ_SERVER" || -z "$NZ_CLIENT_SECRET" ]]; then
            err "无法从您粘贴的命令中解析出必要信息，请检查后重试或选择手动输入。"
            exit 1
        fi
    elif [[ "$choice" == "2" ]]; then
        read -rp "请输入面板服务器地址 (例如: data.yourdomain.com): " NZ_SERVER_HOST
        read -rp "请输入面板服务器端口 (例如: 5555): " NZ_SERVER_PORT
        read -rp "请输入面板密钥: " NZ_CLIENT_SECRET
        read -rp "是否启用 TLS (SSL) [y/n] (默认: n): " NZ_TLS_CHOICE
        
        NZ_SERVER="${NZ_SERVER_HOST}:${NZ_SERVER_PORT}"
        [[ "$NZ_TLS_CHOICE" == "y" || "$NZ_TLS_CHOICE" == "Y" ]] && NZ_TLS="true" || NZ_TLS="false"
    else
        err "无效的选项。"
        exit 1
    fi
    success "面板信息获取成功！"
}

# 获取伪造数据配置
get_fake_config() {
    info "现在开始配置伪造数据，直接回车将使用默认值。"
    read -rp "请输入伪造的CPU型号 [默认: HUAWEI Kirin 9000s 256 Core]: " FAKE_CPU
    read -rp "请输入伪造的架构 [默认: taishan64]: " FAKE_ARCH
    read -rp "请输入伪造的操作系统 [默认: HarmonyOS NEXT]: " FAKE_PLATFORM
    read -rp "请输入伪造的磁盘总大小 (单位Byte) [默认: 219902325555200 (200PB)]: " FAKE_DISK_TOTAL
    read -rp "请输入伪造的内存总大小 (单位Byte) [默认: 549755813888 (512GB)]: " FAKE_MEM_TOTAL
    read -rp "请输入真实磁盘使用量的倍数 [默认: 10]: " FAKE_DISK_MULTI
    read -rp "请输入真实内存使用量的倍数 [默认: 20]: " FAKE_MEM_MULTI
    read -rp "请输入真实网络流量的倍数 [默认: 1000]: " FAKE_NET_MULTI
    read -rp "请输入伪造的IP地址 [默认: 8.8.8.8]: " FAKE_IP

    # 设置默认值
    [ -z "$FAKE_CPU" ] && FAKE_CPU="HUAWEI Kirin 9000s 256 Core"
    [ -z "$FAKE_ARCH" ] && FAKE_ARCH="taishan64"
    [ -z "$FAKE_PLATFORM" ] && FAKE_PLATFORM="HarmonyOS NEXT"
    [ -z "$FAKE_DISK_TOTAL" ] && FAKE_DISK_TOTAL="219902325555200"
    [ -z "$FAKE_MEM_TOTAL" ] && FAKE_MEM_TOTAL="549755813888"
    [ -z "$FAKE_DISK_MULTI" ] && FAKE_DISK_MULTI="10"
    [ -z "$FAKE_MEM_MULTI" ] && FAKE_MEM_MULTI="20"
    [ -z "$FAKE_NET_MULTI" ] && FAKE_NET_MULTI="1000"
    [ -z "$FAKE_IP" ] && FAKE_IP="8.8.8.8"
}

# 安装 Agent
install_agent() {
    info "开始安装 Fake Nezha Agent..."
    
    # 1. 检查环境
    check_root
    check_and_install_deps # <--- 调用新的依赖检查函数
    detect_arch
    
    # 2. 如果已安装，先提示卸载
    if [ -f "$SERVICE_PATH" ]; then
        err "检测到已安装的 Fake Agent。请先运行卸载选项，再进行安装。"
        exit 1
    fi

    # 3. 获取配置
    get_server_config
    get_fake_config

    # 4. 下载并解压
    info "正在从 GitHub 下载 Agent: ${AGENT_URL}"
    if ! curl -L -o "/tmp/${AGENT_ZIP_NAME}" "${AGENT_URL}"; then
        err "下载失败！请检查您的网络或 GitHub 连接。"
        exit 1
    fi
    
    info "创建安装目录: ${INSTALL_PATH}"
    mkdir -p "$INSTALL_PATH"
    
    info "解压 Agent..."
    # 动态识别解压出的可执行文件名
    local agent_exec_name
    agent_exec_name=$(unzip -Z1 "/tmp/${AGENT_ZIP_NAME}" | grep -v -E 'LICENSE|README' | head -n 1 | tr -d '\r')

    if ! unzip -o "/tmp/${AGENT_ZIP_NAME}" -d "$INSTALL_PATH"; then
        err "解压失败！"
        rm -rf "$INSTALL_PATH"
        exit 1
    fi

    if [ -z "$agent_exec_name" ]; then
        err "无法在压缩包中找到可执行文件！"
        rm -rf "$INSTALL_PATH"
        rm "/tmp/${AGENT_ZIP_NAME}"
        exit 1
    fi
    info "检测到可执行文件: ${agent_exec_name}"

    chmod +x "${INSTALL_PATH}/${agent_exec_name}"
    rm "/tmp/${AGENT_ZIP_NAME}"

    # 5. 创建配置文件
    info "正在生成配置文件 config.yaml..."
    cat > "${INSTALL_PATH}/config.yaml" <<EOF
# 由一键安装脚本生成

# --- 面板连接信息 ---
server: ${NZ_SERVER}
secret: ${NZ_CLIENT_SECRET}
tls: ${NZ_TLS}

# --- 核心伪造配置 ---
# 必须关闭自动更新，否则会被官方版覆盖
disable_auto_update: true
fake: true

# --- 自定义伪造信息 ---
version: 6.6.6
arch: "${FAKE_ARCH}"
cpu: "${FAKE_CPU}"
platform: "${FAKE_PLATFORM}"
disktotal: ${FAKE_DISK_TOTAL}
memtotal: ${FAKE_MEM_TOTAL}
diskmultiple: ${FAKE_DISK_MULTI}
memmultiple: ${FAKE_MEM_MULTI}
networkmultiple: ${FAKE_NET_MULTI}
ip: ${FAKE_IP}
EOF

    # 6. 创建并启动 systemd 服务
    info "正在创建 systemd 服务..."
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Nezha Fake Agent Service
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=10s
ExecStart=${INSTALL_PATH}/${agent_exec_name}

[Install]
WantedBy=multi-user.target
EOF

    info "重载 systemd 并启动服务..."
    systemctl daemon-reload
    systemctl enable nezha-fake-agent.service
    systemctl start nezha-fake-agent.service

    # 7. 检查服务状态
    sleep 2
    if systemctl is-active --quiet nezha-fake-agent.service; then
        success "Fake Nezha Agent 安装并启动成功！"
        info "您现在可以去面板查看效果了。"
        info "常用命令:"
        info "  启动: systemctl start nezha-fake-agent.service"
        info "  停止: systemctl stop nezha-fake-agent.service"
        info "  状态: systemctl status nezha-fake-agent.service"
        info "  日志: journalctl -u nezha-fake-agent.service -f"
    else
        err "服务启动失败！请使用 'journalctl -u nezha-fake-agent.service' 命令查看详细日志。"
    fi
}

# 卸载 Agent
uninstall_agent() {
    info "开始卸载 Fake Nezha Agent..."
    check_root

    if [ ! -f "$SERVICE_PATH" ]; then
        err "未找到 Fake Agent 服务，无需卸载。"
        exit 1
    fi

    info "停止并禁用服务..."
    systemctl stop nezha-fake-agent.service
    systemctl disable nezha-fake-agent.service

    info "删除服务文件..."
    rm -f "$SERVICE_PATH"
    systemctl daemon-reload

    info "删除安装目录: ${INSTALL_PATH}"
    rm -rf "$INSTALL_PATH"

    success "Fake Nezha Agent 已被彻底卸载！"
}

# --- 主菜单 ---
main() {
    clear
    echo "========================================="
    echo "  Fake Nezha Agent 一键管理脚本 (v1.4)"
    echo "========================================="
    echo ""
    echo "请选择要执行的操作:"
    echo "1) 安装 Fake Nezha Agent"
    echo "2) 卸载 Fake Nezha Agent"
    echo "0) 退出脚本"
    echo ""
    read -rp "请输入选项 [0-2]: " option

    case "$option" in
        1) install_agent ;;
        2) uninstall_agent ;;
        0) exit 0 ;;
        *) err "无效的选项" ;;
    esac
}

# 脚本入口
main
