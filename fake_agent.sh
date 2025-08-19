#!/bin/bash
#=================================================================
# Fake Nezha Agent 批量管理脚本（增强版：随机带宽 1~50，定时动态跳动 + 状态管理）
#=================================================================

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; plain='\033[0m'
err() { echo -e "${red}[错误] $1${plain}"; }
success() { echo -e "${green}[成功] $1${plain}"; }
info() { echo -e "${yellow}[信息] $1${plain}"; }

check_root() { [[ $EUID -ne 0 ]] && err "请以 root 权限运行！" && exit 1; }

check_and_install_deps() {
    for dep in curl unzip screen; do
        command -v $dep >/dev/null 2>&1 || {
            info "$dep 未安装，正在安装..."
            if command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y $dep
            elif command -v yum >/dev/null 2>&1; then yum install -y $dep
            elif command -v dnf >/dev/null 2>&1; then dnf install -y $dep
            else err "无法自动安装依赖 $dep"; exit 1; fi
        }
    done
    success "依赖检查完成"
}

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

parse_install_cmd() {
    read -rp "请粘贴哪吒面板一键安装命令: " full_cmd
    NZ_SERVER=$(echo "$full_cmd" | grep -oP 'NZ_SERVER=\K[^ ]+')
    NZ_CLIENT_SECRET=$(echo "$full_cmd" | grep -oP 'NZ_CLIENT_SECRET=\K[^ ]+')
    NZ_TLS_RAW=$(echo "$full_cmd" | grep -oP 'NZ_TLS=\K[^ ]+')
    [[ "$NZ_TLS_RAW" == "true" ]] && NZ_TLS="true" || NZ_TLS="false"
    [[ -z "$NZ_SERVER" || -z "$NZ_CLIENT_SECRET" ]] && err "解析失败，请确认粘贴命令正确" && exit 1
    success "解析完成：NZ_SERVER=$NZ_SERVER, NZ_CLIENT_SECRET=$NZ_CLIENT_SECRET, NZ_TLS=$NZ_TLS"
}

random_choice() { local arr=("$@"); echo "${arr[$RANDOM % ${#arr[@]}]}"; }
random_disk() { echo $(( (RANDOM % 65 + 64) * 1024 * 1024 * 1024 )); }
random_mem()  { echo $(( (RANDOM % 65 + 64) * 1024 * 1024 * 1024 )); }
random_multiplier() { local min=$1 max=$2; echo $((RANDOM % (max - min + 1) + min)); }
random_traffic() { echo $(( (RANDOM % 500 + 100) * 1024 * 1024 * 1024 )); }

IP_RANGES=(
"US:3.0.0.0 3.255.255.255"
"CN:36.0.0.0 36.255.255.255"
"DE:80.0.0.0 80.255.255.255"
"FR:51.0.0.0 51.255.255.255"
"JP:133.0.0.0 133.255.255.255"
"BR:200.0.0.0 200.255.255.255"
)

