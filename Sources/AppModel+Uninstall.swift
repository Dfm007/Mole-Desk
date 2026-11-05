import AppKit
import Foundation
import SwiftUI

extension AppModel {
    func loadApps(force: Bool = false) async {
        if !force && !apps.isEmpty { return }
        guard !appsLoading else { return }
        appsLoading = true
        let result = await Runner.run(MolePaths.entry, ["uninstall", "--list"], timeout: 120)
        if result.status == 0,
           let decoded = try? JSONDecoder.snakeCase.decode([AppEntry].self, from: Data(result.output.utf8)) {
            apps = decoded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } else {
            showToast("应用列表读取失败", color: Theme.red)
        }
        appsLoading = false
    }

    func selectApp(_ app: AppEntry?) {
        selectedApp = app
        uninstallRaw = ""
        uninstallPreviewBaseRaw = ""
        uninstallResult = ""
        uninstallPreviewSummary = nil
        uninstallRemovesPersonalData = false
        uninstallPreviewGeneration += 1
    }

    func previewUninstall(_ app: AppEntry) async {
        uninstallPreviewGeneration += 1
        let generation = uninstallPreviewGeneration
        selectedApp = app
        busyMessage = "正在分析 \(app.name) 的关联文件…"
        var arguments = ["--dry-run"]
        arguments.append(contentsOf: [app.path, app.name, app.bundleId])
        let result = await Runner.run(
            MolePaths.fastUninstall,
            arguments,
            extraEnvironment: [
                "MO_NO_OPLOG": "1",
                "MOLE_ROOT": MolePaths.root
            ],
            timeout: 600
        )
        guard generation == uninstallPreviewGeneration else { return }
        uninstallPreviewBaseRaw = stripTerminalOutput(result.output)
        applyUninstallPreviewPolicy()
        busyMessage = nil
        if uninstallRaw.isEmpty {
            showToast("未能生成卸载预览", color: Theme.red)
        }
    }

    func setUninstallRemovesPersonalData(_ remove: Bool, for app: AppEntry) {
        guard uninstallRemovesPersonalData != remove else { return }
        uninstallRemovesPersonalData = remove
        guard selectedApp?.id == app.id, !uninstallPreviewBaseRaw.isEmpty else { return }
        applyUninstallPreviewPolicy()
    }

    private func applyUninstallPreviewPolicy() {
        uninstallRaw = uninstallRemovesPersonalData
            ? uninstallPreviewWithPersonalData(uninstallPreviewBaseRaw)
            : uninstallPreviewBaseRaw
        uninstallPreviewSummary = parseUninstallPreviewSummary(uninstallRaw)
    }

    func requestUninstall(_ app: AppEntry) {
        guard !uninstallRaw.isEmpty else { return }
        let removesPersonalData = uninstallRemovesPersonalData
        let impact: String
        if let summary = uninstallPreviewSummary {
            impact = "将处理 \(summary.pendingItemCount) 项（应用 \(summary.appCount) 个、关联/系统文件 \(summary.relatedFileCount) 项、个人数据 \(summary.personalDataCount) 项），保留 \(summary.retainedCount) 项。"
        } else {
            impact = "Mole 会再次扫描关联文件。"
        }
        pendingConfirmation = PendingConfirmation(
            title: removesPersonalData ? "卸载 \(app.name) 并删除个人数据？" : "卸载 \(app.name)？",
            message: removesPersonalData
                ? "\(impact) 应用及个人数据将移入废纸篓；受系统保护或与其他应用共享的数据仍会保留。"
                : "\(impact) 应用会移入废纸篓，个人数据默认保留。",
            confirmTitle: removesPersonalData ? "卸载并删除" : "卸载应用",
            kind: .uninstall(app)
        )
    }

