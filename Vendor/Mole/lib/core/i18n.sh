#!/bin/bash
# Mole - user-facing localization helpers.
#
# Commands inherit MOLE_LANG from the main launcher. The maintained upstream
# default stays English when a script is run directly; the `mo` launcher and
# interactive menu select Simplified Chinese unless MOLE_LANG=en is set.

set -euo pipefail

if [[ -n "${MOLE_I18N_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_I18N_LOADED=1

mole_language() {
    case "${MOLE_LANG:-en}" in
        en* | EN*) printf 'en' ;;
        *) printf 'zh_CN' ;;
    esac
}

mole_is_zh() {
    [[ "$(mole_language)" == "zh_CN" ]]
}

# mole_t <English> <Chinese>
mole_t() {
    if mole_is_zh; then
        printf '%s' "${2:-$1}"
    else
        printf '%s' "${1:-}"
    fi
}

# Translate a count noun while preserving the numeric value.
mole_count_text() {
    local count="$1" noun="$2"
    if ! mole_is_zh; then
        if [[ "$count" == "1" ]]; then
            printf '%s %s' "$count" "$noun"
        else
            printf '%s %ss' "$count" "$noun"
        fi
        return 0
    fi

    case "$noun" in
        item | items) printf '%s 项' "$count" ;;
        app | apps) printf '%s 个应用' "$count" ;;
        application | applications) printf '%s 个应用' "$count" ;;
        category | categories) printf '%s 类' "$count" ;;
        file | files) printf '%s 个文件' "$count" ;;
        snapshot | snapshots) printf '%s 个快照' "$count" ;;
        optimization | optimizations) printf '%s 项优化' "$count" ;;
        cycle | cycles) printf '%s 次循环' "$count" ;;
        *) printf '%s %s' "$count" "$noun" ;;
    esac
}

mole_command_description() {
    local description="$1"
    if ! mole_is_zh; then
        printf '%s' "$description"
        return 0
    fi
    case "$description" in
        "Free up disk space") printf '释放磁盘空间' ;;
        "Remove apps completely") printf '彻底移除应用及残留' ;;
        "Refresh caches and services") printf '刷新缓存与服务' ;;
        "Explore disk usage") printf '分析磁盘空间占用' ;;
        "Monitor system health") printf '监控系统运行状态' ;;
        "Review cleanup activity") printf '查看清理记录' ;;
        "Remove old project artifacts") printf '清理旧项目构建产物' ;;
        "Find and remove installer files") printf '查找并删除安装包' ;;
        "Remove Intel code from universal apps") printf '移除通用应用中的 Intel 代码' ;;
        "Configure Touch ID for sudo") printf '配置 sudo 的 Touch ID' ;;
        "Setup shell tab completion") printf '配置 Shell 自动补全' ;;
        "Update to latest version") printf '更新到最新版本' ;;
        "Remove Mole from system") printf '从系统中卸载 Mole' ;;
        "Show help") printf '显示帮助' ;;
        "Show version") printf '显示版本' ;;
        *) printf '%s' "$description" ;;
    esac
}

mole_help_option_text() {
    local description="$1"
    if ! mole_is_zh; then
        printf '%s' "$description"
        return 0
    fi
    case "$description" in
        "Preview cleanup") printf '预览清理' ;;
        "Manage protected caches") printf '管理受保护的缓存' ;;
        "Preview optimization") printf '预览优化' ;;
        "Manage protected items") printf '管理受保护项目' ;;
        "Preview app uninstall") printf '预览应用卸载' ;;
        "Export cleanup history") printf '导出清理记录' ;;
        "Preview project purge") printf '预览项目产物清理' ;;
        "Preview installer cleanup") printf '预览安装包清理' ;;
        "Preview Intel code removal") printf '预览 Intel 代码移除' ;;
        "Preview Touch ID setup") printf '预览 Touch ID 配置' ;;
        "Preview shell completion edits") printf '预览 Shell 补全修改' ;;
        "Configure scan directories") printf '配置扫描目录' ;;
        "Analyze external drives only") printf '仅分析外置磁盘' ;;
        "Force reinstall latest stable version") printf '强制重新安装最新稳定版' ;;
        "Preview Mole removal") printf '预览 Mole 卸载' ;;
        "Install latest unreleased main branch build") printf '安装 main 分支最新开发版' ;;
        *) printf '%s' "$description" ;;
    esac
}