ip2int() { local IFS=.; read -r a b c d <<< "$1"; echo $(( (a<<24) + (b<<16) + (c<<8) + d )); }
int2ip() { local ip=$1; echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"; }
generate_geoip_ip() {
    local range=${IP_RANGES[$RANDOM % ${#IP_RANGES[@]}]}
    local ips=${range#*:}
    local start_ip=${ips%% *}
    local end_ip=${ips##* }
    local start_int=$(ip2int "$start_ip")
    local end_int=$(ip2int "$end_ip")
    int2ip $((RANDOM % (end_int - start_int + 1) + start_int))
}

CPU_LIST=(
"Intel Xeon E5-2680" "Intel Xeon E5-2690" "Intel Xeon Platinum 8168" "Intel Xeon Platinum 8259CL"
"Intel Xeon Platinum 8369B" "AMD EPYC 7302" "AMD EPYC 7402" "AMD EPYC 7502" "AMD EPYC 7742"
"AMD EPYC 9654" "AMD Ryzen 9 5950X" "AMD Ryzen Threadripper 3970X" "Intel Core i9-10980XE"
"Intel Core i7-10700K" "Intel Core i5-10600K"
)
PLATFORM_LIST=("CentOS 7.9" "Ubuntu 20.04" "Ubuntu 22.04" "Debian 10" "Debian 11")

download_agent() {
    local url="$1"; local dest="$2"; local retries=5; local count=0
    while [[ $count -lt $retries ]]; do
        info "下载 Agent: $url (尝试 $((count+1))/$retries)"
        curl -fL -o "$dest" "$url" && break
        count=$((count+1)); sleep 2
    done
    unzip -t "$dest" >/dev/null 2>&1 || { err "ZIP 文件无效或损坏"; rm -f "$dest"; exit 1; }
    success "Agent 下载验证成功"
}

cleanup_instance() {
    local idx=$1
    rm -rf "/opt/nezha-fake-$idx"
    rm -f "/etc/systemd/system/nezha-fake-agent-$idx.service"
    systemctl daemon-reload >/dev/null 2>&1
}

install_instance() {
    local idx=$1
    INSTALL_PATH="/opt/nezha-fake-$idx"
    CONFIG_FILE="$INSTALL_PATH/config.yaml"
    info "安装实例 $idx 到 $INSTALL_PATH"
    mkdir -p "$INSTALL_PATH"
    download_agent "$AGENT_URL" "/tmp/nezha-agent-fake.zip"
    unzip -o "/tmp/nezha-agent-fake.zip" -d "$INSTALL_PATH"
    rm "/tmp/nezha-agent-fake.zip"
    agent_exec_name=$(ls "$INSTALL_PATH" | head -n1)
    [[ -x "$INSTALL_PATH/$agent_exec_name" ]] || { err "找不到可执行文件"; exit 1; }
    chmod +x "$INSTALL_PATH/$agent_exec_name"

    CPU=$(random_choice "${CPU_LIST[@]}")
    ARCH=$(random_choice "amd64" "arm64")
    PLATFORM=$(random_choice "${PLATFORM_LIST[@]}")
    DISK_TOTAL=$(random_disk)
    MEM_TOTAL=$(random_mem)
    DISK_MULTI=$(random_multiplier 1 2)
    MEM_MULTI=$(random_multiplier 1 3)
    IP=$(generate_geoip_ip)

    UPLOAD_MULTI=$(random_multiplier 1 50)
    DOWNLOAD_MULTI=$(random_multiplier 1 50)
    UPLOAD_TOTAL=$(random_traffic)
    DOWNLOAD_TOTAL=$(random_traffic)

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
network_upload_total: $UPLOAD_TOTAL
network_download_total: $DOWNLOAD_TOTAL
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

    systemctl daemon-reload
    systemctl enable --now "nezha-fake-agent-$idx"

    # 动态带宽跳动脚本
    cat > "$INSTALL_PATH/update_bandwidth.sh" <<'UPD'
#!/bin/bash
CONFIG_FILE="$1"
SERVICE_NAME="$2"
random_multiplier() { local min=$1 max=$2; echo $((RANDOM % (max - min + 1) + min)); }
while true; do
    UPLOAD_MULTI=$(random_multiplier 1 50)
    DOWNLOAD_MULTI=$(random_multiplier 1 50)
    sed -i "s/^network_upload_multiple:.*/network_upload_multiple: $UPLOAD_MULTI/" "$CONFIG_FILE"
    sed -i "s/^network_download_multiple:.*/network_download_multiple: $DOWNLOAD_MULTI/" "$CONFIG_FILE"
    systemctl restart "$SERVICE_NAME"
    sleep 300
done
UPD
    chmod +x "$INSTALL_PATH/update_bandwidth.sh"
    nohup "$INSTALL_PATH/update_bandwidth.sh" "$CONFIG_FILE" "nezha-fake-agent-$idx" >/dev/null 2>&1 &

    success "实例 $idx 安装完成 (IP: $IP, CPU: $CPU, 平台: $PLATFORM)"
    info "日志查看: journalctl -u nezha-fake-agent-$idx -f"
}

uninstall_all() {
    read -rp "确认要卸载所有实例吗？(y/n): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    for service in /etc/systemd/system/nezha-fake-agent-*.service; do
        [[ -f "$service" ]] || continue
        name=$(basename "$service" .service)
        systemctl stop "$name"
        systemctl disable "$name"
        rm -f "$service"
    done
    pkill -f update_bandwidth.sh
    rm -rf /opt/nezha-fake-*
    systemctl daemon-reload
    success "所有实例已卸载完成"
}

show_status_all() {
    echo "========= Fake Agent 状态 ========="
    for service in /etc/systemd/system/nezha-fake-agent-*.service; do
        [[ -f "$service" ]] || continue
        name=$(basename "$service" .service)
        state=$(systemctl is-active "$name")
        echo "$name : $state"
    done
    echo "=================================="
}

restart_all() {
    echo "正在重启所有实例..."
    for service in /etc/systemd/system/nezha-fake-agent-*.service; do
        [[ -f "$service" ]] || continue
        name=$(basename "$service" .service)
        systemctl restart "$name"
    done
    success "所有实例已重启完成"
}

stop_all() {
    echo "正在停止所有实例..."
    for service in /etc/systemd/system/nezha-fake-agent-*.service; do
        [[ -f "$service" ]] || continue
        name=$(basename "$service" .service)
        systemctl stop "$name"
    done
    success "所有实例已停止"
}

main() {
    clear
    echo "=============================="
    echo "  Fake Nezha 批量管理脚本"
    echo "=============================="
    check_root
    check_and_install_deps
    detect_arch
    echo ""
    echo "请选择操作:"
    echo "1) 批量安装实例"
    echo "2) 卸载所有实例"
    echo "3) 查看所有实例运行状态"
    echo "4) 重启所有实例"
    echo "5) 停止所有实例"
    read -rp "请输入选项 [1-5]: " op

    case "$op" in
        1)
            parse_install_cmd
            read -rp "请输入要生成实例数量 (N): " N
            for i in $(seq 1 $N); do
                cleanup_instance $i
                install_instance $i
            done
            success "全部 $N 个实例安装完成！"
            ;;
        2) uninstall_all ;;
        3) show_status_all ;;
        4) restart_all ;;
        5) stop_all ;;
        *) err "无效选项" ;;
    esac
}

main
