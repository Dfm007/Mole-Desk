#!/bin/bash

show_clean_help() {
    echo "$(mole_t 'Usage: mo clean [OPTIONS]' '用法：mo clean [选项]')"
    echo ""
    echo "$(mole_t 'Clean up disk space by removing caches, logs, temporary files, and app leftovers from already-uninstalled apps.' '清理缓存、日志、临时文件和已卸载应用的残留，释放磁盘空间。')"
    echo ""
    echo "$(mole_t 'Options:' '选项：')"
    echo "  --dry-run, -n     $(mole_t 'Preview cleanup without making changes' '只预览清理，不修改任何文件')"
    echo "  --external PATH   $(mole_t 'Clean OS metadata from a mounted external volume' '清理已挂载外置卷中的系统元数据')"
    echo "  --whitelist       $(mole_t 'Manage protected paths' '管理受保护的路径')"
    echo "  --debug           $(mole_t 'Show detailed operation logs' '显示详细操作日志')"
    echo "  -h, --help        $(mole_t 'Show this help message' '显示帮助信息')"
}

show_installer_help() {
    echo "$(mole_t 'Usage: mo installer [OPTIONS]' '用法：mo installer [选项]')"
    echo ""
    echo "$(mole_t 'Find and remove installer files (.dmg, .pkg, .iso, .xip, .zip).' '查找并删除安装包文件（.dmg、.pkg、.iso、.xip、.zip）。')"
    echo ""
    echo "$(mole_t 'Options:' '选项：')"
    echo "  --dry-run         $(mole_t 'Preview installer cleanup without making changes' '只预览安装包清理，不修改任何文件')"
    echo "  --debug           $(mole_t 'Show detailed operation logs' '显示详细操作日志')"
    echo "  -h, --help        $(mole_t 'Show this help message' '显示帮助信息')"
}

show_optimize_help() {
    echo "$(mole_t 'Usage: mo optimize [OPTIONS]' '用法：mo optimize [选项]')"
    echo ""
    echo "$(mole_t 'Refresh system caches and services, repair safe maintenance issues.' '刷新系统缓存与服务，修复可安全处理的维护问题。')"
    echo ""
    echo "$(mole_t 'Options:' '选项：')"
    echo "  --dry-run, -n     $(mole_t 'Preview optimization without making changes' '只预览优化，不修改任何文件')"
    echo "  --whitelist       $(mole_t 'Manage protected items' '管理受保护项目')"
    echo "  --debug           $(mole_t 'Show detailed operation logs' '显示详细操作日志')"
    echo "  -h, --help        $(mole_t 'Show this help message' '显示帮助信息')"
}

show_touchid_help() {
    echo "$(mole_t 'Usage: mo touchid [COMMAND]' '用法：mo touchid [命令]')"
    echo ""
    echo "$(mole_t 'Configure Touch ID for sudo authentication.' '配置 sudo 的 Touch ID 验证。')"
    echo ""
    echo "$(mole_t 'Commands:' '命令：')"
    echo "  enable            $(mole_t 'Enable Touch ID for sudo' '启用 sudo 的 Touch ID')"
    echo "  disable           $(mole_t 'Disable Touch ID for sudo' '关闭 sudo 的 Touch ID')"
    echo "  status            $(mole_t 'Show current Touch ID status' '查看当前 Touch ID 状态')"
    echo ""
    echo "$(mole_t 'Options:' '选项：')"
    echo "  --dry-run         $(mole_t 'Preview Touch ID changes without modifying sudo config' '预览 Touch ID 变更，不修改 sudo 配置')"
    echo "  -h, --help        $(mole_t 'Show this help message' '显示帮助信息')"
    echo ""
    echo "$(mole_t 'If no command is provided, an interactive menu is shown.' '不提供命令时显示交互式菜单。')"
}

show_uninstall_help() {
    echo "$(mole_t 'Usage: mo uninstall [OPTIONS] [APP_NAME ...]' '用法：mo uninstall [选项] [应用名称 ...]')"
    echo ""
    echo "$(mole_t 'Interactively remove applications and their leftover files.' '交互式卸载应用及其残留文件。')"
    echo "$(mole_t 'Optionally specify one or more app names to uninstall directly.' '也可以直接指定一个或多个应用名称进行卸载。')"
    echo "$(mole_t 'For leftovers from apps that are already gone, use mo clean.' '如果应用已经手动删除，请使用 mo clean 清理残留。')"
    echo ""
    echo "$(mole_t 'Examples:' '示例：')"
    echo "  mo uninstall                   $(mole_t 'Open interactive app selector' '打开交互式应用选择器')"
    echo "  mo uninstall slack             $(mole_t 'Uninstall Slack' '卸载 Slack')"
    echo "  mo uninstall slack zoom        $(mole_t 'Uninstall Slack and Zoom' '卸载 Slack 和 Zoom')"
    echo "  mo uninstall --dry-run slack   $(mole_t 'Preview Slack uninstallation' '预览 Slack 卸载')"
    echo "  mo uninstall --with-data slack $(mole_t 'Uninstall Slack with its data selected' '卸载 Slack 并预选个人数据')"
    echo "  mo uninstall --list            $(mole_t 'Show installed apps and the names mo uninstall accepts' '列出已安装应用及可用的卸载名称')"
    echo ""
    echo "$(mole_t 'Options:' '选项：')"
    echo "  --list            $(mole_t 'List installed apps with the exact name mo uninstall accepts' '列出已安装应用及可用的卸载名称')"
    echo "  --dry-run         $(mole_t 'Preview app uninstallation without making changes' '只预览应用卸载，不修改任何文件')"
    echo "  --permanent       $(mole_t 'Bypass macOS Trash and rm -rf immediately' '跳过废纸篓并立即永久删除')"
    echo "  --with-data       $(mole_t 'Start with personal data selected; press D to keep any' '预选个人数据；按 D 可保留任意路径')"
    echo "  --whitelist       $(mole_t 'Not supported for uninstall (use clean/optimize)' '卸载命令不支持（请使用 clean/optimize）')"
    echo "  --debug           $(mole_t 'Show detailed operation logs' '显示详细操作日志')"
    echo "  -h, --help        $(mole_t 'Show this help message' '显示帮助信息')"
    echo ""
    echo "$(mole_t 'By default, uninstalled files go to the macOS Trash so they can be' '默认情况下，卸载的文件会进入 macOS 废纸篓，可随时恢复。')"
    echo "$(mole_t 'recovered. Use --permanent to skip the Trash step.' '使用 --permanent 可跳过废纸篓。')"
}
