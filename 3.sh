#!/bin/bash
#================================================================================
# Name:        Cyberpunk Fake Nezha Manager (Ultimate Edition v3.1)
# Description: 完整功能保留 + 炫酷UI + 架构修复 + 自定义节点命名
# Version:     3.1 Name Enhanced
#================================================================================

# --- 🎨 霓虹配色定义 ---
c_reset='\033[0m'
c_red='\033[1;31m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'
c_blue='\033[1;34m'; c_purple='\033[1;35m'; c_cyan='\033[1;36m'
c_white='\033[1;37m'
bg_red='\033[41;37m'; bg_green='\033[42;37m'

# --- 📟 信息输出函数 ---
err() { echo -e "${bg_red} [ERROR] ${c_reset} ${c_red}$1${c_reset}"; }
success() { echo -e "${bg_green} [SUCCESS] ${c_reset} ${c_green}$1${c_reset}"; }
info() { echo -e "${c_cyan}[INFO]${c_reset} $1"; }
prompt() { echo -en "${c_purple}👉 $1${c_reset}"; }

# --- 🛡️ 权限与依赖检查 ---
check_root() { [[ $EUID -ne 0 ]] && err "请以 root 权限运行！(sudo -i)" && exit 1; }

check_and_install_deps() {
    local deps=(curl unzip screen tput bc)
    local install_cmd=""
    
    if command -v apt-get >/dev/null 2>&1; then install_cmd="apt-get install -y"
    elif command -v yum >/dev/null 2>&1; then install_cmd="yum install -y"
    elif command -v dnf >/dev/null 2>&1; then install_cmd="dnf install -y"
    else err "无法自动安装依赖，请手动安装: ${deps[*]}"; exit 1; fi

    for dep in "${deps[@]}"; do
        command -v $dep >/dev/null 2>&1 || {
            info "正在安装依赖: ${c_yellow}$dep${c_reset}..."
            $install_cmd $dep >/dev/null 2>&1
        }
    done
}

# --- ⚙️ 系统架构检测 ---
detect_arch() {
    case "$(uname -s)" in Linux) os="linux";; *) err "不支持系统: $(uname -s)"; exit 1;; esac
    
    local raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64|amd64) arch="amd64";;
        aarch64|arm64) arch="arm64";;
        i386|i686) arch="386";;
        *arm*) arch="arm";;
        *) err "不支持架构: $raw_arch"; exit 1;;
    esac
    AGENT_URL="https://gh-proxy.com/https://github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/nezha-agent-fake_linux_${arch}.zip"
}

# --- 🖥️ UI 组件: 头部 Banner ---
show_banner() {
    clear
    local sys_os=$(cat /etc/os-release | grep PRETTY_NAME | cut -d '"' -f 2)
    local sys_kernel=$(uname -r)
    local sys_uptime=$(uptime -p | sed 's/up //')

    echo -e "${c_purple}==============================================================${c_reset}"
    echo -e "${c_cyan}    Fake Nezha Manager ${c_yellow}>> Ultimate v3.1 (Naming Edition) <<${c_reset}"
    echo -e "${c_purple}==============================================================${c_reset}"
    echo -e "${c_blue} 🖥️  OS: ${c_white}${sys_os}  ${c_blue} ⚙️  Arch: ${c_white}${arch}"
    echo -e "${c_blue} 🧠 Kernel: ${c_white}${sys_kernel}  ${c_blue} ⏱️  Uptime: ${c_white}${sys_uptime}"
    echo -e "${c_purple}==============================================================${c_reset}"
    echo -e ""
}

# --- 📊 进度条函数 ---
show_progress() {
    local current=$1; local total=$2; local msg="$3"
    local percent=$((current * 100 / total))
    local bar_len=30
    local filled=$((percent * bar_len / 100))
    local empty=$((bar_len - filled))
    local bar_str=$(printf "%0.s█" $(seq 1 $filled)) 
    local empty_str=$(printf "%0.s░" $(seq 1 $empty))
    
    local color=$c_cyan
    [[ $percent -ge 100 ]] && color=$c_green

    tput civis 2>/dev/null
    printf "\r${c_blue}[处理]${c_reset} ${color}[${bar_str}${empty_str}]${c_reset} ${c_yellow}%3d%%${c_reset} %s" "$percent" "$msg"
    
    if [[ $current -eq $total ]]; then
        echo ""
        tput cnorm 2>/dev/null
    fi
}

