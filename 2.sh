#!/bin/bash
#================================================================================
# Name:        Cyberpunk Fake Nezha Manager (Merged Edition)
# Description: 2.sh 主线合并版：完整功能保留 + 炫酷UI + 架构修复 + 进程防阻塞
#              + 面板批量智能改名 + 3.sh 的名称前缀 / 本地批量改名
#              旧版 3.sh / 4.sh 已合并进本文件，不再单独保留
# Version:     4.0 Merged
#================================================================================

# 不启用 set -e：交互菜单需要容忍 systemctl 等命令的非致命失败；
# 关键步骤（下载、解压）均有显式错误处理。
set -uo pipefail

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
    local deps=(curl unzip screen tput bc python3 python3-pip)
    local missing=()
    local dep

    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        local install_cmd=""
        if command -v apt-get >/dev/null 2>&1; then
            install_cmd="apt-get install -y"
            info "正在更新软件包索引..."
            apt-get update >/dev/null 2>&1 || true
        elif command -v dnf >/dev/null 2>&1; then install_cmd="dnf install -y"
        elif command -v yum >/dev/null 2>&1; then install_cmd="yum install -y"
        else err "无法自动安装依赖，请手动安装: ${missing[*]}"; exit 1; fi

        for dep in "${missing[@]}"; do
            info "正在安装依赖: ${c_yellow}$dep${c_reset}..."
            $install_cmd "$dep" >/dev/null 2>&1 || err "依赖 $dep 安装失败，请手动安装"
        done
    fi

    # 确保 python 运行库就绪（PEP 668 系统上需要 --break-system-packages）
    python3 -c "import requests, websocket" >/dev/null 2>&1 || {
        info "正在配置 Python 网络组件 (requests, websocket-client)..."
        pip3 install --break-system-packages -q requests websocket-client >/dev/null 2>&1 \
            || pip3 install -q requests websocket-client >/dev/null 2>&1 \
            || pip install -q requests websocket-client >/dev/null 2>&1 \
            || err "Python 依赖安装失败，面板改名功能将不可用"
    }
}

# --- ⚙️ 系统架构检测 (已修复) ---
detect_arch() {
    case "$(uname -s)" in Linux) os="linux";; *) err "不支持系统: $(uname -s)"; exit 1;; esac

    local raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64|amd64) arch="amd64";;
        aarch64|arm64) arch="arm64";;
        armv7l) arch="armv7";;
        armv6l) arch="armv6";;
        i386|i686) arch="386";;
        *arm*) arch="arm";;
        *) err "不支持架构: $raw_arch"; exit 1;;
    esac
    local asset="nezha-agent-fake_linux_${arch}.zip"
    AGENT_URL="https://gh-proxy.com/https://github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/${asset}"
    AGENT_URL_DIRECT="https://github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/${asset}"
}

