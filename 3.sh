#!/bin/bash
#================================================================================
# Name:        Cyberpunk Fake Nezha Manager (Ultimate Edition v3.1 - Fully Fixed)
# Description: 完整功能保留 + 炫酷UI + 架构修复 + 自定义节点命名 + 网页强制生效
# Version:     3.1 Full Integration
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

# --- 🧩 数据生成工具 (完整保留自 3.sh) ---
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
}

# --- 🛠️ 核心功能函数 ---

safer_start_service() {
    local idx=$1
    systemctl daemon-reload &>/dev/null
    systemctl enable "nezha-fake-agent-$idx" &>/dev/null
    systemctl restart "nezha-fake-agent-$idx" &>/dev/null
}

install_instance() {
    local idx=$1
    local INSTALL_PATH="/opt/nezha-fake-$idx"
    local CONFIG_FILE="$INSTALL_PATH/config.yaml"
    mkdir -p "$INSTALL_PATH"
    
    unzip -oq "/tmp/nezha-agent-fake.zip" -d "$INSTALL_PATH"
    local agent_exec_name=$(ls -1A "$INSTALL_PATH" | grep -v "config" | head -n1)
    chmod +x "$INSTALL_PATH/$agent_exec_name"

    # 关键修复：写入自定义名字
    local prefix=${NAME_PREFIX:-"Phantom"}
    local custom_name="${prefix}-${idx}"

    cat > "$CONFIG_FILE" <<EOF
name: "$custom_name"
disable_auto_update: true
fake: true
version: 6.6.6
arch: $arch
cpu: "$(random_choice "${CPU_LIST[@]}")"
platform: "$(random_choice "${PLATFORM_LIST[@]}")"
disktotal: $(random_disk)
memtotal: $(random_mem)
diskmultiple: $(random_multiplier 1 2)
memmultiple: $(random_multiplier 1 3)
network_upload_multiple: $(random_multiplier 1 50)
network_download_multiple: $(random_multiplier 1 50)
networkmultiple: $(random_multiplier 1 100)
network_upload_total: $(random_traffic)
network_download_total: $(random_traffic)
ip: $(generate_geoip_ip "${COUNTRY_LIST[@]}")
EOF

    # 关键修复：ExecStart 强制指定配置文件路径 -c
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

# --- 🏷️ 命名管理系统 (注入自 3.sh 菜单) ---
modify_names_batch() {
    prompt "输入新名称前缀 (如 HK-GP): "; read prefix
    [[ -z "$prefix" ]] && prefix="Node"
    local configs=(/opt/nezha-fake-*/config.yaml)
    local total=${#configs[@]}; local current=0
    for cfg in "${configs[@]}"; do
        current=$((current+1))
        local idx=$(basename "$(dirname "$cfg")" | awk -F- '{print $3}')
        local new_name="${prefix}-${idx}"
        sed -i '/^name:/d' "$cfg"
        sed -i "1i name: \"$new_name\"" "$cfg"
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null
        show_progress $current $total "重命名为 $new_name"
    done
    success "改名完成，面板刷新约需30秒"
}

# --- 📋 其它原有功能函数 (完整保留) ---
modify_network() {
    prompt "输入新倍数(回车随机): " ; read new_val
    local files=(/opt/nezha-fake-*/config.yaml)
    local total=${#files[@]}; local current=0
    for file in "${files[@]}"; do
        current=$((current+1))
        local idx=$(basename "$(dirname "$file")" | awk -F- '{print $3}')
        local val=${new_val:-$(random_multiplier 1 100)}
        sed -i "s|^networkmultiple:.*|networkmultiple: $val|" "$file"
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null
        show_progress $current $total "更新倍数 -> $val"
    done
}

modify_all() {
    prompt "CPU型号: "; read new_cpu
    prompt "内存(GB): "; read new_mem
    local configs=(/opt/nezha-fake-*/config.yaml)
    for config in "${configs[@]}"; do
        local idx=$(basename "$(dirname "$config")" | awk -F- '{print $3}')
        [[ -n "$new_cpu" ]] && sed -i "s|^cpu:.*|cpu: \"$new_cpu\"|" "$config"
        [[ -n "$new_mem" ]] && sed -i "s|^memtotal:.*|memtotal: $((new_mem*1024*1024*1024))|" "$config"
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null
    done
    success "修改完成"
}

show_instance_details() {
    echo -e "${c_blue}ID\tName\t\t\tIP\t\tStatus${c_reset}"
    for file in /opt/nezha-fake-*/config.yaml; do
        [[ -f "$file" ]] || continue
        local idx=$(basename "$(dirname "$file")" | awk -F- '{print $3}')
        local name=$(grep "^name:" "$file" | cut -d'"' -f2)
        local ip=$(grep "^ip:" "$file" | awk '{print $2}')
        local st=$(systemctl is-active "nezha-fake-agent-$idx")
        echo -e "${c_yellow}$idx\t${name:0:15}\t$ip\t$st${c_reset}"
    done
    read -rp "回车继续..."
}

# --- 🔄 主程序 ---
main() {
    check_root; check_and_install_deps; detect_arch
    while true; do
        clear
        echo -e "${c_purple}==============================================================${c_reset}"
        echo -e "${c_cyan}    Fake Nezha Manager ${c_yellow}>> Ultimate v3.1 集成版 <<${c_reset}"
        echo -e "${c_purple}==============================================================${c_reset}"
        echo -e " 1) ${c_green}🚀 批量安装实例 (设置前缀)${c_reset}"
        echo -e " 2) ${c_red}🗑️  一键卸载所有实例${c_reset}"
        echo -e " 3) ${c_yellow}📡 查看运行状态${c_reset}"
        echo -e " 4) ${c_blue}🔄 重启所有实例${c_reset}"
        echo -e " 6) 🔧 批量修改配置 (CPU/内存)${c_reset}"
        echo -e " 8) 📶 修改流量倍数${c_reset}"
        echo -e " 9) 📋 查看配置详情${c_reset}"
        echo -e " a) ${c_purple}🏷️  批量修改名称${c_reset}"
        echo -e " 0) 🚪 退出${c_reset}"
        echo -e "${c_purple}==============================================================${c_reset}"
        prompt "请选择操作: "; read op
        case "$op" in
            1)
                parse_install_cmd
                prompt "数量: "; read N
                prompt "节点名称前缀: "; read NAME_PREFIX
                prompt "国家(CN,US...): "; read c_in
                if [[ -n "$c_in" ]]; then IFS=',' read -r -a COUNTRY_LIST <<< "$c_in"; fi
                curl -fsSL -o "/tmp/nezha-agent-fake.zip" "$AGENT_URL"
                for i in $(seq 1 $N); do
                    install_instance $i
                    show_progress $i $N "正在安装第 $i 个节点"
                done
                success "安装完成" ; read -rp "继续..." ;;
            2)
                for dir in /opt/nezha-fake-*/; do
                    idx=$(basename "$dir" | awk -F- '{print $3}')
                    systemctl disable --now "nezha-fake-agent-$idx" &>/dev/null
                    rm -rf "$dir" "/etc/systemd/system/nezha-fake-agent-$idx.service"
                done
                success "清理完毕" ; sleep 1 ;;
            3) systemctl list-units --type=service --all | grep 'nezha-fake-agent'; read -rp "继续..." ;;
            4) 
                for dir in /opt/nezha-fake-*/; do
                    idx=$(basename "$dir" | awk -F- '{print $3}')
                    systemctl restart "nezha-fake-agent-$idx" &>/dev/null
                done
                success "重启完成" ;;
            6) modify_all ;;
            8) modify_network ;;
            9) show_instance_details ;;
            a|A) modify_names_batch ;;
            0) exit 0 ;;
        esac
    done
}
main
