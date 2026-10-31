
# Fake Nezha Agent 一键安装脚本

想要多少服务器就有多少服务器，在朋友面前再也不会抬不起头来了
一键安装/卸载 Fake Nezha Agent 的 Shell 脚本，支持自动解析面板命令、交互式自定义伪造数据，并使用 systemd 持久化运行。

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Language](https://img.shields.io/badge/language-Shell-blue.svg)](./2.sh)

### 一键安装

请以 `root` 权限，在您的 Linux 服务器上执行以下命令：

```bash
bash -c "$(curl -LfsS "https://raw.githubusercontent.com/yanziyyds/nezha-fake-agent-installer/main/2.sh?$(date +%s)")"
```

反代命令（Caddy + HTTPS 反代哪吒面板）：

```bash
bash -c "$(curl -LfsS "https://raw.githubusercontent.com/yanziyyds/nezha-fake-agent-installer/main/caddy-nezha.sh?$(date +%s)")"
```

脚本将自动处理所有依赖安装、下载配置及设置开机自启。

### 功能

- 批量安装/卸载实例（systemd 持久化）
- 自动解析面板一键安装命令（NZ_SERVER / NZ_CLIENT_SECRET / NZ_TLS）
- 自定义实例名称前缀、CPU/内存/硬盘、IP 国家、流量倍数
- 面板批量改名：调用面板 API 按「国家 机型 核心+内存」重命名
- 本地批量改名：修改各实例配置中的名称

### 卸载

运行安装脚本，在菜单中选择「批量卸载实例」即可；也可以手动删除 `/opt/nezha-fake-*` 目录与对应的 systemd 服务文件。

### 说明

- 仅支持 Linux + systemd，以 root 运行。
- Agent 二进制来自 dysf888/fake-nezha-agent-v1 的 release，优先经 gh-proxy.com 下载，失败时自动直连 GitHub，并做 ZIP 完整性校验。
- 面板 API Token 只在运行时读取（不回显），经环境变量传给改名逻辑，不写入任何文件；面板命令中的 secret 仅用于生成 systemd 服务的环境变量。
- 旧版 `3.sh` / `4.sh` 已在 v4.0 合并进 `2.sh`，不再单独保留。

### 致谢

- **[k08255-lxm/nezha-fake-agent-installer](https://github.com/k08255-lxm/nezha-fake-agent-installer)**：本项目最初的改动来源。
- **[dysf888/fake-nezha-agent-v1](https://github.com/dysf888/fake-nezha-agent-v1)**：核心的伪造版 Agent 程序。
- **[nezhahq/dashboard](https://github.com/nezhahq/dashboard)**：强大的哪吒探针项目。

### 许可证

本项目基于 MIT 许可证开源。详情请见 [LICENSE](LICENSE) 文件。