mole_section_text() {
    local section="$1"
    if ! mole_is_zh; then
        printf '%s' "$section"
        return 0
    fi
    case "$section" in
        "External volume") printf '外置磁盘' ;;
        "System") printf '系统' ;;
        "User essentials") printf '用户基础文件' ;;
        "App caches") printf '应用缓存' ;;
        "Browsers") printf '浏览器' ;;
        "Cloud & Office") printf '云盘与 Office' ;;
        "Developer tools") printf '开发工具' ;;
        "Apps & utilities") printf '应用与工具' ;;
        "Virtualization") printf '虚拟机' ;;
        "Application Support") printf '应用支持文件' ;;
        "App leftovers") printf '应用残留' ;;
        "Device backups & firmware") printf '设备备份与固件' ;;
        "Time Machine") printf '时间机器' ;;
        "Large files") printf '大文件' ;;
        "Project artifacts") printf '项目构建产物' ;;
        *) printf '%s' "$section" ;;
    esac
}

mole_optimize_task_text() {
    local task="$1"
    if ! mole_is_zh; then
        printf '%s' "$task"
        return 0
    fi
    case "$task" in
        "Finder Cache Refresh") printf 'Finder 缓存刷新' ;;
        "App State Cleanup") printf '应用状态清理' ;;
        "Broken Config Repair") printf '损坏配置修复' ;;
        "Network Cache Refresh") printf '网络缓存刷新' ;;
        "Database Optimization") printf '数据库优化' ;;
        "Prevent Finder .DS_Store") printf '阻止 Finder 写入 .DS_Store' ;;
        "Legacy Overrides") printf '旧版覆盖项' ;;
        "Network Stack Refresh") printf '网络栈刷新' ;;
        "Permission Repair") printf '权限修复' ;;
        "Spotlight Optimization") printf 'Spotlight 优化' ;;
        "Spotlight Orphan Rules") printf 'Spotlight 孤立规则' ;;
        "Periodic Maintenance") printf '定期维护' ;;
        "Shared File Lists") printf '共享文件列表' ;;
        "Disk Health") printf '磁盘健康' ;;
        "Login Items" | "Login Items Audit") printf '登录项检查' ;;
        "Quarantine Database Cleanup") printf '隔离区数据库清理' ;;
        "Launch Agents Cleanup") printf '启动代理清理' ;;
        "Notifications") printf '通知清理' ;;
        "Usage Data") printf '使用数据清理' ;;
        *) printf '%s' "$task" ;;
    esac
}

