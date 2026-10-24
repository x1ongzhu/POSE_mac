# macOS 原生界面

此目录提供原生 SwiftUI 应用，并将 CloudpilotEmu 的 C++ 核心作为动态库载入主进程。核心采用无窗口软件渲染，Palm 画面显示在主窗口的 NSView 中；鼠标与键盘输入由该视图送入模拟器。

## Xcode 项目

用 Xcode 打开 `MacApp/PalmOS.xcodeproj`，选择 `CloudpilotMac` scheme 与 “My Mac”，即可构建和运行完整 App。构建阶段会编译 C++ 核心、嵌入动态库与随附的 ROM、浏览器，并编译 `Resources/PalmOS.icon` 的 Icon Composer 分层图标。首次构建前需安装含 macOS 27 SDK 的 Xcode 和以下依赖：

```sh
brew install sdl2 sdl2_image readline curl
```

从仓库克隆后，还需将 Palm m515 ROM 放到 `ROMs/Palm-m515-4.1-en.rom`，将 EudoraWeb 与 SSLPlus 放到 `PalmApps/EudoraWeb_2.1.prc` 和 `PalmApps/sslplus_1.0.7i.prc`。来源及校验值见 `ROMs/SOURCE.md`、`PalmApps/SOURCE.md`。这些第三方文件和本机生成的 `dist/` 不提交到 Git；本机打包好的 App 仍可直接运行。

图标的可编辑文稿是 `MacApp/Resources/PalmOS.icon`，Xcode 会直接编译该文稿。`tools/generate-app-icon.swift` 是早期图标生成脚本；运行它会覆盖当前在 Icon Composer 中编辑的文稿，请先备份。

## 制作开箱即用的 App

在构建机上安装含 macOS 27 SDK 的 Xcode、Homebrew 和 Cloudpilot 核心依赖后，在仓库根目录运行：

```sh
brew install sdl2 sdl2_image readline curl
./tools/package-macos.sh
```

成品位于 `dist/Palm OS.app`。打包脚本直接复制 Xcode 项目的 Release 构建产物，确保分发版与 Xcode 中运行的 App 使用同一套 macOS 27 SDK 构建设置和原生工具栏外观。构建过程嵌入模拟器核心、所需动态库与 Palm m515 ROM。启动后可直接运行，也可导入其他 ROM；应用按原项目的 ROM 兼容规则自动识别对应设备，设备不可手动更改。模拟器会每分钟及停止时将会话保存至用户的 Application Support 目录。

## 从命令行启动

可直接执行 App 内的程序，指定 ROM 并安装一个或多个 Palm 应用/数据库：

```sh
"dist/Palm OS.app/Contents/MacOS/CloudpilotMac" --rom "ROMs/Palm-m515-4.1-en.rom" --install "PalmApps/EudoraWeb_2.1.prc"
"dist/Palm OS.app/Contents/MacOS/CloudpilotMac" --install "/path/to/app.prc" --install "/path/to/data.pdb"
```

`--rom` 自动识别设备并在窗口打开后立即启动虚拟机；未提供时使用内置 ROM。`--install` 可重复，`--app` 是同义参数。Palm OS 初始化完成后会安装所有文件，并自动打开最后指定且安装成功的 PRC 应用；PDB 仅安装数据。结果会显示在窗口状态栏及标准错误输出中。路径支持绝对路径、`~` 和相对当前目录的路径。使用 `open` 时建议传绝对路径，并加 `-n` 确保启动新进程以接收参数：

```sh
open -n "dist/Palm OS.app" --args --rom "/absolute/path/to/Palm.rom" --install "/absolute/path/to/app.prc"
```

执行程序加 `--help` 可查看全部参数。再次指定同一 ROM 时会继续使用该 ROM 先前保存的会话。

应用使用 CloudpilotEmu 的原生网络后端，将 Palm OS 的网络请求直接转接至 macOS 的网络栈，不需要额外运行代理服务。网络默认开启，可在工具栏“更多操作”中切换。首次使用内置 Palm m515 ROM 建立会话时，应用会在 Palm 系统就绪后安装随包附带的 EudoraWeb 2.1 浏览器及 SSLPlus；已有会话可用“安装 PRC/PDB”手动安装。老浏览器对现代 HTTPS、网页脚本和复杂页面的兼容性有限，建议先用普通 HTTP 页面验证连接。浏览器来源见 `PalmApps/SOURCE.md`。EudoraWeb 首次启动可能要求用户阅读并接受其许可协议。

运行中可从工具栏的“更多操作”或“模拟器”菜单触发 HotSync、软重置和保存 PNG 截图。HotSync 会按下模拟设备的底座按钮；与 Palm Desktop 传输数据仍需配置对应的桌面同步服务。

工具栏的安装按钮可将 PRC/PDB 文件装入当前设备。资源库可导入、打开、复制、导出或删除会话；存储卡可导入镜像、创建空白卡、挂载、弹出、导出或删除。存储卡在弹出和停止模拟器时写回应用的存储目录。

也可从 Finder 将 ROM 或多个 PRC/PDB 直接拖到主窗口。ROM 会自动识别设备并启动；PRC/PDB 安装到当前设备，若设备未启动则先启动，待 Palm OS 初始化完成后安装。同一次拖放可以包含一个 ROM 和多个 PRC/PDB。

按 ⌘N 可新建模拟器窗口。每个窗口由独立的 App 进程运行，可同时模拟不同设备；新窗口为内置 ROM 创建独立会话。若尝试在两个窗口中打开同一会话镜像，后打开的窗口会提示该会话已在运行，防止并发写入。

## 单独运行 SwiftUI 开发版

```sh
cd MacApp
swift run
```

开发版需要核心构建在 `src/cloudpilot/libcloudpilot-embed.dylib`；发布请用上面的打包脚本生成完整 App。

## 来源和许可

模拟器核心来自 [CloudpilotEmu](https://github.com/cloudpilot-emu/cloudpilot-emu)，上游项目采用 GPL-3.0。基于该核心分发的组合版本需遵循其许可证要求。本目录 SwiftUI 前端为本移植新增代码；发布时请一并提供对应源码和许可文本。
