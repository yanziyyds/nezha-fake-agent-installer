# nezha-fake-agent-installer
一键安装/卸载 Fake Nezha Agent 的 Shell 脚本，支持自动解析面板命令、交互式自定义伪造数据，并使用 systemd 持久化运行。

# Fake Nezha Agent 一键安装脚本

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Language](https://img.shields.io/badge/language-Shell-blue.svg)](./fake_agent.sh)

一个用于稳定运行 `dysf888/fake-nezha-agent-v1` 的终极解决方案，通过 `screen` 和 `cron` 解决了原程序存在的后台运行及开机自启缺陷。

### 一键安装

请以 `root` 权限，在您的 Linux 服务器上执行以下命令：

```bash
bash -c "$(curl -LfsS "https://raw.githubusercontent.com/yanziyyds/nezha-fake-agent-installer/main/fake_agent.sh?$(date +%s)")"
```

脚本将自动处理所有依赖安装、下载配置及设置开机自启。

### 日常管理

  * **查看实时日志**:

    ```bash
    screen -r nezha-fake
    ```

    *(进入日志界面后，按组合键 `Ctrl+A`，再按 `D` 键即可返回主终端，程序将继续在后台运行)*

  * **停止 Agent 服务**:

    ```bash
    screen -S nezha-fake -X quit
    ```

  * **卸载 Agent**:
    重新运行上方的一键安装脚本，并在菜单中选择“卸载”选项即可。

### 许可证

本项目基于 [MIT] 许可证发行。

## 致谢

-   **[dysf888/fake-nezha-agent-v1](https://github.com/dysf888/fake-nezha-agent-v1)**：核心的伪造版 Agent 程序。
-   **[nezhahq/dashboard](https://github.com/nezhahq/dashboard)**：强大的哪吒探针项目。

## 许可证

本项目基于 MIT 许可证开源。详情请见 [LICENSE](LICENSE) 文件。