# --- 🖥️ UI 组件: 头部 Banner ---
show_banner() {
    clear
    local sys_os=$(cat /etc/os-release | grep PRETTY_NAME | cut -d '"' -f 2)
    local sys_kernel=$(uname -r)
    local sys_uptime=$(uptime -p | sed 's/up //')

    echo -e "${c_purple}==============================================================${c_reset}"
    echo -e "${c_cyan}    Fake Nezha Agent Manager ${c_yellow}>> Merged Edition v4.0 <<${c_reset}"
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
    local bar_str="" empty_str=""
    (( filled > 0 )) && bar_str=$(printf "%0.s█" $(seq 1 $filled))
    (( empty > 0 )) && empty_str=$(printf "%0.s░" $(seq 1 $empty))

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
    local range=${DEFAULT_IP_RANGES[$country]:-}
    [[ -z "$range" ]] && { err "未知国家代码: $country"; return 1; }
    local start_ip=${range%% *}
    local end_ip=${range##* }
    local start_int=$(ip2int "$start_ip")
    local end_int=$(ip2int "$end_ip")
    int2ip $((RANDOM % (end_int - start_int + 1) + start_int))
}

CPU_LIST=("Intel Xeon E5-2680" "Intel Xeon Platinum 8168" "AMD EPYC 7742" "AMD Ryzen 9 5950X" "Intel Core i9-10980XE")
PLATFORM_LIST=("CentOS 7.9" "Ubuntu 20.04" "Ubuntu 22.04" "Debian 11")
COUNTRY_LIST=()

# --- 📥 解析安装命令（纯 bash 正则，不依赖 grep -P） ---
parse_install_cmd() {
    echo -e "${c_cyan}┌───────────────────────────────────────────────────────┐${c_reset}"
    echo -e "${c_cyan}│ 请粘贴哪吒面板的一键安装命令 (包含 token 和 secret)   │${c_reset}"
    echo -e "${c_cyan}└───────────────────────────────────────────────────────┘${c_reset}"
    read -rp "👉 粘贴命令: " full_cmd

    NZ_SERVER=""; NZ_CLIENT_SECRET=""; NZ_TLS="false"
    [[ "$full_cmd" =~ NZ_SERVER=([^[:space:];]+) ]] && NZ_SERVER="${BASH_REMATCH[1]}"
    [[ "$full_cmd" =~ NZ_CLIENT_SECRET=([^[:space:];]+) ]] && NZ_CLIENT_SECRET="${BASH_REMATCH[1]}"
    if [[ "$full_cmd" =~ NZ_TLS=(true|false) ]]; then NZ_TLS="${BASH_REMATCH[1]}"; fi

    if [[ -z "$NZ_SERVER" || -z "$NZ_CLIENT_SECRET" ]]; then
        err "解析失败，请确认粘贴的命令包含 NZ_SERVER 和 NZ_CLIENT_SECRET"
        exit 1
    fi
    success "解析成功: Server=${NZ_SERVER} | TLS=${NZ_TLS}"
}

# --- 🛠️ 核心功能函数 ---

download_agent() {
    local url="$1"; local dest="$2"; local fallback="${3:-}"
    if [[ -f "$dest" ]]; then info "检测到缓存文件，跳过下载"; return; fi

    info "正在下载 Agent ($arch)..."
    if ! curl -fsSL --retry 2 -o "$dest" "$url"; then
        if [[ -n "$fallback" ]]; then
            info "代理下载失败，尝试直连 GitHub..."
            curl -fsSL --retry 2 -o "$dest" "$fallback" || { err "下载失败"; exit 1; }
        else
            err "下载失败"; exit 1
        fi
    fi
    [[ -s "$dest" ]] || { err "下载文件为空"; rm -f "$dest"; exit 1; }
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

    # 稳健地定位可执行文件：优先带可执行权限的非配置/文档文件
    local agent_exec_name=""
    local candidate
    for candidate in "$INSTALL_PATH"/*; do
        [[ -f "$candidate" ]] || continue
        case "$(basename "$candidate")" in *.yaml|*.yml|*.md|*.txt) continue;; esac
        if [[ -x "$candidate" ]]; then agent_exec_name="$(basename "$candidate")"; break; fi
    done
    if [[ -z "$agent_exec_name" ]]; then
        agent_exec_name=$(ls -1A "$INSTALL_PATH" 2>/dev/null | grep -v -E '\.(yaml|yml|md|txt)$' | head -n1)
    fi
    [[ -n "$agent_exec_name" ]] || { err "解压后未找到可执行文件"; exit 1; }
    chmod +x "$INSTALL_PATH/$agent_exec_name"

    local NAME_PREFIX_EFF="${NAME_PREFIX:-Phantom}"
    local custom_name="${NAME_PREFIX_EFF}-${idx}"
    local CPU=$(random_choice "${CPU_LIST[@]}")
    local PLATFORM=$(random_choice "${PLATFORM_LIST[@]}")
    local IP
    if [[ ${#COUNTRY_LIST[@]} -gt 0 ]]; then
        IP=$(generate_geoip_ip "${COUNTRY_LIST[@]}")
    else
        IP=$(generate_geoip_ip)
    fi

    cat > "$CONFIG_FILE" <<EOF
name: "$custom_name"
disable_auto_update: true
fake: true
version: 6.6.6
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

modify_network() {
    echo -e "${c_cyan}--- 修改流量倍数 (networkmultiple) ---${c_reset}"
    prompt "输入实例编号(回车全部修改): " ; read target
    prompt "输入新倍数(回车随机 1-100): " ; read new_val

    local files=()
    if [[ -n "$target" ]]; then
        [[ -f "/opt/nezha-fake-$target/config.yaml" ]] && files=("/opt/nezha-fake-$target/config.yaml") || { err "实例不存在"; return; }
    else
        files=(/opt/nezha-fake-*/config.yaml)
        [[ -f "${files[0]}" ]] || { info "无实例"; return; }
    fi

    local total=${#files[@]}
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
    [[ -f "${configs[0]}" ]] || { info "无实例"; return; }

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
    for file in /opt/nezha-fake-*/config.yaml; do
        [[ -f "$file" ]] || continue
        local idx=$(basename "$(dirname "$file")" | awk -F- '{print $3}')
        echo -e "${c_yellow}>>> 实例 $idx ${c_reset}"
        grep -E "name:|cpu:|memtotal:|disktotal:|ip:|networkmultiple:" "$file" | sed 's/total//g'
    done
    echo -e "${c_blue}==============================================${c_reset}"
    read -rp "按回车继续..."
}

# --- 🏷️ 本地批量改名（并入自 3.sh） ---
modify_names_batch() {
    prompt "输入新名称前缀 (如 HK-GP，留空默认 Node): "; read prefix
    [[ -z "$prefix" ]] && prefix="Node"
    local configs=(/opt/nezha-fake-*/config.yaml)
    [[ -f "${configs[0]}" ]] || { err "无可用实例"; return; }

    local total=${#configs[@]}; local current=0
    for cfg in "${configs[@]}"; do
        current=$((current+1))
        local idx=$(basename "$(dirname "$cfg")" | awk -F- '{print $3}')
        local new_name="${prefix}-${idx}"
        sed -i '/^name:/d' "$cfg"
        sed -i "1i name: \"$new_name\"" "$cfg"
        systemctl restart "nezha-fake-agent-$idx" &>/dev/null || true
        show_progress $current $total "正在将实例 $idx 改名为 $new_name"
    done
    success "改名完成，面板预计 30 秒内同步"
}

# --- 🏷️ 面板智能批量改名（国家 机型 核心+内存） ---
rename_on_dashboard() {
    echo -e "${c_purple}==============================================================${c_reset}"
    echo -e "${c_cyan}       🏷️ 哪吒面板批量智能重命名 [国家+机型+规格]${c_reset}"
    echo -e "${c_purple}==============================================================${c_reset}"

    if ! python3 -c "import requests, websocket" >/dev/null 2>&1; then
        err "缺少 Python 依赖 (requests, websocket-client)，请先安装依赖后重试"
        read -rp "按回车返回..."; return
    fi

    prompt "输入哪吒面板地址 (例如: https://arm.weiaita.top): " ; read panel_url
    panel_url="${panel_url%/}"
    [[ -z "$panel_url" ]] && { err "面板地址不能为空！"; read -rp "按回车返回..."; return; }
    [[ "$panel_url" =~ ^https?:// ]] || { err "面板地址须以 http:// 或 https:// 开头"; read -rp "按回车返回..."; return; }

    # -s 不回显；Token 经环境变量传给 Python，不拼进代码，避免注入与泄露
    prompt "输入面板 API Token (含 nezha:server:write 权限): " ; read -rs api_token; echo ""
    [[ -z "$api_token" ]] && { err "API Token 不能为空！"; read -rp "按回车返回..."; return; }

    prompt "排除的服务器 ID (逗号隔开, 默认 1,2,3): " ; read exclude_ids
    exclude_ids="${exclude_ids:-1,2,3}"

    info "正在连接面板获取实时硬件与地区信息并批量重命名..."

    export FAKE_NEZHA_PANEL_URL="$panel_url" FAKE_NEZHA_API_TOKEN="$api_token" FAKE_NEZHA_EXCLUDE_IDS="$exclude_ids"
    python3 - <<'PYEOF'
import os, sys, json, requests, websocket

panel_url = os.environ["FAKE_NEZHA_PANEL_URL"]
token = os.environ["FAKE_NEZHA_API_TOKEN"]
exclude_str = os.environ.get("FAKE_NEZHA_EXCLUDE_IDS", "")
exclude_list = [int(x.strip()) for x in exclude_str.split(",") if x.strip().isdigit()]

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json",
    "Accept": "application/json"
}

COUNTRY_MAP = {
    "sg": "新加坡", "de": "德国", "gb": "英国", "br": "巴西",
    "jp": "日本", "cn": "中国", "mx": "墨西哥", "co": "哥伦比亚",
    "us": "美国", "hk": "香港", "tw": "台湾", "kr": "韩国", "fr": "法国"
}

def clean_cpu(cpu_str):
    if not cpu_str:
        return "通用"
    c = cpu_str.strip()
    c = c.replace("Intel(R) Xeon(R)", "Xeon").replace("Intel Xeon Platinum ", "Xeon-")
    c = c.replace("Intel Xeon ", "Xeon-").replace("Intel Core ", "")
    c = c.replace("AMD Ryzen 9 ", "R9-").replace("AMD Ryzen ", "Ryzen-")
    c = c.replace("AMD EPYC ", "EPYC-").replace("Processor", "").strip()
    return c


ws_protocol = "wss" if panel_url.startswith("https") else "ws"
domain = panel_url.split("://")[1]
ws_url = f"{ws_protocol}://{domain}/api/v1/ws/server"

servers_data = []
try:
    ws = websocket.create_connection(ws_url, timeout=6)
    msg = ws.recv()
    ws.close()
    data = json.loads(msg)
    servers_data = data.get("servers", [])
except Exception as e:
    print(f"\033[1;31m[-] 连接 WebSocket 失败: {e}\033[0m")
    sys.exit(1)

if not servers_data:
    print("\033[1;33m[-] 未获取到任何在线服务器！\033[0m")
    sys.exit(0)

success_count = 0
fail_count = 0
print(f"\033[1;36m[*] 获取到 {len(servers_data)} 台服务器，开始批量修改...\033[0m\n")

for s in servers_data:
    s_id = s.get("id")
    if s_id in exclude_list:
        print(f"\033[1;35m保留服务器 ID #{s_id:02d} [{s.get('name')}]\033[0m")
        continue
    cc = s.get("country_code", "").lower()
    country = COUNTRY_MAP.get(cc, cc.upper())
    cpus = s.get("host", {}).get("cpu", [])
    cpu_raw = cpus[0] if cpus else ""
    cpu_model = clean_cpu(cpu_raw)
    cores = len(cpus) if isinstance(cpus, list) else 1
    mem_total = s.get("host", {}).get("mem_total", 0)
    mem_gb = round(mem_total / (1024**3))
    new_name = f"{country} {cpu_model} {cores}C+{mem_gb}G"
    url = f"{panel_url}/api/v1/server/{s_id}"
    payload = {"name": new_name}
    try:
        r = requests.patch(url, json=payload, headers=headers, timeout=8)
        res = r.json() if r.text else {}
        if r.status_code in [200, 204] and res.get("success"):
            print(f"\033[1;32m[+] ID #{s_id:02d} -> {new_name} 成功\033[0m")
            success_count += 1
        else:
            print(f"\033[1;31m[-] ID #{s_id:02d} -> {new_name} 失败: {res.get('error', r.text[:50])}\033[0m")
            fail_count += 1
    except Exception as e:
        print(f"\033[1;31m[-] ID #{s_id:02d} 异常: {e}\033[0m")
        fail_count += 1

print(f"\n\033[1;32m[*] 执行完成: 成功 {success_count} 台，失败 {fail_count} 台！\033[0m")
PYEOF
    unset FAKE_NEZHA_PANEL_URL FAKE_NEZHA_API_TOKEN FAKE_NEZHA_EXCLUDE_IDS

    echo ""
    read -rp "按回车返回菜单..."
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
        echo -e "${c_cyan}│${c_reset}  ${c_yellow}10.${c_reset} 🏷️  面板批量改名 (Rename on Panel) [国家+机型+规格]     ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_yellow}11.${c_reset} 🏷️  本地批量改名 (Rename Local) [前缀-编号]               ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}│${c_reset}  ${c_red}0.${c_reset} 🚪 退出脚本 (Exit)                                    ${c_cyan}│${c_reset}"
        echo -e "${c_cyan}└───────────────────────────────────────────────────────────────┘${c_reset}"
        echo -e ""
        prompt "请选择 [0-11]: "; read op

        case "$op" in
            1)
                parse_install_cmd
                prompt "生成实例数量 (N): "; read N
                [[ ! "$N" =~ ^[1-9][0-9]*$ ]] && { err "请输入正整数"; continue; }

                prompt "名称前缀 (留空默认 Phantom): "; read NAME_PREFIX
                NAME_PREFIX="${NAME_PREFIX:-Phantom}"

                prompt "IP国家(逗号隔开,留空默认): "; read country_input
                if [[ -n "$country_input" ]]; then IFS=',' read -r -a COUNTRY_LIST <<< "$country_input"; else COUNTRY_LIST=(); fi

                download_agent "$AGENT_URL" "/tmp/nezha-agent-fake.zip" "$AGENT_URL_DIRECT"

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
            10) rename_on_dashboard ;;
            11) modify_names_batch ;;
            0) exit 0 ;;
            *) err "无效选项" ;;
        esac
    done
}

main
