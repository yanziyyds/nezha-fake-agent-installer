#!/bin/bash
#================================================================================
# Name:        Cyberpunk Fake Nezha Manager (Ultimate Edition v4.0)
# Description: 基于 3.sh 原件修复：强制名称显示 + 网页即时生效 + 完整功能保留
#================================================================================

# --- 🚀 样式初始化 ---
bold=$(tput bold)
underline=$(tput sgr 1)
standout=$(tput smso)
normal=$(tput sgr 0)
blink=$(tput blink)
reverse_video=$(tput rev)

c_reset='\033[0m'
c_red=$standout'\033[1;31m'; c_green=$standout'\033[1;32m'; c_yellow='[1;33m'
c_blue='[1;34m'; c_purple=bold'\033[1;35m'; c_cyan=bold'[0;36m'

bg_red=$reverse_video'\033[41m'; bg_green=$standout'\033[42m\033[37m'
bg_yellow='\033[1;43m'; bg_blue='\033[1;44m'

# --- ⚙️ 系统架构检测 ---
detect_arch() {
    local raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64|amd64) arch="AMD64"; echo "${bg_blue}已检测到 AMD64 架构${c_reset}"
            ;;
        aarch64|arm64) arch="ARM64"; echo "${bg_green}已检测到 ARM64 架构${c_reset}"
            ;;
        *) arch="X86_64"; echo "${bg_yellow}未知架构，将使用默认 X86_64 设置${c_reset}"
            ;;
    esac
}

# --- 🛡️ 权限与依赖检查 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo_error "❌ 请以 root 权限运行！(sudo -i)"
        exit 1
    fi
}

format_title() { 
    local text=$1; 
    printf "$bold\n${c_blue}%-60s${c_reset}$normal\n$blink" "$text"
}

success() {
    echo "${bg_green}[SUCCESS] ${normal}${c_green}$1${c_reset}"
}

info() {
    echo -e " ${bg_blue}$1${c_reset}"
}

prompt() {
    local text=$1
    read -r -p "$(echo "$text")" 
}

error() { 
    echo "${bg_red}[ERROR] $1${normal}"
}

# --- 📋 列表显示修复 ---
show_instance_details() {

cat << EOF

┌─────────────────────────────────────┐
│  ${c_yellow}ID${c_reset}         │  ${c_white}Name${c_reset}             │   IP           │ Status       │
├─────────────────────────────────────┼──────────────────────────────────────┼─────────────────┴──────────────┤
EOF

    for dir in /opt/nezha-fake-*/; do
        idx=$(basename "$dir" | awk -F- '{print $3}')
        local cfg="$dir/config.yaml"
        # 修复读取逻辑：确保能抓取到带引号的名字
        name=$(grep "^name:" "$cfg" | sed 's/name: //g' | tr -d '"' | tr -d "'")
        ip=$(grep "^ip:" "$cfg" | awk '{print $2}' | tr -d '"')

        # 检查 systemd 单元是否存在
        if [[ ! -f "/etc/systemd/system/nezha-fake-agent-$idx.service" ]]; then
            echo " [${c_red}ERROR${c_reset}] 无法找到代理 ${bold}$idx${normal}"
            continue
        fi

        # 获取状态
        st=$(systemctl is-active "nezha-fake-agent-$idx")
        [[ "$st" == "active (running)" ]] && status="${c_green}● 在线●${c_reset}" || status="● 离线 ${bg_red}$st${normal}"

        printf "${bold}%-4s %-15s%-20s %-8s%s\n${c_reset}" \
            "$idx" "    $name" "     $ip" "   $status"

    done

    read -r -p "回车继续..."
}

# --- 🧩 数据生成工具 ---
random_choice() { local arr=("$@"); echo "${arr[$RANDOM % ${#arr[@]}]}"; }
PLATFORM_LIST=("Ubuntu 22.04" "Debian 11" "CentOS 7.9")
CPU_LIST=("Intel Xeon Platinum 8369B" "AMD EPYC 7742" "Intel Core i9-13900K")

# --- 🛠️ 核心功能逻辑 ---

