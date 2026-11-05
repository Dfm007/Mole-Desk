import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

func formatBytes(_ value: UInt64?, countStyle: ByteCountFormatter.CountStyle = .file) -> String {
    guard let value else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: countStyle)
}

func formatBytes(_ value: Int64?) -> String {
    guard let value else { return "—" }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func formatPercent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.1f%%", value)
}

func stripTerminalOutput(_ raw: String) -> String {
    var text = raw
    text = text.replacingOccurrences(
        of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
        with: "",
        options: .regularExpression
    )
    text = text.replacingOccurrences(of: "\r\n", with: "\n")
    text = text.replacingOccurrences(of: "\r", with: "\n")
    text = text.replacingOccurrences(of: "\u{0000}", with: "")
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func commandTitle(_ raw: String) -> String {
    switch raw {
    case "clean": return "深度清理"
    case "clean-dry-run": return "清理预览"
    case "optimize": return "系统优化"
    case "optimize-dry-run": return "优化预览"
    case "uninstall": return "应用卸载"
    case "uninstall-dry-run": return "卸载预览"
    case "purge": return "项目清理"
    case "installer": return "安装包清理"
    default: return raw
    }
}
