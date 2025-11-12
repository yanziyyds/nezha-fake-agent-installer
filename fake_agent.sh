#!/bin/bash
#=================================================================
# Fake Nezha Agent 批量管理脚本（增强版：全流程进度条 + 国家自定义 IP）
# 修正版 v1：保留原逻辑，修复重复下载与 systemd 启动阻塞问题
#=================================================================

# --- 颜色定义 ---
red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; blue='\033[0;34m'; plain='\033[0m'

# --- 信息输出函数 ---
err() { echo -e "${red}[错误] $1${plain}"; }
success() { echo -e "${green}[成功] $1${plain}"; }
info() { echo -e "${yellow}[信息] $1${plain}"; }
prompt() { echo -en "${blue}$1${plain}"; }

# --- 权限与依赖检查 ---
check_root() { [[ $EUID -ne 0 ]] && err "请以 root 权限运行！" && exit 1; }

check_and_install_deps() {
    # tput 用于光标控制，美化进度条
    for dep in curl unzip screen tput; do
        command -v $dep >/dev/null 2>&1 || {
            info "$dep 未安装，正在安装..."
            if command -v apt-get >/dev/null 2>&1; then apt-get update >/dev/null && apt-get install -y $dep
            elif command -v yum >/dev/null 2>&1; then yum install -y $dep ncurses
            elif command -v dnf >/dev/null 2>&1; then dnf install -y $dep ncurses
            else err "无法自动安装依赖 $dep, 请手动安装后重试"; exit 1; fi
        }
    done
    success "依赖检查完成"
}

# --- 系统架构检测 ---
detect_arch() {
    case "$(uname -s)" in Linux) os="linux";; *) err "不支持系统: $(uname -s)"; exit 1;; esac
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64";;
        aarch64|arm64) arch="arm64";;
        i386|i686) arch="386";;
        *arm*) arch="arm";;
        *) err "不支持架构: $(uname -m)"; exit 1;;
    esac
    AGENT_URL="https://gh-proxy.com/https://github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/nezha-agent-fake_linux_amd64.zip"
}

# --- 解析安装命令 ---
parse_install_cmd() {
    read -rp "请粘贴哪吒面板一键安装命令: " full_cmd
    NZ_SERVER=$(echo "$full_cmd" | grep -oP 'NZ_SERVER=\K[^ ]+')
    NZ_CLIENT_SECRET=$(echo "$full_cmd" | grep -oP 'NZ_CLIENT_SECRET=\K[^ ]+')
    NZ_TLS_RAW=$(echo "$full_cmd" | grep -oP 'NZ_TLS=\K[^ ]+')
    [[ "$NZ_TLS_RAW" == "true" ]] && NZ_TLS="true" || NZ_TLS="false"
    if [[ -z "$NZ_SERVER" || -z "$NZ_CLIENT_SECRET" ]]; then
        err "解析失败，请确认粘贴的命令包含 NZ_SERVER 和 NZ_CLIENT_SECRET"
        exit 1
    fi
    success "解析完成: 服务端=${NZ_SERVER}, 密钥=${NZ_CLIENT_SECRET:0:5}..., TLS=${NZ_TLS}"
}


