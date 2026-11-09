# Btoll 安装与卸载

适用 Apple Silicon（M 系列）、macOS 14.6 或更新版本。打开 Btoll-1.0.0-arm64.pkg，由系统安装器完成应用和独立风扇服务安装，再打开“应用程序”中的 Btoll。管理员密码只在 macOS 系统窗口输入。

安装包未经 Apple 公证，使用临时签名。如果系统拦截，在“隐私与安全性”核对后选择“仍要打开”。不要关闭 Gatekeeper。

Codex 面板读取当前用户自己的官方 Codex 登录、配额与本机会话。需要先安装并登录官方 Codex；活动数据以接口返回为准，无数据时不会编造。包内没有打包者的登录、聊天或监控快照。

首次打开会在当前用户目录部署监控运行时与 LaunchAgent，使用内置 Node，不依赖 Homebrew、Python 或目标机器上的 Xcode。现有运行数据、设置和撤销授权保留。系统询问音乐、蓝牙等权限时，按需要选择。

风扇调速需要本机有风扇且接口受支持；半速、3/4、自定义及全速均受设备范围限制，手动模式到期恢复自动。不要与其他调速工具同时控制风扇。未经逐台实测的型号可能只能显示部分监控数据。

应用流量约每 10 秒采样一次，磁盘进程速率需要两次采样。系统权限不足的进程可能无法提供内存或磁盘计数。电池端功率不是整机功耗，阻止休眠列表来自当前系统电源断言。

## 更新

从本仓库 Releases 下载新的安装器覆盖安装。此分支关闭上游 Atoll 自动更新，避免被原版替换。内部兼容标识保留 local.bsstoll.mac，更新不要求迁移原有设置。已有 bsstoll 安装时，请先退出旧应用；可将旧应用归档为 ZIP 后移走，再安装 Btoll，避免两个应用并存。

## 卸载

先在 Btoll 风扇面板切回自动，退出应用。在终端执行以下命令停止当前用户的本地扩展：

```sh
launchctl bootout "gui/$(id -u)/local.codex.atoll-status"
rm -f "$HOME/Library/LaunchAgents/local.codex.atoll-status.plist"
```

删除“应用程序”中的 Btoll。若确定不再使用独立风扇服务，可卸载服务（需要管理员权限）：

```sh
sudo launchctl bootout system/local.bsstoll.fan-helper
sudo rm -f /Library/LaunchDaemons/local.bsstoll.fan-helper.plist /Library/PrivilegedHelperTools/local.bsstoll.fan-helper
```

服务收到退出信号时会尝试恢复自动。当前用户的数据位于 `~/Library/Application Support/AtollCodexBridge`，日志位于 `~/Library/Logs/AtollCodexBridge`；这些文件默认保留，需要时自行归档或删除。
