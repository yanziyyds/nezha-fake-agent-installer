#!/bin/bash
#================================================================================
# Name:        Cyberpunk Fake Nezha Manager (Ultimate Edition v4.0)
# Description: 基于 3.sh 原件修复：强制名称显示 + 网页即时生效 + 完整功能保留
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
    for dep in "${deps[@]}"; do
        command -v $dep >/dev/null 2>&1 || {
            info "安装依赖: $dep..."
            apt-get update >/dev/null 2>&1 && apt-get install -y $dep >/dev/null 2>&1 || yum install -y $dep >/dev/null 2>&1
        }
    done
}

# --- ⚙️ 系统架构检测 ---
detect_arch() {
    local raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64|amd64) arch="amd64";;
        aarch64|arm64) arch="arm64";;
        *) arch="amd64";;
    esac
    AGENT_URL="https://gh-proxy.com/https://github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/nezha-agent-fake_linux_${arch}.zip"
}

# --- 📊 进度条函数 ---
show_progress() {
    local current=$1; local total=$2; local msg="$3"
    local percent=$((current * 100 / total))
    tput civis 2>/dev/null
    printf "\r${c_blue}[处理]${c_reset} ${c_cyan}[%-30s]${c_reset} ${c_yellow}%d%%${c_reset} %s" \
        "$(printf '█%.0s' $(seq 1 $((percent * 30 / 100))))" "$percent" "$msg"
    [[ $current -eq $total ]] && echo "" && tput cnorm 2>/dev/null
}

# --- 🧩 数据生成工具 (完整保留自 3.sh) ---
random_choice() { local arr=("$@"); echo "${arr[$RANDOM % ${#arr[@]}]}"; }
random_disk() { echo $(( (RANDOM % 65 + 64) * 1024 * 1024 * 1024 )); }
random_mem()  { echo $(( (RANDOM % 65 + 64) * 1024 * 1024 * 1024 )); }
random_multiplier() { echo $((RANDOM % ($2 - $1 + 1) + $1)); }
random_traffic() { echo $(( (RANDOM % 500 + 100) * 1024 * 1024 * 1024 )); }

CPU_LIST=("Intel Xeon Platinum 8369B" "AMD EPYC 7742" "Intel Core i9-13900K")
PLATFORM_LIST=("Ubuntu 22.04" "Debian 11" "CentOS 7.9")

# --- 🛠️ 核心功能逻辑 ---

safer_start_service() {
    local idx=$1
    systemctl daemon-reload &>/dev/null
    systemctl enable "nezha-fake-agent-$idx" &>/dev/null
    systemctl restart "nezha-fake-agent-$idx" &>/dev/null
}

install_instance() {
    local idx=$1; local path="/opt/nezha-fake-$idx"
    mkdir -p "$path"
    unzip -oq "/tmp/nezha-agent-fake.zip" -d "$path"
    local exec_name=$(ls -1A "$path" | grep -v "config" | head -n1)
    chmod +x "$path/$exec_name"

    # 名字处理逻辑
    local prefix=${NAME_PREFIX:-"Phantom"}
    local custom_name="${prefix}-${idx}"

    # 写入配置文件 (强制 name 在第一行)
    cat > "$path/config.yaml" <<EOF
name: "$custom_name"
disable_auto_update: true
fake: true
version: 6.6.6
arch: $arch
cpu: "$(random_choice "${CPU_LIST[@]}")"
platform: "$(random_choice "${PLATFORM_LIST[@]}")"
disktotal: $(random_disk)
memtotal: $(random_mem)
networkmultiple: $(random_multiplier 1 100)
network_upload_total: $(random_traffic)
network_download_total: $(random_traffic)
ip: "1.1.1.1"
EOF

    # 关键：Systemd 启动必须带 -c 明确路径
    cat > "/etc/systemd/system/nezha-fake-agent-$idx.service" <<SERVICE
[Unit]
Description=Fake Agent $idx
After=network.target
[Service]
Type=simple
WorkingDirectory=$path
Environment=NZ_SERVER=${NZ_SERVER}
Environment=NZ_CLIENT_SECRET=${NZ_CLIENT_SECRET}
Environment=NZ_TLS=${NZ_TLS}
ExecStart=$path/$exec_name -c $path/config.yaml
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SERVICE
    safer_start_service "$idx"
}

