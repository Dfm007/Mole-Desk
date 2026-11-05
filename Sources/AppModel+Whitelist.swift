import AppKit
import Foundation
import SwiftUI

extension AppModel {
    func loadWhitelists() {
        cleanWhitelist = readWhitelist(.clean)
        optimizeWhitelist = readWhitelist(.optimize)
        whitelistError = nil
    }

    private func readWhitelist(_ mode: WhitelistMode) -> [String] {
        guard let content = try? String(contentsOf: mode.fileURL, encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func whitelist(for mode: WhitelistMode) -> [String] {
        mode == .clean ? cleanWhitelist : optimizeWhitelist
    }

    func addWhitelistPattern(_ raw: String, mode: WhitelistMode) -> Bool {
        let value = normalizeWhitelistPattern(raw)
        guard !value.isEmpty, !value.hasPrefix("#"), !value.contains("\n") else {
            showToast("请输入有效路径或通配符", color: Theme.amber)
            return false
        }
        var patterns = whitelist(for: mode)
        guard !patterns.contains(value) else {
            showToast("该规则已存在", color: Theme.amber)
            return false
        }
        patterns.append(value)
        return saveWhitelist(patterns, mode: mode)
    }

    func removeWhitelistPattern(_ pattern: String, mode: WhitelistMode) {
        let patterns = whitelist(for: mode).filter { $0 != pattern }
        _ = saveWhitelist(patterns, mode: mode)
    }

    func chooseWhitelistPath(mode: WhitelistMode) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加到白名单"
        panel.message = "选择不想被 Mole 清理的文件或文件夹"
        if panel.runModal() == .OK {
            var added = 0
            for url in panel.urls {
                if addWhitelistPattern(url.path, mode: mode, silent: true) { added += 1 }
            }
            if added > 0 {
                showToast("已添加 \(added) 条白名单", color: Theme.accent)
            }
        }
    }

    @discardableResult
    private func addWhitelistPattern(_ raw: String, mode: WhitelistMode, silent: Bool) -> Bool {
        let value = normalizeWhitelistPattern(raw)
        guard !value.isEmpty, !value.hasPrefix("#"), !value.contains("\n") else { return false }
        var patterns = whitelist(for: mode)
        guard !patterns.contains(value) else { return false }
        patterns.append(value)
        return saveWhitelist(patterns, mode: mode, silent: silent)
    }

    @discardableResult
    private func saveWhitelist(_ patterns: [String], mode: WhitelistMode, silent: Bool = false) -> Bool {
        do {
            let directory = mode.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var content = mode.header + "\n"
            if !patterns.isEmpty {
                content += "\n" + patterns.joined(separator: "\n") + "\n"
            }
            try content.write(to: mode.fileURL, atomically: true, encoding: .utf8)
            loadWhitelists()
            if !silent { showToast("白名单已保存", color: Theme.accent) }
            return true
        } catch {
            whitelistError = error.localizedDescription
            showToast("保存白名单失败", color: Theme.red)
            return false
        }
    }

    private func normalizeWhitelistPattern(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("file://"), let url = URL(string: value) {
            value = url.path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if value == home { return "~" }
        if value.hasPrefix(home + "/") {
            value = "~" + value.dropFirst(home.count)
        }
        return value
    }

    func openWhitelistFile(_ mode: WhitelistMode) {
        if !FileManager.default.fileExists(atPath: mode.fileURL.path) {
            _ = saveWhitelist([], mode: mode, silent: true)
        }
        NSWorkspace.shared.open(mode.fileURL)
    }
}
