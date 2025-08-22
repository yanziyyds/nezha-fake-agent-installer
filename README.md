# nezha-fake-agent-installer
2025-08-22/更新了，美化了界面
 1) 批量安装实例
 2) 卸载所有实例
 3) 查看所有实例运行状态
 4) 重启所有实例
 5) 停止所有实例
 6) 批量修改所有实例配置
 7) 修改单个实例配置
 8) 修改 networkmultiple (流量倍数)
 9) 查看实例配置详情
 0) 退出脚本

# Fake Nezha Agent 一键安装脚本
想要多少服务器就有多少服务器，在朋友面前再也不会抬不起头来了
一键安装/卸载 Fake Nezha Agent 的 Shell 脚本，支持自动解析面板命令、交互式自定义伪造数据，并使用 systemd 持久化运行。

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Language](https://img.shields.io/badge/language-Shell-blue.svg)](./fake_agent.sh)

### 一键安装

请以 `root` 权限，在您的 Linux 服务器上执行以下命令：

```bash
bash -c "$(curl -LfsS "https://raw.githubusercontent.com/yanziyyds/nezha-fake-agent-installer/main/fake_agent.sh?$(date +%s)")"
```

脚本将自动处理所有依赖安装、下载配置及设置开机自启。



### 许可证

本项目基于 [MIT] 许可证发行。

## 致谢

-   **[k08255-lxm用户的(https://github.com/k08255-lxm/nezha-fake-agent-installer)**/在此基础上更改而来]
-   **[dysf888/fake-nezha-agent-v1](https://github.com/dysf888/fake-nezha-agent-v1)**：核心的伪造版 Agent 程序。
-   **[nezhahq/dashboard](https://github.com/nezhahq/dashboard)**：强大的哪吒探针项目。

## 许可证

本项目基于 MIT 许可证开源。详情请见 [LICENSE](LICENSE) 文件。
