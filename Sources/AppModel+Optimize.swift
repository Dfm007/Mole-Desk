import AppKit
import Foundation
import SwiftUI

extension AppModel {
    func previewOptimize() async {
        busyMessage = "正在检查可优化项目…"
        let result = await Runner.run(
            MolePaths.entry,
            ["optimize", "--dry-run"],
            extraEnvironment: [
                "MO_NO_OPLOG": "1",
                "MOLE_GUI_MARKERS": "1"
            ],
            timeout: 300
        )
        let raw = stripTerminalOutput(result.output)
        optimizeSections = parseOptimizePreviewSections(raw)
        optimizeRaw = removeOptimizeMarkers(raw)
        busyMessage = nil
        if optimizeRaw.isEmpty {
            showToast("优化预览失败", color: Theme.red)
        }
    }

    func requestOptimize() {
        guard !optimizeRaw.isEmpty else { return }
        pendingConfirmation = PendingConfirmation(
            title: "开始系统优化？",
            message: "Mole 将刷新缓存、数据库与系统服务。部分任务需要管理员权限，会出现 macOS 授权窗口。",
            confirmTitle: "开始优化",
            kind: .optimize
        )
    }

    func runOptimize() async {
        busyMessage = "正在执行系统优化…"
        let result = await Runner.run(MolePaths.entry, ["optimize"], timeout: 900)
        optimizeResult = stripTerminalOutput(result.output)
        busyMessage = nil
        if result.status == 0 {
            showToast("系统优化完成", color: Theme.accent)
        } else {
            showToast("优化未完全完成，请查看输出", color: Theme.amber)
        }
        await refreshStatus()
        await loadHistory()
    }
}