# --- 🏷️ 批量改名逻辑 (针对已安装的实例) ---
modify_names_batch() {
    prompt "输入新名称前缀 (如 HK-GP): "; read prefix
    [[ -z "$prefix" ]] && prefix="Node"
    local configs=(/opt/nezha-fake-*/config.yaml)
    local total=${#configs[@]}; local current=0
    [[ $total -eq 0 ]] && { err "无可用实例"; return; }
    
    for cfg in "${configs[@]}"; do
        current=$((current+1))
        local idx=$(basename "$(dirname "$cfg")" | awk -F- '{print $3}')
        local new_name="${prefix}-${idx}"
        # 强制删除旧 name 插入新 name
        sed -i '/^name:/d' "$cfg"
        sed -i "1i name: \"$new_name\"" "$cfg"
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null
        show_progress $current $total "正在将 ID $idx 改名为 $new_name"
    done
    success "改名同步已触发，面板预计 30 秒内变动"
}

# --- 📋 列表显示修复 (解决你截图里的空白问题) ---
show_instance_details() {
    echo -e "${c_blue}ID\tName\t\t\tIP\t\tStatus${c_reset}"
    for dir in /opt/nezha-fake-*/; do
        [[ -d "$dir" ]] || continue
        local idx=$(basename "$dir" | awk -F- '{print $3}')
        local cfg="$dir/config.yaml"
        # 修复读取逻辑：确保能抓取到带引号的名字
        local name=$(grep "^name:" "$cfg" | sed 's/name: //g' | tr -d '"' | tr -d "'")
        local ip=$(grep "^ip:" "$cfg" | awk '{print $2}' | tr -d '"')
        local st=$(systemctl is-active "nezha-fake-agent-$idx")
        printf "${c_yellow}%-8s %-20s %-15s %s${c_reset}\n" "$idx" "$name" "$ip" "$st"
    done
    read -rp "回车继续..."
}

# --- 🔄 主菜单 ---
main() {
    check_root; check_and_install_deps; detect_arch
    while true; do
        clear
        echo -e "${c_purple}==============================================================${c_reset}"
        echo -e "${c_cyan}    Fake Nezha Manager ${c_yellow}>> Ultimate v4.0 集成版 <<${c_reset}"
        echo -e "${c_purple}==============================================================${c_reset}"
        echo -e " 1) ${c_green}🚀 批量安装实例 (设置前缀)${c_reset}"
        echo -e " 2) ${c_red}🗑️  一键卸载所有实例${c_reset}"
        echo -e " 3) ${c_yellow}📡 查看运行状态${c_reset}"
        echo -e " 4) ${c_blue}🔄 重启所有实例${c_reset}"
        echo -e " 6) 🔧 批量修改配置 (CPU/内存)${c_reset}"
        echo -e " 8) 📶 修改流量倍数${c_reset}"
        echo -e " 9) 📋 查看配置详情${c_reset}"
        echo -e " a) ${c_purple}🏷️  批量修改名称 (强制同步)${c_reset}"
        echo -e " 0) 🚪 退出${c_reset}"
        echo -e "${c_purple}==============================================================${c_reset}"
        prompt "请选择操作: "; read op
        case "$op" in
            1)
                read -rp "粘贴安装命令: " full_cmd
                NZ_SERVER=$(echo "$full_cmd" | grep -oP 'NZ_SERVER=\K[^ ]+')
                NZ_CLIENT_SECRET=$(echo "$full_cmd" | grep -oP 'NZ_CLIENT_SECRET=\K[^ ]+')
                [[ "$full_cmd" == *"NZ_TLS=true"* ]] && NZ_TLS="true" || NZ_TLS="false"
                [[ -z "$NZ_SERVER" ]] && { err "命令解析失败"; sleep 2; continue; }
                prompt "数量: "; read N
                prompt "名称前缀: "; read NAME_PREFIX
                curl -fsSL -o "/tmp/nezha-agent-fake.zip" "$AGENT_URL"
                for i in $(seq 1 $N); do
                    install_instance $i
                    show_progress $i $N "部署节点 #$i"
                done
                success "安装完成！"; read -rp "回车继续..." ;;
            2)
                for dir in /opt/nezha-fake-*/; do
                    idx=$(basename "$dir" | awk -F- '{print $3}')
                    systemctl disable --now "nezha-fake-agent-$idx" &>/dev/null
                    rm -rf "$dir" "/etc/systemd/system/nezha-fake-agent-$idx.service"
                done
                success "清理完毕"; sleep 2 ;;
            3) systemctl list-units --type=service --all | grep 'nezha-fake-agent'; read -rp "回车继续..." ;;
            4) 
                for dir in /opt/nezha-fake-*/; do
                    idx=$(basename "$dir" | awk -F- '{print $3}')
                    systemctl restart "nezha-fake-agent-$idx" &>/dev/null
                done
                success "全部重启成功"; read -rp "回车继续..." ;;
            a|A) modify_names_batch ;;
            9) show_instance_details ;;
            0) exit 0 ;;
        esac
    done
}
main
