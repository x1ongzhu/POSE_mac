# Palm OS 模拟器 MCP 服务

macOS App 启动后，会为每个窗口创建一个仅当前用户可访问的本机 Unix socket。`palmos-mcp-server.py` 是 stdio MCP 服务，使用 Python 3 标准库，无需安装额外依赖。它会发现正在运行的窗口，并把 MCP 工具调用转给对应的模拟器进程；不开放网络端口。

## 连接 Codex

将下面内容加入 `~/.codex/config.toml`，把脚本路径改为本机实际位置：

```toml
[mcp_servers.palmos]
command = "/usr/bin/python3"
args = ["/absolute/path/to/Palm OS.app/Contents/Resources/palmos-mcp-server.py"]
```

在源码目录工作时，也可以将 `args` 指向 `tools/palmos-mcp-server.py` 的绝对路径。重启 Codex 后，先调用 `palm_list_instances`；若 App 尚未打开，调用 `palm_open_emulator`。Codex 的 [MCP 配置说明](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) 还提供 CLI 和界面添加方式。

如果 App 不在仓库的 `dist/` 中，且 MCP 脚本也未从 App 包内运行，可在 MCP 服务配置中设置环境变量 `PALM_OS_APP_PATH` 为 `Palm OS.app` 的绝对路径。

其他支持 stdio MCP 的客户端可将命令设为 `/usr/bin/python3`，参数设为脚本的绝对路径。服务使用 MCP `2025-11-25` 初始化协议和每行一条 JSON-RPC 消息；支持新协议的客户端可回退到这一版本。

## 常用调试流程

1. `palm_open_emulator` 新建独立窗口，可传 `rom_path` 和 `install_path`；也可先手动打开 App。
2. `palm_list_instances` 列出窗口。多个窗口同时运行时，在后续工具中传 `instance_id`。
3. `palm_load_rom` 启动指定 ROM，或用 `palm_start` 运行当前 ROM；调用 `palm_wait_ready` 等待系统可安装应用。
4. `palm_install` 安装 PRC/PDB。PRC 默认安装后启动；也可用 `palm_launch_app` 再次打开已安装应用。
5. 用 `palm_screenshot` 查看画面，并用 `palm_tap`、`palm_pen`、`palm_type_text`、`palm_press_key` 和 `palm_hardware_button` 操作设备。
6. 用 `palm_reset` 软复位，`palm_save` 保存会话，`palm_stop` 保存并停止，`palm_quit` 保存并关闭指定实例。`palm_set_network` 控制网络重定向。

截图返回 PNG 图像；触控坐标以截图左上角为原点，可从 `palm_status` 读取宽高。ROM、PRC 和 PDB 路径应使用绝对路径。控制 socket 位于 `~/Library/Application Support/Palm OS Emulator/MCP/`，目录权限为 `0700`，socket 权限为 `0600`；退出 App 后 socket 会移除。MCP 服务只访问当前 Mac 的模拟器，不能连接远程或云端运行的 App。
