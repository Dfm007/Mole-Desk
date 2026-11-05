# Mole Desk

Mole 的 macOS 图形界面外壳。Mole 源码和运行文件已经内置在 `Vendor/Mole`，构建时会自动打包进 App。

- 开发者：Dfm007
- 版本：1.0.3
- GitHub：<https://github.com/Dfm007/Mole-Desk>

## 界面预览

### 系统概览

![系统概览](docs/images/system-overview.png)

### 深度清理

![深度清理](docs/images/deep-clean.png)

### 应用卸载

![应用卸载](docs/images/uninstall.png)

### 白名单

![白名单](docs/images/whitelist.png)

## 功能

- 系统概览：CPU、内存、磁盘、网络、电池、高占用进程
- 深度清理：扫描预览、确认后执行
- 应用卸载：扫描应用、按项目数量预览关联文件与个人数据、可选择一并移除、执行时显示项目进度；GUI 使用当前应用路径跳过重复的完整应用扫描
- 系统优化：预览后执行，需要时弹出 macOS 管理员授权
- 磁盘分析：选择目录并逐层查看占用
- 历史记录：读取 Mole 操作日志
- 白名单：管理清理白名单和优化白名单

## 目录

- `Sources/MoleDesk.swift`：应用入口与窗口配置
- `Sources/AppModel.swift`：统一应用状态与操作流程
- `Sources/AppModel+*.swift`：按清理、卸载、优化、分析、历史和分页拆分的操作逻辑
- `Sources/Models.swift`、`Services.swift`、`Parsing.swift`、`Utilities.swift`、`Theme.swift`：数据模型、进程服务、输出解析、工具函数和主题
- `Sources/Components.swift`、`RootView.swift`：通用组件、根视图和侧边栏
- `Sources/*View.swift`：系统概览、深度清理、应用卸载、系统优化、磁盘分析、历史记录、白名单和关于等独立分页
- `Vendor/Mole/`：内置的 Mole 源码与运行文件，GUI 功能基于 Mole 原生命令实现
- `Resources/`：图标、Info.plist、系统兼容 shim、管理员密码弹窗和快速卸载入口
- `build.sh`：构建 x86_64 + arm64 GUI，自动准备 Mole 通用运行时并打包进 App
- `Mole Desk.app`：构建产物

## 构建

进入项目根目录后执行：

```bash
./build.sh
```

构建脚本会自动识别当前项目目录，不依赖固定绝对路径。构建只读取 `Vendor/Mole`，不依赖外部 Mole 仓库。App 包内的 Mole 运行时位于：

`Mole Desk.app/Contents/Resources/Mole/`

打包后 `Mole Desk.app` 可以单独拷贝到其他 Intel Mac 或 Apple Silicon Mac 使用。运行时产生的配置、白名单和日志仍保存在当前用户的 `~/.config/mole` 与 `~/Library/Logs/mole`。

当前构建为 x86_64 + arm64 通用版本，最低系统为 macOS 15+，同一个 DMG 可运行在 Intel Mac 和 Apple Silicon Mac 上。构建脚本会分别编译两种架构并合并 GUI 可执行文件；内置的 `status-go` 与 `analyze-go` 也是 universal 二进制，不需要额外安装 Rosetta 或外部 Mole。系统没有安装 Go 时，首次构建会下载 `go.mod` 指定版本到 `build/toolchain/`，后续源码未变化时直接复用。

## 更新 Mole

将新的 Mole 源码同步到 `Vendor/Mole/`，检查差异后重新运行 `./build.sh`。脚本会检测 `cmd/`、`internal/`、`go.mod` 和 `go.sum` 的变化，并自动重建两种架构的 `status-go` 与 `analyze-go`，不需要手工维护二进制。不要直接修改 `Mole Desk.app/Contents/Resources/Mole/`，重新构建会覆盖它。