# --- 🧩 数据生成工具 ---
random_choice() { local arr=("$@"); echo "${arr[$RANDOM % ${#arr[@]}]}"; }
random_disk() { echo $(( (RANDOM % 65 + 64) * 1024 * 1024 * 1024 )); }
random_mem()  { echo $(( (RANDOM % 65 + 64) * 1024 * 1024 * 1024 )); }
random_multiplier() { local min=$1 max=$2; echo $((RANDOM % (max - min + 1) + min)); }
random_traffic() { echo $(( (RANDOM % 500 + 100) * 1024 * 1024 * 1024 )); }

declare -A DEFAULT_IP_RANGES=(
    [US]="3.0.0.0 3.255.255.255" [CN]="36.0.0.0 36.255.255.255"
    [DE]="80.0.0.0 80.255.255.255" [FR]="51.0.0.0 51.255.255.255"
    [JP]="133.0.0.0 133.255.255.255" [BR]="200.0.0.0 200.255.255.255"
)
ip2int() { local IFS=.; read -r a b c d <<< "$1"; echo $(( (a<<24) + (b<<16) + (c<<8) + d )); }
int2ip() { local ip=$1; echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"; }
generate_geoip_ip() {
    local countries=("$@")
    [[ ${#countries[@]} -eq 0 ]] && countries=("${!DEFAULT_IP_RANGES[@]}")
    local country=${countries[$RANDOM % ${#countries[@]}]}
    local range=${DEFAULT_IP_RANGES[$country]}
    local start_int=$(ip2int "${range%% *}")
    local end_int=$(ip2int "${range##* }")
    int2ip $((RANDOM % (end_int - start_int + 1) + start_int))
}

CPU_LIST=("Intel Xeon E5-2680" "Intel Xeon Platinum 8168" "AMD EPYC 7742" "AMD Ryzen 9 5950X" "Intel Core i9-10980XE")
PLATFORM_LIST=("CentOS 7.9" "Ubuntu 20.04" "Ubuntu 22.04" "Debian 11")

# --- 📥 解析安装命令 ---
parse_install_cmd() {
    echo -e "${c_cyan}┌───────────────────────────────────────────────────────┐${c_reset}"
    echo -e "${c_cyan}│ 请粘贴哪吒面板的一键安装命令 (包含 token 和 secret)   │${c_reset}"
    echo -e "${c_cyan}└───────────────────────────────────────────────────────┘${c_reset}"
    read -rp "👉 粘贴命令: " full_cmd
    
    NZ_SERVER=$(echo "$full_cmd" | grep -oP 'NZ_SERVER=\K[^ ]+')
    NZ_CLIENT_SECRET=$(echo "$full_cmd" | grep -oP 'NZ_CLIENT_SECRET=\K[^ ]+')
    NZ_TLS_RAW=$(echo "$full_cmd" | grep -oP 'NZ_TLS=\K[^ ]+')
    [[ "$NZ_TLS_RAW" == "true" ]] && NZ_TLS="true" || NZ_TLS="false"
    
    if [[ -z "$NZ_SERVER" || -z "$NZ_CLIENT_SECRET" ]]; then
        err "解析失败，请确认粘贴的命令包含 NZ_SERVER 和 NZ_CLIENT_SECRET"
        exit 1
    fi
    success "解析成功: Server=${NZ_SERVER} | TLS=${NZ_TLS}"
}

# --- 🛠️ 核心功能函数 ---

download_agent() {
    local url="$1"; local dest="$2"
    if [[ -f "$dest" ]]; then info "检测到缓存文件，跳过下载"; return; fi
    
    info "正在下载 Agent ($arch)..."
    curl -fsSL -o "$dest" "$url" || { err "下载失败"; exit 1; }
    unzip -t "$dest" >/dev/null 2>&1 || { err "ZIP文件损坏"; rm -f "$dest"; exit 1; }
    success "下载并验证成功"
}

cleanup_instance() {
    local idx=$1
    systemctl disable --now "nezha-fake-agent-$idx" &>/dev/null || true
    rm -rf "/opt/nezha-fake-$idx"
    rm -f "/etc/systemd/system/nezha-fake-agent-$idx.service"
}

safer_start_service() {
    local idx=$1
    local svc="nezha-fake-agent-$idx"
    systemctl daemon-reload &>/dev/null
    systemctl enable "$svc" &>/dev/null
    systemctl start --no-block "$svc" &>/dev/null
    
    local waited=0
    while ! systemctl is-active --quiet "$svc" && [[ $waited -lt 5 ]]; do
        sleep 0.5
        waited=$((waited+1))
    done
}

install_instance() {
    local idx=$1
    local INSTALL_PATH="/opt/nezha-fake-$idx"
    local CONFIG_FILE="$INSTALL_PATH/config.yaml"
    mkdir -p "$INSTALL_PATH"
    
    unzip -oq "/tmp/nezha-agent-fake.zip" -d "$INSTALL_PATH"
    local agent_exec_name=$(ls -1A "$INSTALL_PATH" 2>/dev/null | head -n1)
    chmod +x "$INSTALL_PATH/$agent_exec_name"

    local CPU=$(random_choice "${CPU_LIST[@]}")
    local PLATFORM=$(random_choice "${PLATFORM_LIST[@]}")
    local IP=$(generate_geoip_ip "${COUNTRY_LIST[@]}")
    
    # 获取传入的名称前缀，默认为 Phantom
    local prefix=${NAME_PREFIX:-"Phantom"}
    local custom_name="${prefix}-${idx}"

    cat > "$CONFIG_FILE" <<EOF
disable_auto_update: true
fake: true
version: 6.6.6
name: "$custom_name"
arch: $arch
cpu: "$CPU"
platform: "$PLATFORM"
disktotal: $(random_disk)
memtotal: $(random_mem)
diskmultiple: $(random_multiplier 1 2)
memmultiple: $(random_multiplier 1 3)
network_upload_multiple: $(random_multiplier 1 50)
network_download_multiple: $(random_multiplier 1 50)
networkmultiple: $(random_multiplier 1 100)
network_upload_total: $(random_traffic)
network_download_total: $(random_traffic)
ip: $IP
EOF

    cat > "/etc/systemd/system/nezha-fake-agent-$idx.service" <<SERVICE
[Unit]
Description=Fake Nezha Agent $idx
After=network.target
[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
Environment=NZ_SERVER=${NZ_SERVER}
Environment=NZ_CLIENT_SECRET=${NZ_CLIENT_SECRET}
Environment=NZ_TLS=${NZ_TLS}
ExecStart=$INSTALL_PATH/$agent_exec_name -c $CONFIG_FILE
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SERVICE

    safer_start_service "$idx"
}

# --- 🏷️ 命名管理函数 ---

modify_names_batch() {
    echo -e "${c_cyan}--- 批量修改节点名称 ---${c_reset}"
    prompt "输入新名称前缀 (如 CDN-HK): "; read prefix
    [[ -z "$prefix" ]] && prefix="Phantom"
    
    local configs=(/opt/nezha-fake-*/config.yaml)
    local total=${#configs[@]}
    [[ $total -eq 0 ]] && { info "无实例"; return; }
    
    local current=0
    for cfg in "${configs[@]}"; do
        current=$((current+1))
        local idx=$(basename "$(dirname "$cfg")" | awk -F- '{print $3}')
        local new_name="${prefix}-${idx}"
        
        # 使用 sed 修改或追加 name 字段
        if grep -q "^name:" "$cfg"; then
            sed -i "s|^name:.*|name: \"$new_name\"|" "$cfg"
        else
            echo "name: \"$new_name\"" >> "$cfg"
        fi
        
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null
        show_progress $current $total "节点重命名 -> $new_name"
    done
    success "批量重命名完成"
}

modify_name_single() {
    echo -e "${c_cyan}--- 修改单个节点名称 ---${c_reset}"
    prompt "输入实例编号: "; read target
    local cfg="/opt/nezha-fake-$target/config.yaml"
    [[ ! -f "$cfg" ]] && { err "实例不存在"; return; }
    
    prompt "输入新名称 (如 Super-VIP-1): "; read new_name
    [[ -z "$new_name" ]] && { err "名称不能为空"; return; }
    
    if grep -q "^name:" "$cfg"; then
        sed -i "s|^name:.*|name: \"$new_name\"|" "$cfg"
    else
        echo "name: \"$new_name\"" >> "$cfg"
    fi
    
    systemctl restart "nezha-fake-agent-$target" &>/dev/null
    success "实例 $target 已重命名为: $new_name"
}

modify_network() {
    echo -e "${c_cyan}--- 修改流量倍数 (networkmultiple) ---${c_reset}"
    prompt "输入实例编号(回车全部修改): " ; read target
    prompt "输入新倍数(回车随机 1-100): " ; read new_val
    
    local files=()
    if [[ -n "$target" ]]; then
        [[ -f "/opt/nezha-fake-$target/config.yaml" ]] && files=("/opt/nezha-fake-$target/config.yaml") || { err "实例不存在"; return; }
    else
        files=(/opt/nezha-fake-*/config.yaml)
    fi
    
    local total=${#files[@]}
    [[ $total -eq 0 ]] && { info "无实例"; return; }
    
    local current=0
    for file in "${files[@]}"; do
        current=$((current+1))
        local idx=$(basename "$(dirname "$file")" | awk -F- '{print $3}')
        local val=${new_val:-$(random_multiplier 1 100)}
        sed -i "s|^networkmultiple:.*|networkmultiple: $val|" "$file"
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null
        show_progress $current $total "实例 $idx 更新倍数 -> $val"
    done
    success "修改完成"
}

modify_all() {
    local configs=(/opt/nezha-fake-*/config.yaml)
    [[ ${#configs[@]} -eq 0 ]] && { info "无实例"; return; }
    
    echo -e "${c_yellow}批量修改配置 (回车保持不变)${c_reset}"
    prompt "CPU型号: "; read new_cpu
    prompt "内存(GB): "; read new_mem
    prompt "硬盘(GB): "; read new_disk
    prompt "上传倍数: "; read new_up
    prompt "下载倍数: "; read new_down
    prompt "IP国家(逗号隔开): "; read country_input
    
    local selected_countries=()
    [[ -n "$country_input" ]] && IFS=',' read -r -a selected_countries <<< "$country_input"
    
    local total=${#configs[@]}
    local current=0
    for config in "${configs[@]}"; do
        current=$((current+1))
        local idx=$(basename "$(dirname "$config")" | awk -F- '{print $3}')
        [[ -n "$new_cpu" ]] && sed -i "s|^cpu:.*|cpu: \"$new_cpu\"|" "$config"
        [[ -n "$new_mem" ]] && sed -i "s|^memtotal:.*|memtotal: $((new_mem*1024*1024*1024))|" "$config"
        [[ -n "$new_disk" ]] && sed -i "s|^disktotal:.*|disktotal: $((new_disk*1024*1024*1024))|" "$config"
        [[ -n "$new_up" ]] && sed -i "s|^network_upload_multiple:.*|network_upload_multiple: $new_up|" "$config"
        [[ -n "$new_down" ]] && sed -i "s|^network_download_multiple:.*|network_download_multiple: $new_down|" "$config"
        if [[ ${#selected_countries[@]} -gt 0 ]]; then
            local new_ip=$(generate_geoip_ip "${selected_countries[@]}")
            sed -i "s|^ip:.*|ip: $new_ip|" "$config"
        fi
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null
        show_progress $current $total "实例 $idx 配置更新"
    done
    success "批量修改完成"
}

modify_config() {
    prompt "输入实例编号: "; read target
    local config_file="/opt/nezha-fake-$target/config.yaml"
    [[ ! -f "$config_file" ]] && { err "文件不存在"; return; }
    
    echo -e "${c_yellow}修改实例 $target (回车跳过)${c_reset}"
    prompt "CPU型号: "; read new_cpu
    prompt "内存(GB): "; read new_mem
    prompt "硬盘(GB): "; read new_disk
    
    [[ -n "$new_cpu" ]] && sed -i "s|^cpu:.*|cpu: \"$new_cpu\"|" "$config_file"
    [[ -n "$new_mem" ]] && sed -i "s|^memtotal:.*|memtotal: $((new_mem*1024*1024*1024))|" "$config_file"
    [[ -n "$new_disk" ]] && sed -i "s|^disktotal:.*|disktotal: $((new_disk*1024*1024*1024))|" "$config_file"
    
    systemctl restart "nezha-fake-agent-$target" &>/dev/null
    success "实例 $target 更新完毕"
}

show_instance_details() {
    echo -e "${c_blue}================== 实例详情 ==================${c_reset}"
    echo -e "${c_white}ID\tName\t\t\tIP\t\tCPU${c_reset}"
    for file in /opt/nezha-fake-*/config.yaml; do
        [[ -f "$file" ]] || continue
        local idx=$(basename "$(dirname "$file")" | awk -F- '{print $3}')
        local name=$(grep "^name:" "$file" | cut -d'"' -f2)
        local ip=$(grep "^ip:" "$file" | awk '{print $2}')
        local cpu=$(grep "^cpu:" "$file" | cut -d'"' -f2)
        # 截断显示防止换行
        echo -e "${c_yellow}$idx\t${name:0:15}\t$ip\t${cpu:0:20}...${c_reset}"
    done
    echo -e "${c_blue}==============================================${c_reset}"
    read -rp "按回车继续..."
}

# --- 🔄 主程序循环 ---
main() {
    check_root
    check_and_install_deps
    detect_arch
    
    while true; do
        show_banner
        echo -e "${c_cyan}┌──────────────────────── [ 功能菜单 ] ─────────────────────────┐${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_green}1.${c_reset} 🚀 批量安装实例 (Install)                                ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_red}2.${c_reset} 🗑️  批量卸载实例 (Uninstall)                              ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_yellow}3.${c_reset} 📡 查看运行状态 (Status)                                ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_blue}4.${c_reset} 🔄 重启所有实例 (Restart)                                ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_purple}5.${c_reset} ⏹️  停止所有实例 (Stop)                                   ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_white}6.${c_reset} 🔧 批量修改配置 (Batch Config)                            ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_white}7.${c_reset} ✏️  修改单个实例 (Single Config)                           ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_white}8.${c_reset} 📶 修改流量倍数 (Network Multi)                           ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_white}9.${c_reset} 📋 查看配置详情 (Details)                                 ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_white}a.${c_reset} 🏷️  批量修改名称 (Batch Rename)                          ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_white}b.${c_reset} 🏷️  修改单个名称 (Single Rename)                         ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_red}0.${c_reset} 🚪 退出脚本 (Exit)                                    ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}└───────────────────────────────────────────────────────────────┘${c_reset}"
        echo -e ""
        prompt "请选择指令: "; read op
        
        case "$op" in
            1)
                parse_install_cmd
                prompt "生成实例数量 (N): "; read N
                [[ ! "$N" =~ ^[1-9][0-9]*$ ]] && { err "请输入正整数"; continue; }
                
                # 新增名称询问
                prompt "节点名称前缀 (默认 'Phantom', 生成 Phantom-1...): "; read NAME_PREFIX
                
                prompt "IP国家(逗号隔开,留空默认): "; read country_input
                if [[ -n "$country_input" ]]; then IFS=',' read -r -a COUNTRY_LIST <<< "$country_input"; else COUNTRY_LIST=(); fi

                download_agent "$AGENT_URL" "/tmp/nezha-agent-fake.zip"
                
                MAX_PARALLEL=5
                total=$N
                
                for i in $(seq 1 $N); do
                    ( cleanup_instance $i; install_instance $i ) &
                    while [[ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]]; do sleep 0.5; done
                    show_progress $i $total "部署实例 #$i"
                    sleep 0.05
                done
                wait
                success "全部安装完成！"
                read -rp "按回车继续..."
                ;;
            2)
                dirs=(/opt/nezha-fake-*/)
                [[ ! -d "${dirs[0]}" ]] && { info "无实例"; sleep 1; continue; }
                prompt "确认卸载所有实例? [y/N]: "; read confirm
                [[ "${confirm,,}" != "y" ]] && continue
                
                local total=${#dirs[@]}; local current=0
                for dir in "${dirs[@]}"; do
                    current=$((current+1))
                    idx=$(basename "$dir" | awk -F- '{print $3}')
                    cleanup_instance $idx
                    show_progress $current $total "已卸载实例 $idx"
                done
                success "卸载完成"; read -rp "按回车继续..."
                ;;
            3)
                info "服务状态查询中..."
                systemctl list-units --type=service --all | grep 'nezha-fake-agent'
                read -rp "按回车继续..."
                ;;
            4)
                dirs=(/opt/nezha-fake-*/)
                [[ ! -d "${dirs[0]}" ]] && { info "无实例"; sleep 1; continue; }
                local total=${#dirs[@]}; local current=0
                for dir in "${dirs[@]}"; do
                    current=$((current+1))
                    idx=$(basename "$dir" | awk -F- '{print $3}')
                    systemctl restart "nezha-fake-agent-$idx" &>/dev/null
                    show_progress $current $total "已重启实例 $idx"
                done
                success "全部重启完成"; read -rp "按回车继续..."
                ;;
            5)
                dirs=(/opt/nezha-fake-*/)
                [[ ! -d "${dirs[0]}" ]] && { info "无实例"; sleep 1; continue; }
                local total=${#dirs[@]}; local current=0
                for dir in "${dirs[@]}"; do
                    current=$((current+1))
                    idx=$(basename "$dir" | awk -F- '{print $3}')
                    systemctl stop "nezha-fake-agent-$idx" &>/dev/null
                    show_progress $current $total "已停止实例 $idx"
                done
                success "全部停止完成"; read -rp "按回车继续..."
                ;;
            6) modify_all ;;
            7) modify_config ;;
            8) modify_network ;;
            9) show_instance_details ;;
            a|A) modify_names_batch ;;
            b|B) modify_name_single ;;
            0) exit 0 ;;
            *) err "无效选项" ;;
        esac
    done
}

main
