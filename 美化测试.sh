#!/bin/bash
#================================================================================
# Name:        Cyberpunk Fake Nezha Manager
# Description: 批量管理伪装哪吒探针 (UI增强 + 架构自动修复版)
# Version:     2.0 Pro
# Author:      Gemini AI
#================================================================================

# --- 霓虹配色定义 ---
c_reset='\033[0m'
c_red='\033[1;31m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'
c_blue='\033[1;34m'; c_purple='\033[1;35m'; c_cyan='\033[1;36m'
c_white='\033[1;37m'
bg_red='\033[41;37m'; bg_green='\033[42;37m'

# --- 基础工具函数 ---
err() { echo -e "${bg_red} [ERROR] ${c_reset} ${c_red}$1${c_reset}"; }
success() { echo -e "${bg_green} [SUCCESS] ${c_reset} ${c_green}$1${c_reset}"; }
info() { echo -e "${c_cyan}[INFO]${c_reset} $1"; }
warn() { echo -e "${c_yellow}[WARN]${c_reset} $1"; }

# --- 权限与依赖 ---
check_root() { [[ $EUID -ne 0 ]] && err "请切换到 root 用户运行！(sudo -i)" && exit 1; }

check_deps() {
    local deps=(curl unzip screen tput bc)
    local install_cmd=""
    
    if command -v apt-get >/dev/null 2>&1; then install_cmd="apt-get install -y"
    elif command -v yum >/dev/null 2>&1; then install_cmd="yum install -y"
    elif command -v dnf >/dev/null 2>&1; then install_cmd="dnf install -y"
    else err "未检测到支持的包管理器，请手动安装: ${deps[*]}"; exit 1; fi

    for dep in "${deps[@]}"; do
        if ! command -v $dep >/dev/null 2>&1; then
            info "正在安装依赖: ${c_yellow}$dep${c_reset}..."
            $install_cmd $dep >/dev/null 2>&1
        fi
    done
}

# --- 架构自适应检测 (修复版) ---
detect_arch() {
    local arch_raw=$(uname -m)
    case "$arch_raw" in
        x86_64|amd64) ARCH_CODE="amd64" ;;
        aarch64|arm64) ARCH_CODE="arm64" ;;
        *) err "不支持的 CPU 架构: $arch_raw"; exit 1 ;;
    esac
    # 动态拼接下载地址
    AGENT_URL="https://gh-proxy.com/https://github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/nezha-agent-fake_linux_${ARCH_CODE}.zip"
}

# --- UI 组件: 头部 Banner ---
show_banner() {
    clear
    local sys_os=$(cat /etc/os-release | grep PRETTY_NAME | cut -d '"' -f 2)
    local sys_kernel=$(uname -r)
    local sys_uptime=$(uptime -p | sed 's/up //')
    local sys_arch=$(uname -m)

    echo -e "${c_purple}==============================================================${c_reset}"
    echo -e "${c_cyan}"
    echo -e "   █████▒▄▄▄       ██ ▄█▀▓█████     ███▄    █ ▓█████ ▒█████   "
    echo -e " ▓██   ▒▒████▄     ██▄█▒ ▓█   ▀     ██ ▀█   █ ▓█   ▀▒██▒  ██▒ "
    echo -e " ▒████ ░▒██  ▀█▄  ▓███▄░ ▒███      ▓██  ▀█ ██▒▒███  ▒██░  ██▒ "
    echo -e " ░▓█▒  ░░██▄▄▄▄██ ▓██ █▄ ▒▓█  ▄    ▓██▒  ▐▌██▒▒▓█  ▄▒██   ██░ "
    echo -e " ░▒█░    ▓█   ▓██▒▒██▒ █▄░▒████▒   ▒██░   ▓██░░▒████▒ ████▓▒░ "
    echo -e "  ▒ ░    ▒▒   ▓▒█░▒ ▒▒ ▓▒░░ ▒░ ░   ░ ▒░   ▒ ▒ ░░ ▒░ ░ ▒░▒░▒░  "
    echo -e "${c_reset}"
    echo -e "${c_purple}   >>> 虚拟探针批量管理系统 Pro <<<   ${c_reset}"
    echo -e "${c_purple}==============================================================${c_reset}"
    echo -e "${c_yellow} 🖥️  系统: ${c_white}${sys_os}  ${c_yellow}🧠 内核: ${c_white}${sys_kernel}"
    echo -e "${c_yellow} ⚙️  架构: ${c_white}${sys_arch}     ${c_yellow}⏱️  运行: ${c_white}${sys_uptime}"
    echo -e "${c_purple}==============================================================${c_reset}"
    echo -e ""
}