mole_optimize_message_text() {
    local message="$1"
    if ! mole_is_zh; then
        printf '%s' "$message"
        return 0
    fi
    case "$message" in
        "QuickLook thumbnails refreshed") printf 'QuickLook 缩略图已刷新' ;;
        "Icon services cache rebuilt") printf '图标服务缓存已重建' ;;
        "App saved states optimized") printf '应用保存状态已优化' ;;
        "Removed "*" old saved state(s)") printf '%s' "${message/Removed /已移除 }" | sed 's/ old saved state(s)/ 个旧应用状态/' ;;
        "Repaired "*" corrupted preference files") printf '%s' "${message/Repaired /已修复 }" | sed 's/ corrupted preference files/ 个损坏的偏好设置文件/' ;;
        "All preference files valid") printf '所有偏好设置文件均正常' ;;
        "Network cache refresh skipped (admin access required)") printf '已跳过网络缓存刷新（需要管理员权限）' ;;
        "DNS cache refreshed") printf 'DNS 缓存已刷新' ;;
        "DNS cache refresh skipped, active VPN detected") printf '已跳过 DNS 缓存刷新：检测到 VPN 正在运行' ;;
        "DNS cache refresh skipped, macOS does not allow signaling mDNSResponder") printf '已跳过 DNS 缓存刷新：当前 macOS 不允许向 mDNSResponder 发送信号' ;;
        "Quarantine database already clean") printf '隔离区数据库已经干净' ;;
        "Quarantine history cleared ("*" entries)") printf '%s' "${message/Quarantine history cleared (/隔离区历史已清除（}" | sed 's/ entries)/ 条记录）/' ;;
        "Optimized "*" databases for Mail, Safari, Messages") printf '%s' "${message/Optimized /已优化 }" | sed 's/ databases for Mail, Safari, Messages/ 个数据库（邮件、Safari、信息）/' ;;
        "No databases compacted") printf '没有需要压缩的数据库' ;;
        "All databases already optimized") printf '所有数据库均已优化' ;;
        "No databases found to optimize") printf '没有找到可优化的数据库' ;;
        "Already optimal for "*" databases") printf '%s' "${message/Already optimal for /已有 }" | sed 's/ databases/ 个数据库保持最佳状态/' ;;
        "Skipped "*" databases over the 100 MB safety limit") printf '%s' "${message/Skipped /已跳过 }" | sed 's/ databases over the 100 MB safety limit/ 个超过 100 MB 安全上限的数据库/' ;;
        "Network stack refresh skipped, active VPN detected") printf '已跳过网络栈刷新：检测到 VPN 正在运行' ;;
        "Network stack already optimal") printf '网络栈已处于最佳状态' ;;
        "Network routing table refreshed") printf '网络路由表已刷新' ;;
        "ARP cache cleared") printf 'ARP 缓存已清除' ;;
        "User directory permissions already optimal") printf '用户目录权限已处于最佳状态' ;;
        "User directory permissions repaired") printf '用户目录权限已修复' ;;
        "File access issues resolved") printf '文件访问问题已解决' ;;
        "Spotlight index already optimal") printf 'Spotlight 索引已处于最佳状态' ;;
        "Spotlight index rebuild started") printf 'Spotlight 索引重建已启动' ;;
        "Spotlight index verified") printf 'Spotlight 索引已验证' ;;
        "Spotlight search rules already clean") printf 'Spotlight 搜索规则已经干净' ;;
        "Would remove "*" orphan Spotlight rule(s)") printf '%s' "${message/Would remove /将移除 }" | sed 's/ orphan Spotlight rule(s)/ 条孤立 Spotlight 规则/' ;;
        "Removed "*" orphan Spotlight rule(s)") printf '%s' "${message/Removed /已移除 }" | sed 's/ orphan Spotlight rule(s)/ 条孤立 Spotlight 规则/' ;;
        ".DS_Store prevention already enabled on network & USB volumes") printf '网络卷和 USB 卷已启用 .DS_Store 防护' ;;
        ".DS_Store prevention enabled on network & USB volumes") printf '已启用网络卷和 USB 卷的 .DS_Store 防护' ;;
        "No legacy App Nap or disk-image overrides found") printf '未发现旧版 App Nap 或磁盘映像覆盖项' ;;
        "Skipped (whitelisted): "*) printf '已跳过（白名单）：%s' "${message#Skipped (whitelisted): }" ;;
        "Removed override: "*) printf '已移除覆盖项：%s' "${message#Removed override: }" ;;
        "Launch Agents all healthy") printf '所有启动代理均正常' ;;
        "Periodic maintenance skipped (not available on this macOS version)") printf '已跳过定期维护（当前 macOS 版本不支持）' ;;
        "Periodic maintenance already current ("*"d ago)") printf '%s' "${message/Periodic maintenance already current (/定期维护已是最新（}" | sed 's/d ago)/ 天前）/' ;;
        "Periodic maintenance skipped (requires sudo)") printf '已跳过定期维护（需要管理员权限）' ;;
        "Periodic maintenance triggered") printf '定期维护已触发' ;;
        "Shared file lists directory not found") printf '未找到共享文件列表目录' ;;
        "Repaired "*" corrupted shared file list(s)") printf '%s' "${message/Repaired /已修复 }" | sed 's/ corrupted shared file list(s)/ 个损坏的共享文件列表/' ;;
        "Shared file lists all healthy") printf '共享文件列表全部正常' ;;
        "Notification Center database is healthy ("*) printf '%s' "${message/Notification Center database is healthy (/通知中心数据库正常（}" | sed 's/)$/）/' ;;
        "Notification Center database cleaned (was "*) printf '%s' "${message/Notification Center database cleaned (was /通知中心数据库已清理（原大小 }" | sed 's/)$/）/' ;;
        "Knowledge database not found") printf '未找到使用数据数据库' ;;
        "Knowledge database is healthy ("*) printf '%s' "${message/Knowledge database is healthy (/使用数据数据库正常（}" | sed 's/)$/）/' ;;
        "Knowledge database cleaned (was "*) printf '%s' "${message/Knowledge database cleaned (was /使用数据数据库已清理（原大小 }" | sed 's/)$/）/' ;;
        "Disk verify skipped") printf '已跳过磁盘校验' ;;
        "Disk verify · skipped in dry-run") printf '磁盘校验 · 预览模式下跳过' ;;
        "Disk filesystem verified OK") printf '磁盘文件系统校验通过' ;;
        "Login items audit · skipped in test mode") printf '登录项检查 · 测试模式下跳过' ;;
        "No login items found") printf '未找到登录项' ;;
        "Login items all healthy ("*" checked)") printf '%s' "${message/Login items all healthy (/登录项全部正常（已检查 }" | sed 's/ checked)/ 项）/' ;;
        *) printf '%s' "$message" ;;
    esac
}

mole_uninstall_scan_text() {
    local message="$1"
    if ! mole_is_zh; then
        printf '%s' "$message"
        return 0
    fi
    case "$message" in
        "Scanning applications...") printf '正在扫描应用...' ;;
        "Merging cache data...") printf '正在合并缓存数据...' ;;
        "Collecting metadata...") printf '正在收集元数据...' ;;
        "Updating cache...") printf '正在更新缓存...' ;;
        "Sorting application list...") printf '正在排序应用列表...' ;;
        "Finalizing list...") printf '正在完成列表...' ;;
        "Preparing app list...") printf '正在准备应用列表...' ;;
        "Building uninstall index...") printf '正在建立卸载索引...' ;;
        *) printf '%s' "$message" ;;
    esac
}
