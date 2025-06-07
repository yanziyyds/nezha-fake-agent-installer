# nezha-fake-agent-installer
一键安装/卸载 Fake Nezha Agent 的 Shell 脚本，支持自动解析面板命令、交互式自定义伪造数据，并使用 systemd 持久化运行。

# Fake Nezha Agent 一键安装脚本

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Language](https://img.shields.io/badge/language-Shell-blue.svg)](./fake_agent.sh)

一个功能强大的 Shell 脚本，用于一键安装、卸载和管理 [dysf888/fake-nezha-agent-v1](https://github.com/dysf888/fake-nezha-agent-v1)，帮助您轻松地在[哪吒面板](https://github.com/nezhahq/dashboard)中“装逼”。

## 功能特点

-   **全自动安装**：自动检测系统架构 (x86_64, arm64等)，下载并配置最合适的 Agent 程序。
-   **智能配置**：支持直接粘贴哪吒面板官方的一键安装命令，脚本会自动提取服务器地址和密钥，免去手动输入的烦恼。
-   **交互式自定义**：在安装过程中，脚本会引导您输入想伪造的各项信息（CPU型号、核心数、内存大小、流量倍率等），并提供合理的默认值。
-   **稳定可靠**：使用 `systemd` 将 Agent 创建为系统服务，确保开机自启和进程守护，远比 `nohup` 可靠。
-   **轻松管理**：提供完整的安装与卸载功能，一键部署，一键清除，无任何残留。
-   **用户友好**：全程中文提示，关键信息彩色高亮，清晰易懂。

## 使用方法

### 一键安装命令

在您的 Linux 服务器上，使用 `root` 权限执行以下命令即可：

```bash
bash -c "$(curl -LfsS [https://raw.githubusercontent.com/k08255-lxm/nezha-fake-agent-installer/main/fake_agent.sh](https://raw.githubusercontent.com/k08255-lxm/nezha-fake-agent-installer/main/fake_agent.sh))"
```

### 手动安装

1.  克隆本仓库到您的服务器：
    ```bash
    git clone [https://github.com/k08255-lxm/nezha-fake-agent-installer.git](https://github.com/k08255-lxm/nezha-fake-agent-installer.git)
    ```
2.  进入项目目录：
    ```bash
    cd nezha-fake-agent-installer
    ```
3.  为脚本赋予执行权限：
    ```bash
    chmod +x fake_agent.sh
    ```
4.  以 `root` 权限运行脚本：
    ```bash
    sudo ./fake_agent.sh
    ```

### 脚本界面预览

运行后，您会看到一个清晰的管理菜单：

```text
=========================================
  Fake Nezha Agent 一键管理脚本
=========================================

请选择要执行的操作:
1) 安装 Fake Nezha Agent
2) 卸载 Fake Nezha Agent
0) 退出脚本

请输入选项 [0-2]:
```

## 兼容性

本脚本为 Linux 设计，依赖 `systemd` 进行服务管理。理论上支持所有主流发行版，如:
- Ubuntu 16+
- Debian 8+
- CentOS 7+
- AlmaLinux / Rocky Linux
- ...以及其他使用 systemd 的系统

## 致谢

-   **[dysf888/fake-nezha-agent-v1](https://github.com/dysf888/fake-nezha-agent-v1)**：核心的伪造版 Agent 程序。
-   **[nezhahq/dashboard](https://github.com/nezhahq/dashboard)**：强大的哪吒探针项目。

## 许可证

本项目基于 MIT 许可证开源。详情请见 [LICENSE](LICENSE) 文件。
