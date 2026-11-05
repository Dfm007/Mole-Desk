import AppKit
import Foundation
import SwiftUI

extension AppModel {
    func previewClean() async {
        busyMessage = "正在扫描可清理项目…"
        let result = await Runner.run(
            MolePaths.entry,
            ["clean", "--dry-run"],
            extraEnvironment: ["MO_NO_OPLOG": "1"],
            timeout: 300
        )
        let raw = stripTerminalOutput(result.output)
        cleanRaw = raw
        loadWhitelists()
        cleanPreview = parseCleanPreview(raw, whitelistPatterns: cleanWhitelist)
        busyMessage = nil
        if cleanPreview == nil {
            showToast("清理预览失败", color: Theme.red)
        }
    }

    func requestClean() {
        guard cleanPreview != nil else { return }
        pendingConfirmation = PendingConfirmation(
            title: "开始清理？",
            message: "Mole 将删除预览中列出的缓存、日志与残留文件。系统级项目可能弹出管理员授权。",
            confirmTitle: "开始清理",
            kind: .clean
        )
    }

    func runClean() async {
        let pendingItems = cleanPreview?.sections.flatMap(\.items).filter { !$0.isWhitelisted } ?? []
        cleanProgressTotal = pendingItems.count
        cleanProgressDone = 0
        cleanProgressLabels = Set(pendingItems.map { previewItemLabel($0.text) })
        cleanDoneLabels = []
        cleanProgressBuffer = ""
        busyMessage = "正在清理，请保持 Mole 运行…"
        busyProgress = cleanProgressTotal > 0 ? 0 : nil
        busyProgressText = cleanProgressTotal > 0 ? "0 / \(cleanProgressTotal) 项" : nil

        let result = await Runner.run(
            MolePaths.entry,
            ["clean"],
            timeout: 900,
            onOutput: { [weak self] chunk in
                Task { @MainActor [weak self] in
                    self?.consumeCleanOutput(chunk)
                }
            }
        )
        cleanResult = stripTerminalOutput(result.output)

        if cleanProgressTotal > 0 {
            busyProgress = 1
            busyProgressText = "\(cleanProgressTotal) / \(cleanProgressTotal) 项"
            try? await Task.sleep(nanoseconds: 280_000_000)
        }
        busyMessage = nil
        busyProgress = nil
        busyProgressText = nil
        if result.status == 0 {
            showToast("清理完成", color: Theme.accent)
        } else {
            showToast("清理未完全完成，请查看输出", color: Theme.amber)
        }
        await refreshStatus()
        await loadHistory()
    }

    private func consumeCleanOutput(_ chunk: String) {
        cleanProgressBuffer += chunk
        while let newline = cleanProgressBuffer.firstIndex(of: "\n") {
            let line = String(cleanProgressBuffer[..<newline])
            cleanProgressBuffer.removeSubrange(...newline)
            handleCleanProgressLine(line)
        }
    }

    private func handleCleanProgressLine(_ raw: String) {
        let line = stripTerminalOutput(raw).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        let glyphs = ["✓", "○", "◎", "⊙", "•"]
        guard glyphs.contains(where: { line.hasPrefix($0) }) else { return }
        var itemText = line
        for glyph in glyphs where itemText.hasPrefix(glyph) {
            itemText.removeFirst(glyph.count)
            break
        }
        itemText = itemText.trimmingCharacters(in: .whitespaces)
        let label = previewItemLabel(itemText)
        guard cleanProgressLabels.contains(label), !cleanDoneLabels.contains(label) else { return }
        cleanDoneLabels.insert(label)
        cleanProgressDone = min(cleanProgressTotal, cleanProgressDone + 1)
        busyProgress = cleanProgressTotal > 0 ? Double(cleanProgressDone) / Double(cleanProgressTotal) : nil
        busyProgressText = cleanProgressTotal > 0 ? "\(cleanProgressDone) / \(cleanProgressTotal) 项" : nil
    }
}