# ===== 美化后的进度条函数 =====
show_progress() {
    local current=$1
    local total=$2
    local info_msg="$3"
    local bar_width=40
    local filled_char="█"
    local empty_char="░"
    local spinner_chars=("◐" "◓" "◑" "◒")

    local progress=$((current * 100 / total))
    local filled_len=$((progress * bar_width / 100))
    
    local bar=""
    for ((i=0; i<filled_len; i++)); do bar+="${filled_char}"; done
    for ((i=0; i<bar_width - filled_len; i++)); do bar+="${empty_char}"; done

    local spinner_idx=$((current % ${#spinner_chars[@]}))
    local spinner="${blue}${spinner_chars[$spinner_idx]}${plain}"
    
    if [[ $current -eq $total ]]; then
        spinner="${green}✔${plain}"
    fi
    
    # 隐藏光标（容错）
    tput civis 2>/dev/null || true
    printf "\r${yellow}%3d%%${plain} [${green}%s${plain}] ${blue}%d/%d${plain} %-20s ${spinner}" \
           "$progress" "$bar" "$current" "$total" "$info_msg"

    if [[ $current -eq $total ]]; then
        echo
        # 显示光标
        tput cnorm 2>/dev/null || true
    fi
}


# ===== 随机数据生成函数 =====
random_choice() { local arr=("$@"); echo "${arr[$RANDOM % ${#arr[@]}]}"; }
random_disk() { echo $(( (RANDOM % 65 + 64) * 1024 * 1024 * 1024 )); }
random_mem()  { echo $(( (RANDOM % 65 + 64) * 1024 * 1024 * 1024 )); }
random_multiplier() { local min=$1 max=$2; echo $((RANDOM % (max - min + 1) + min)); }
random_traffic() { echo $(( (RANDOM % 500 + 100) * 1024 * 1024 * 1024 )); }

# ===== IP 国家自定义与生成 =====
declare -A DEFAULT_IP_RANGES=(
    [US]="3.0.0.0 3.255.255.255"
    [CN]="36.0.0.0 36.255.255.255"
    [DE]="80.0.0.0 80.255.255.255"
    [FR]="51.0.0.0 51.255.255.255"
    [JP]="133.0.0.0 133.255.255.255"
    [BR]="200.0.0.0 200.255.255.255"
)
ip2int() { local IFS=.; read -r a b c d <<< "$1"; echo $(( (a<<24) + (b<<16) + (c<<8) + d )); }
int2ip() { local ip=$1; echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"; }
generate_geoip_ip() {
    local countries=("$@")
    if [[ ${#countries[@]} -eq 0 ]]; then
        countries=("${!DEFAULT_IP_RANGES[@]}")
    fi
    local country=${countries[$RANDOM % ${#countries[@]}]}
    local range=${DEFAULT_IP_RANGES[$country]}
    local start_ip=${range%% *}
    local end_ip=${range##* }
    local start_int=$(ip2int "$start_ip")
    local end_int=$(ip2int "$end_ip")
    int2ip $((RANDOM % (end_int - start_int + 1) + start_int))
}

# --- 预设数据列表 ---
CPU_LIST=("Intel Xeon E5-2680" "Intel Xeon E5-2690" "Intel Xeon Platinum 8168" "Intel Xeon Platinum 8259CL" "Intel Xeon Platinum 8369B" "AMD EPYC 7302" "AMD EPYC 7402" "AMD EPYC 7502" "AMD EPYC 7742" "AMD EPYC 9654" "AMD Ryzen 9 5950X" "AMD Ryzen Threadripper 3970X" "Intel Core i9-10980XE" "Intel Core i7-10700K" "Intel Core i5-10600K")
PLATFORM_LIST=("CentOS 7.9" "Ubuntu 20.04" "Ubuntu 22.04" "Debian 10" "Debian 11")

# --- Agent 下载与清理 ---
download_agent() {
    local url="$1"; local dest="$2"; local retries=5; local count=0
    while [[ $count -lt $retries ]]; do
        info "下载 Agent: $url (尝试 $((count+1))/$retries)"
        curl -fsSL -o "$dest" "$url" && break
        count=$((count+1)); sleep 2
    done
    [[ $count -eq $retries ]] && err "Agent 下载失败, 请检查网络或链接" && exit 1
    unzip -t "$dest" >/dev/null 2>&1 || { err "ZIP 文件无效或损坏"; rm -f "$dest"; exit 1; }
    success "Agent 下载验证成功"
}

cleanup_instance() {
    local idx=$1
    # 修改点：不要每次都调用 daemon-reload（频繁 reload 可能导致 systemd 锁），只 stop/disable 并移除文件
    systemctl disable --now "nezha-fake-agent-$idx" &>/dev/null || true
    rm -rf "/opt/nezha-fake-$idx"
    rm -f "/etc/systemd/system/nezha-fake-agent-$idx.service"
    # 不在这里调用 daemon-reload，避免并发时 systemd 被锁定
}

# ---- 新增：更安全的启动函数（替换 enable --now 以避免阻塞） ----
safer_start_service() {
    local idx=$1
    local svc="nezha-fake-agent-$idx"
    # reload 一次以应用 unit（单次调用，避免在 cleanup/循环中频繁调用）
    systemctl daemon-reload &>/dev/null || true
    systemctl enable "$svc" &>/dev/null || true
    # 使用非阻塞启动，避免 systemctl start 时阻塞脚本
    systemctl start --no-block "$svc" &>/dev/null || true

    # 等待服务进入 active 状态（短超时），超时则记录并继续
    local wait_sec=8
    local waited=0
    while ! systemctl is-active --quiet "$svc" && [[ $waited -lt $wait_sec ]]; do
        sleep 1
        waited=$((waited+1))
    done

    if systemctl is-active --quiet "$svc"; then
        return 0
    else
        # 仅记录，不退出整个脚本（避免单个服务卡住整个批量）
        err "实例 $idx: 服务未在 ${wait_sec}s 内进入 active（请检查 systemctl status $svc）"
        return 2
    fi
}

# --- 核心安装逻辑 ---
install_instance() {
    local idx=$1
    local INSTALL_PATH="/opt/nezha-fake-$idx"
    local CONFIG_FILE="$INSTALL_PATH/config.yaml"
    mkdir -p "$INSTALL_PATH"
    
    unzip -o "/tmp/nezha-agent-fake.zip" -d "$INSTALL_PATH" >/dev/null 2>&1
    # 修改点：使用 ls -1A 避免 '.' '..' 或空名
    local agent_exec_name=$(ls -1A "$INSTALL_PATH" 2>/dev/null | head -n1)
    [[ -z "$agent_exec_name" || ! -f "$INSTALL_PATH/$agent_exec_name" ]] && { err "解压后找不到 Agent 执行文件 (实例 $idx)"; return 1; }
    chmod +x "$INSTALL_PATH/$agent_exec_name"

    # 生成随机配置
    local CPU=$(random_choice "${CPU_LIST[@]}")
    local ARCH=$(random_choice "amd64" "arm64")
    local PLATFORM=$(random_choice "${PLATFORM_LIST[@]}")
    local DISK_TOTAL=$(random_disk)
    local MEM_TOTAL=$(random_mem)
    local DISK_MULTI=$(random_multiplier 1 2)
    local MEM_MULTI=$(random_multiplier 1 3)
    local UPLOAD_MULTI=$(random_multiplier 1 50)
    local DOWNLOAD_MULTI=$(random_multiplier 1 50)
    local NETWORK_MULTI=$(random_multiplier 1 100)
    local UPLOAD_TOTAL=$(random_traffic)
    local DOWNLOAD_TOTAL=$(random_traffic)
    local IP=$(generate_geoip_ip "${COUNTRY_LIST[@]}")

    # 写入配置文件
    cat > "$CONFIG_FILE" <<EOF
disable_auto_update: true
fake: true
version: 6.6.6
arch: $ARCH
cpu: "$CPU"
platform: "$PLATFORM"
disktotal: $DISK_TOTAL
memtotal: $MEM_TOTAL
diskmultiple: $DISK_MULTI
memmultiple: $MEM_MULTI
network_upload_multiple: $UPLOAD_MULTI
network_download_multiple: $DOWNLOAD_MULTI
networkmultiple: $NETWORK_MULTI
network_upload_total: $UPLOAD_TOTAL
network_download_total: $DOWNLOAD_TOTAL
ip: $IP
EOF

    # 写入 systemd 服务文件
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

    # 修改点：使用 safer_start_service 以避免阻塞
    safer_start_service "$idx" >/dev/null 2>&1 || true
}

# ===== 修改 networkmultiple (支持随机批量) =====
modify_network() {
    read -rp "请输入要修改的实例编号(直接回车批量修改所有): " target
    read -rp "请输入新的 networkmultiple (直接回车随机生成 1-100): " new_val
    local files=()
    if [[ -n "$target" ]]; then
        [[ -f "/opt/nezha-fake-$target/config.yaml" ]] && files=("/opt/nezha-fake-$target/config.yaml") || { err "实例 $target 不存在"; return; }
    else
        files=(/opt/nezha-fake-*/config.yaml)
    fi
    local total=${#files[@]}
    [[ $total -eq 0 ]] && { info "未找到任何实例"; return; }
    local current=0
    for file in "${files[@]}"; do
        current=$((current+1))
        local idx=$(basename "$(dirname "$file")" | awk -F- '{print $3}')
        local val=${new_val:-$(random_multiplier 1 100)}
        sed -i "s|^networkmultiple:.*|networkmultiple: $val|" "$file"
        # 使用 restart --no-block 不会阻塞；但 systemctl restart 没有 --no-block 标志，
        # 我们调用 restart 并不阻塞脚本（一般很快），若遇到阻塞请改为 stop/start --no-block
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null || true
        show_progress $current $total "实例 $idx networkmultiple 已修改"
        sleep 0.1
    done
    success "全部 networkmultiple 修改完成！"
}

# ===== 批量修改配置 =====
modify_all() {
    local configs=(/opt/nezha-fake-*/config.yaml)
    local total=${#configs[@]}
    [[ $total -eq 0 ]] && { info "未找到任何实例"; return; }
    
    read -rp "请输入 CPU 型号 (直接回车保持不变): " new_cpu
    read -rp "请输入内存大小(GB,直接回车保持不变): " new_mem
    read -rp "请输入硬盘大小(GB,直接回车保持不变): " new_disk
    read -rp "请输入上传倍数(直接回车保持不变): " new_up
    read -rp "请输入下载倍数(直接回车保持不变): " new_down
    read -rp "批量修改 IP 国家(逗号分隔,留空保持不变): " country_input
    local selected_countries=()
    if [[ -n "$country_input" ]]; then
        IFS=',' read -r -a selected_countries <<< "$country_input"
    fi
    
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
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null || true
        show_progress $current $total "实例 $idx 配置已修改"
        sleep 0.1
    done
    success "全部实例配置修改完成！"
}

# ===== 单个修改配置 =====
modify_config() {
    local target=$1
    local config_file="/opt/nezha-fake-$target/config.yaml"
    [[ -f "$config_file" ]] || { err "找不到实例 $target 的配置文件"; return; }
    
    read -rp "请输入 CPU 型号 (直接回车保持不变): " new_cpu
    read -rp "请输入内存大小(GB,直接回车保持不变): " new_mem
    read -rp "请输入硬盘大小(GB,直接回车保持不变): " new_disk
    read -rp "请输入上传倍数(直接回车保持不变): " new_up
    read -rp "请输入下载倍数(直接回车保持不变): " new_down
    read -rp "修改 IP 国家(逗号分隔,留空保持不变): " country_input
    
    [[ -n "$new_cpu" ]] && sed -i "s|^cpu:.*|cpu: \"$new_cpu\"|" "$config_file"
    [[ -n "$new_mem" ]] && sed -i "s|^memtotal:.*|memtotal: $((new_mem*1024*1024*1024))|" "$config_file"
    [[ -n "$new_disk" ]] && sed -i "s|^disktotal:.*|disktotal: $((new_disk*1024*1024*1024))|" "$config_file"
    [[ -n "$new_up" ]] && sed -i "s|^network_upload_multiple:.*|network_upload_multiple: $new_up|" "$config_file"
    [[ -n "$new_down" ]] && sed -i "s|^network_download_multiple:.*|network_download_multiple: $new_down|" "$config_file"
    if [[ -n "$country_input" ]]; then
        IFS=',' read -r -a selected_countries <<< "$country_input"
        local new_ip=$(generate_geoip_ip "${selected_countries[@]}")
        sed -i "s|^ip:.*|ip: $new_ip|" "$config_file"
    fi
    
    systemctl restart "nezha-fake-agent-$target" &>/dev/null || true
    success "实例 $target 配置已更新并重启"
}

# ===== 查看实例配置详情 =====
show_instance_details() {
    echo -e "${blue}================== 实例配置详情 ==================${plain}"
    local count=0
    for file in /opt/nezha-fake-*/config.yaml; do
        [[ -f "$file" ]] || continue
        count=$((count+1))
        local idx=$(basename "$(dirname "$file")" | awk -F- '{print $3}')
        echo -e "${yellow}--------- 实例 $idx ---------${plain}"
        grep -E "cpu:|memtotal:|disktotal:|network_upload_multiple:|network_download_multiple:|networkmultiple:|ip:" "$file" | \
        sed -e 's/memtotal:/内存(bytes): /' -e 's/disktotal:/硬盘(bytes): /'
    done
    [[ $count -eq 0 ]] && info "未找到任何实例"
    echo -e "${blue}===================================================${plain}"
}


# ===== 脚本主菜单 =====
main() {
    clear
    check_root
    check_and_install_deps
    detect_arch
    
    while true; do
        echo -e "\n${green}==============================================${plain}"
        echo -e "${blue}          Fake Nezha 批量管理脚本${plain}"
        echo -e "${green}==============================================${plain}"
        echo -e " 1) ${green}批量安装实例${plain}"
        echo -e " 2) ${red}卸载所有实例${plain}"
        echo -e " 3) ${yellow}查看所有实例运行状态${plain}"
        echo -e " 4) ${blue}重启所有实例${plain}"
        echo -e " 5) ${blue}停止所有实例${plain}"
        echo -e " 6) ${yellow}批量修改所有实例配置${plain}"
        echo -e " 7) ${yellow}修改单个实例配置${plain}"
        echo -e " 8) ${yellow}修改 networkmultiple (流量倍数)${plain}"
        echo -e " 9) ${yellow}查看实例配置详情${plain}"
        echo -e " 0) ${plain}退出脚本${plain}"
        echo -e "${green}==============================================${plain}"
        read -rp "请输入选项 [0-9]: " op
        
        case "$op" in
            1)
                parse_install_cmd
                read -rp "请输入要生成实例数量 (N): " N
                [[ ! "$N" =~ ^[1-9][0-9]*$ ]] && { err "请输入一个正整数"; continue; }
                
                read -rp "请输入要生成 IP 的国家(逗号分隔, 留空默认全部 US,CN,DE,FR,JP,BR): " country_input
                if [[ -n "$country_input" ]]; then
                    IFS=',' read -r -a COUNTRY_LIST <<< "$country_input"
                else
                    COUNTRY_LIST=()
                fi

                # ===== 优化：一次性下载 ZIP（若已存在则复用） =====
                if [[ ! -f /tmp/nezha-agent-fake.zip ]]; then
                    download_agent "$AGENT_URL" "/tmp/nezha-agent-fake.zip"
                else
                    info "检测到已存在的 /tmp/nezha-agent-fake.zip，将复用该文件"
                fi

                # 并行控制参数（可调）
                MAX_PARALLEL=5
                total=$N
                running=0

                for i in $(seq 1 $N); do
                    # 后台执行每个实例的清理+安装，避免单个长时间阻塞主循环
                    (
                        cleanup_instance $i
                        install_instance $i
                    ) &

                    # 控制并发数量
                    while [[ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]]; do
                        sleep 0.8
                    done

                    show_progress $i $total "实例 $i 安装中..."
                    sleep 0.05
                done

                # 等待所有后台任务完成
                wait

                # 清理临时 ZIP（如果你想保留缓存以便下次复用，可注释掉下一行）
                rm -f "/tmp/nezha-agent-fake.zip"

                success "全部 $N 个实例安装完成！"
                ;;
            2)
                local dirs=(/opt/nezha-fake-*/)
                local total=${#dirs[@]}
                [[ ! -d "${dirs[0]}" ]] && { info "未找到任何实例"; continue; }
                
                read -rp "$(echo -e ${red}"确定要卸载所有 ${total} 个实例吗? [y/N]: "${plain})" confirm
                [[ "${confirm,,}" != "y" ]] && { info "操作已取消"; continue; }

                local current=0
                for dir in "${dirs[@]}"; do
                    current=$((current+1))
                    local idx=$(basename "$dir" | awk -F- '{print $3}')
                    cleanup_instance $idx
                    show_progress $current $total "实例 $idx 已卸载"
                    sleep 0.1
                done
                success "全部实例已卸载完成！"
                ;;
            3)
                info "正在查询 nezha-fake-agent 服务状态..."
                systemctl list-units --type=service --all | grep 'nezha-fake-agent-.*\.service'
                ;;
            4)
                local dirs=(/opt/nezha-fake-*/)
                local total=${#dirs[@]}
                [[ ! -d "${dirs[0]}" ]] && { info "未找到任何实例"; continue; }

                local current=0
                for dir in "${dirs[@]}"; do
                    current=$((current+1))
                    local idx=$(basename "$dir" | awk -F- '{print $3}')
                    systemctl restart "nezha-fake-agent-$idx" &>/dev/null || true
                    show_progress $current $total "实例 $idx 已重启"
                    sleep 0.1
                done
                success "全部实例已重启完成！"
                ;;
            5)
                local dirs=(/opt/nezha-fake-*/)
                local total=${#dirs[@]}
                [[ ! -d "${dirs[0]}" ]] && { info "未找到任何实例"; continue; }

                local current=0
                for dir in "${dirs[@]}"; do
                    current=$((current+1))
                    local idx=$(basename "$dir" | awk -F- '{print $3}')
                    systemctl stop "nezha-fake-agent-$idx" &>/dev/null || true
                    show_progress $current $total "实例 $idx 已停止"
                    sleep 0.1
                done
                success "全部实例已停止完成！"
                ;;
            6) modify_all ;;
            7)
                read -rp "请输入要修改的实例编号: " idx
                [[ -z "$idx" ]] && { err "实例编号不能为空"; continue; }
                modify_config $idx
                ;;
            8) modify_network ;;
            9) show_instance_details ;;
            0) exit 0 ;;
            *) err "无效选项，请输入 0-9 之间的数字" ;;
        esac
    done
}

main