    func runUninstall(_ app: AppEntry) async {
        let removesPersonalData = uninstallRemovesPersonalData
        uninstallProgressTotal = max(1, uninstallPreviewSummary?.appCount ?? 1)
        uninstallProgressDone = 0
        uninstallProgressBuffer = ""
        busyProgress = 0
        busyProgressText = "0 / \(uninstallProgressTotal) 项"
        if let summary = uninstallPreviewSummary {
            busyMessage = "正在卸载 \(app.name)… 共 \(summary.pendingItemCount) 项"
        } else {
            busyMessage = "正在卸载 \(app.name)…"
        }
        let script = """
        set timeout 1200
        log_user 1
        set passwordAttempts 0
        set uninstallArgs [list]
        if {$env(REMOVE_PERSONAL_DATA) eq "1"} {
            lappend uninstallArgs "--with-data"
        }
        lappend uninstallArgs $env(APP_PATH) $env(APP_NAME) $env(BUNDLE_ID)
        spawn $env(MOLE_BIN) {*}$uninstallArgs
        expect {
            -re {确认|confirm} {
                # Mole drains pending input immediately before its confirmation
                # read, so send only after that drain window has passed.
                after 300
                send "\\r"
                exp_continue
            }
            -re {Password:|password:|密码[:：]} {
                incr passwordAttempts
                if {$passwordAttempts > 3} {
                    puts "\\n__SUDO_CANCELLED__\\n"
                    send "\\003"
                    exit 8
                }
                if {[catch {exec $env(MOLE_ASKPASS)} password]} {
                    puts "\\n__SUDO_CANCELLED__\\n"
                    send "\\003"
                    exit 8
                }
                if {$password eq ""} {
                    puts "\\n__SUDO_CANCELLED__\\n"
                    send "\\003"
                    exit 8
                }
                send "$password\\r"
                exp_continue
            }
            timeout {
                puts "\\n__MOLE_TIMEOUT__\\n"
                exit 124
            }
            eof {}
        }
        catch wait result
        exit [lindex $result 3]
        """
        let result = await Runner.run(
            URL(fileURLWithPath: "/usr/bin/expect"),
            ["-c", script],
            extraEnvironment: [
                "MOLE_BIN": MolePaths.fastUninstall.path,
                "MOLE_ROOT": MolePaths.root,
                "APP_PATH": app.path,
                "APP_NAME": app.name,
                "BUNDLE_ID": app.bundleId,
                "REMOVE_PERSONAL_DATA": removesPersonalData ? "1" : "0",
                "MOLE_ASKPASS": MolePaths.askpass.path,
                "TERM": "xterm-256color"
            ],
            timeout: 1260,
            onOutput: { [weak self] chunk in
                Task { @MainActor [weak self] in
                    self?.consumeUninstallOutput(chunk)
                }
            }
        )
        uninstallResult = stripTerminalOutput(result.output)
        consumeUninstallOutput("\n")
        if result.status == 0 {
            uninstallProgressDone = uninstallProgressTotal
            busyProgress = 1
            busyProgressText = "\(uninstallProgressTotal) / \(uninstallProgressTotal) 项"
            try? await Task.sleep(nanoseconds: 280_000_000)
        }
        busyMessage = nil
        busyProgress = nil
        busyProgressText = nil
        if result.status == 0 {
            showToast("\(app.name) 已卸载", color: Theme.accent)
            selectedApp = nil
            uninstallRaw = ""
            uninstallPreviewBaseRaw = ""
            uninstallPreviewSummary = nil
            uninstallRemovesPersonalData = false
            await loadApps(force: true)
        } else if uninstallResult.contains("__SUDO_CANCELLED__") {
            showToast("已取消管理员授权，卸载未执行", color: Theme.amber)
        } else {
            showToast("卸载未完成，请查看输出", color: Theme.amber)
        }
        await refreshStatus()
        await loadHistory()
    }

    private func consumeUninstallOutput(_ chunk: String) {
        uninstallProgressBuffer += chunk
        while let newline = uninstallProgressBuffer.firstIndex(of: "\n") {
            let line = String(uninstallProgressBuffer[..<newline])
            uninstallProgressBuffer.removeSubrange(...newline)
            handleUninstallProgressLine(line)
        }
    }

    private func handleUninstallProgressLine(_ raw: String) {
        let line = stripTerminalOutput(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let removedCount = firstMatch(in: line, pattern: #"已移除\s*([0-9]+)\s*个应用"#)
            ?? firstMatch(in: line, pattern: #"(?i)\bremoved\s+([0-9]+)\s+app"#)
        guard let removedCount, let count = Int(removedCount) else { return }
        uninstallProgressDone = min(uninstallProgressTotal, max(0, count))
        busyProgress = uninstallProgressTotal > 0 ? Double(uninstallProgressDone) / Double(uninstallProgressTotal) : nil
        busyProgressText = uninstallProgressTotal > 0 ? "\(uninstallProgressDone) / \(uninstallProgressTotal) 项" : nil
    }
}