# --- 进度条动画 ---
show_progress() {
    local current=$1; local total=$2; local msg="$3"
    local percent=$((current * 100 / total))
    local bar_len=30
    local filled=$((percent * bar_len / 100))
    local empty=$((bar_len - filled))
    
    local bar_str=$(printf "%0.s█" $(seq 1 $filled))
    local empty_str=$(printf "%0.s░" $(seq 1 $empty))
    
    # 颜色根据进度变化
    local color=$c_cyan
    [[ $percent -ge 80 ]] && color=$c_green
    
    printf "\r${c_blue}[处理中]${c_reset} ${color}[${bar_str}${empty_str}]${c_reset} ${c_yellow}%3d%%${c_reset} - %s" "$percent" "$msg"
    [[ $current -eq $total ]] && echo ""
}

# --- 核心逻辑 ---

# 随机IP生成器
declare -A IP_RANGES=( [US]="3.0.0.0" [CN]="36.0.0.0" [DE]="80.0.0.0" [JP]="133.0.0.0" )
ip2int() { local a b c d; IFS=. read -r a b c d <<< "$1"; echo $(( (a<<24) + (b<<16) + (c<<8) + d )); }
int2ip() { local ip=$1; echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"; }
get_random_ip() {
    local ranges=("${!IP_RANGES[@]}"); local key=${ranges[$RANDOM % ${#ranges[@]}]}
    local base=$(ip2int "${IP_RANGES[$key]}")
    int2ip $((base + RANDOM % 16777214))
}

# 解析安装命令
parse_cmd() {
    echo -e "${c_cyan}┌───────────────────────────────────────────────────────┐${c_reset}"
    echo -e "${c_cyan}│ 请粘贴哪吒面板的一键安装命令 (包含 token 和 secret)   │${c_reset}"
    echo -e "${c_cyan}└───────────────────────────────────────────────────────┘${c_reset}"
    read -rp "👉 粘贴命令: " raw_cmd
    
    NZ_SERVER=$(echo "$raw_cmd" | grep -oP 'NZ_SERVER=\K[^ ]+')
    NZ_SECRET=$(echo "$raw_cmd" | grep -oP 'NZ_CLIENT_SECRET=\K[^ ]+')
    NZ_TLS=$(echo "$raw_cmd" | grep -oP 'NZ_TLS=\K[^ ]+' || echo "false")
    [[ "$NZ_TLS" == "true" ]] && TLS_BOOL="true" || TLS_BOOL="false"

    if [[ -z "$NZ_SERVER" || -z "$NZ_SECRET" ]]; then
        err "命令解析失败！请确保包含 NZ_SERVER 和 NZ_CLIENT_SECRET"
        exit 1
    fi
    success "解析成功: Server=${NZ_SERVER} | TLS=${TLS_BOOL}"
}

# 服务安全启动
safe_start() {
    local svc="nezha-fake-agent-$1"
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable "$svc" >/dev/null 2>&1
    systemctl start --no-block "$svc" >/dev/null 2>&1
    
    # 非阻塞检测
    for k in {1..5}; do
        if systemctl is-active --quiet "$svc"; then return 0; fi
        sleep 0.5
    done
    return 1
}

# 安装单个实例
install_single() {
    local id=$1; local path="/opt/nezha-fake-$id"
    mkdir -p "$path"
    unzip -oq "/tmp/fake_agent.zip" -d "$path"
    local bin=$(ls -1 "$path" | head -n1)
    chmod +x "$path/$bin"

    # 随机配置
    local cpu_list=("Intel Xeon Platinum 8369B" "AMD EPYC 7763" "AMD Ryzen 9 7950X" "Intel Core i9-13900K")
    local cpu=${cpu_list[$RANDOM % ${#cpu_list}]}
    
    cat > "$path/config.yaml" <<EOF
disable_auto_update: true
fake: true
version: 7.0.0
arch: ${ARCH_CODE}
cpu: "$cpu"
platform: "Ubuntu 22.04 LTS"
disktotal: $(( (RANDOM%100+50)*1024*1024*1024 ))
memtotal: $(( (RANDOM%32+4)*1024*1024*1024 ))
diskmultiple: $((RANDOM%3+1))
memmultiple: $((RANDOM%3+1))
network_upload_multiple: $((RANDOM%50+10))
network_download_multiple: $((RANDOM%50+10))
networkmultiple: $((RANDOM%50+10))
network_upload_total: $(( (RANDOM%500+100)*1024*1024*1024 ))
network_download_total: $(( (RANDOM%500+100)*1024*1024*1024 ))
ip: $(get_random_ip)
EOF

    cat > "/etc/systemd/system/nezha-fake-agent-$id.service" <<SERVICE
[Unit]
Description=Fake Agent $id
After=network.target
[Service]
Type=simple
WorkingDirectory=$path
Environment=NZ_SERVER=${NZ_SERVER}
Environment=NZ_CLIENT_SECRET=${NZ_SECRET}
Environment=NZ_TLS=${TLS_BOOL}
ExecStart=$path/$bin -c $path/config.yaml
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SERVICE

    safe_start "$id"
}

# 批量操作主逻辑
batch_install() {
    parse_cmd
    read -rp "🔢 请输入生成数量 (例如 10): " limit
    [[ ! "$limit" =~ ^[0-9]+$ ]] && err "必须输入数字！" && return

    info "正在下载对应架构 (${ARCH_CODE}) 的 Agent..."
    if [[ ! -f /tmp/fake_agent.zip ]]; then
        curl -fsSL -o /tmp/fake_agent.zip "$AGENT_URL" || { err "下载失败"; return; }
    fi

    echo ""
    for ((i=1; i<=limit; i++)); do
        # 停止旧服务并清理
        systemctl disable --now "nezha-fake-agent-$i" >/dev/null 2>&1
        rm -rf "/opt/nezha-fake-$i"
        
        # 安装新服务
        install_single $i
        show_progress $i $limit "正在部署实例 #$i"
        
        # 并发控制 (每5个暂停一下，防止CPU瞬时飙高)
        [[ $((i % 5)) -eq 0 ]] && sleep 1
    done
    
    success "🎉 全部 $limit 个伪装探针部署完成！"
    echo -e "${c_yellow}提示：面板上线可能需要 10-30 秒，请耐心等待。${c_reset}"
    read -rp "按回车键返回菜单..."
}

batch_uninstall() {
    local services=$(systemctl list-units --all | grep -o 'nezha-fake-agent-[0-9]*' | sort -u)
    local count=$(echo "$services" | wc -l)
    
    if [[ -z "$services" ]]; then warn "未发现任何运行中的伪装实例"; read -rp "按回车返回..."; return; fi
    
    warn "⚠️  即将卸载 $count 个实例，确定吗？[y/N]"
    read -r confirm
    [[ "$confirm" != "y" ]] && return

    local i=0
    for svc in $services; do
        i=$((i+1))
        id=${svc##*-}
        systemctl disable --now "$svc" >/dev/null 2>&1
        rm -f "/etc/systemd/system/$svc.service"
        rm -rf "/opt/nezha-fake-$id"
        show_progress $i $count "正在移除实例 $id"
    done
    systemctl daemon-reload
    success "🗑️  卸载完成！"
    read -rp "按回车返回..."
}

# --- 菜单循环 ---
main() {
    check_root
    check_deps
    detect_arch
    
    while true; do
        show_banner
        echo -e "${c_cyan}┌──────────────────────── [ 菜单选项 ] ─────────────────────────┐${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_green}1.${c_reset} 🚀 批量部署实例 (Install)                                ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_red}2.${c_reset} 🗑️  批量卸载实例 (Uninstall)                              ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_yellow}3.${c_reset} 🔄 批量重启所有 (Restart)                               ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_blue}4.${c_reset} 📊 查看运行状态 (Status)                                ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_purple}5.${c_reset} 🔧 修改配置参数 (Modify Config)                         ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_white}0.${c_reset} 🚪 退出脚本 (Exit)                                    ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}└───────────────────────────────────────────────────────────────┘${c_reset}"
        echo -e ""
        read -rp "👉 请选择 [0-5]: " choice

        case $choice in
            1) batch_install ;;
            2) batch_uninstall ;;
            3) 
                info "正在重启所有服务..."
                systemctl list-units --all | grep 'nezha-fake-agent' | awk '{print $1}' | xargs -I {} systemctl restart {}
                success "重启命令已下发"
                sleep 2
                ;;
            4) 
                echo -e "${c_yellow}当前活跃实例:${c_reset}"
                systemctl list-units --type=service --state=running | grep 'nezha-fake-agent'
                read -rp "按回车继续..." 
                ;;
            5)
                echo -e "功能开发中...请使用编辑器手动修改 /opt/nezha-fake-*/config.yaml"
                sleep 2
                ;;
            0) exit 0 ;;
            *) err "无效输入"; sleep 1 ;;
        esac
    done
}

main