install_instance() {
    local idx=$1; 
    prompt "${c_purple}正在安装代理 $idx${normal}"

    # 创建目录
    mkdir -p "/opt/nezha-fake-$idx"

    # 下载 Agent 文件 (示例 URL)
    AGENT_URL="https://gh-proxy.com/https://github.com/dysf888/fake-nezha-agent-v1/releases/latest/download/nezha-agent-fake_linux_${arch}.zip"
    
    curl -fsSL -o "/tmp/agent.zip" "$AGENT_URL"

    # 提取 Agent 文件到目标目录
    unzip -q "/tmp/agent.zip" -d "/opt/nezha-fake-$idx"

    # 设置名称
    local prefix=${NAME_PREFIX:-"Phantom"}
    custom_name="${prefix}-${idx}"

    # 写入配置文件 (强制 name 在第一行)
    cat > "/opt/nezha-fake-$idx/config.yaml" <<EOF
name: $custom_name
disable_auto_update: true
fake: true
version: 6.6.6
arch: $arch
cpu: $(random_choice "${CPU_LIST[@]}")
platform: $(random_choice "${PLATFORM_LIST[@]}")
memtotal: ${NEZHA_CLIENT_MEM:-$((${RANDOM} % 30 + 1) * 512)}
networkmultiple: ${(("${RANDOM}" % 9 + 1)) * 10}
EOF

    # 创建 systemd 服务文件
    cat > "/etc/systemd/system/nezha-fake-agent-$idx.service" <<SERVICE
[Unit]
Description=Fake Agent $idx - ${custom_name}
After=network.target
[Service]
ExecStart=/opt/nezha-fake-$idx/agent --config /opt/nezha-fake-$idx/config.yaml
Restart=always
RestartSec=3
User=${NEZHA_USER:-root}
WorkingDirectory=/opt/nezha-fake-$idx
[Install]
WantedBy=multi-user.target
SERVICE

    # 启动服务单元
    systemctl daemon-reload
    systemctl enable nezha-fake-agent-$idx.service
    systemctl start nezha-fake-agent-$idx.service
    
}

# --- 🔄 主菜单 ---
main() {

clear -x

format_title "CYBERPUNK FAKE NEZHA MANAGER (v4.0 ULTIMATE EDITION)"

echo "${c_blue}"
cat << EOF

     ╔═════════════════════════════════╗
     ║ ▄▄▄   ▄██  ▄█ ██ ██ ██ ▓▓▓▓▓▓▓▓    ║
     ║   ▀▀▄▄█▓▌▐██@██ ▓▓ ██ ██ ██        ║
     ╚═════════════════════════════════╝

EOF
echo "${c_reset}"

# 显示现有代理列表
if [[ -z $(ls /opt/nezha-fake-* 2>/dev/null) ]]; then
    echo_error "未检测到任何已安装的 Nezha 代理！"
else
    show_instance_details
fi


read -r -p "
请选择操作：

1️⃣   ${bg_blue}🚀 高级模式：手动输入命令行参数进行定制化部署${c_reset}
2️⃣   ${bg_green}🔧 系统模式：一键安装完整代理 (推荐新手使用)${normal}${c_reset}

    " -n 1 -s op
case "$op" in
    [1][a-zA-Z])
        read -r -p "
您选择了高级自定义部署模式！

请选择配置项：

A   ${bg_yellow}🔧 修改现有代理的CPU类型与内存限制${normal}
B   ${bg_red}🗑️  卸载所有代理并重装新版本${c_reset}

    " choice
        case "$choice" in
            [aA]) 
                read -r -p "
请选择修改方式：

1. 手动输入配置参数 (使用JSON格式)
2. 自动模式：选择CPU类型与内存限制

  ${bg_purple}请输入选项: ${c_reset}
                ;;
        esac
    ;;

    2) 
        read -r -p "
您选择了系统自定义部署模式！

请提供以下信息：

🔹 ${bg_blue}NEZHA服务器地址${normal}: " NZ_SERVER
        read -r -p "
🔹 客户端密钥: " NZ_CLIENT_SECRET

        # 默认配置
        CPU_LIST=("Intel Xeon Platinum 8369B" "AMD EPYC 7742" "Intel Core i9-13900K")
        PLATFORM_LIST=("Ubuntu 22.04" "Debian 11" "CentOS 7.9")

        # 随机生成其他参数
        install_instance $((RANDOM % 25 + 1))

        ;;
esac

