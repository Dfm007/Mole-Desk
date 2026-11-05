import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

func parseOptimizePreviewSections(_ raw: String) -> [OptimizePreviewSection] {
    struct MutableSection {
        let title: String
        var lines: [String]
        var isApplied: Bool
    }

    var sections: [MutableSection] = []
    var currentIndex: Int?

    for rawLine in raw.components(separatedBy: .newlines) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\u{001E}MOLE_OPTIMIZE_APPLIED:"), let index = currentIndex {
            sections[index].isApplied = true
            continue
        }
        if trimmed.isEmpty { continue }
        if trimmed.hasPrefix("➤") {
            let title = trimmed.replacingOccurrences(of: "➤", with: "").trimmingCharacters(in: .whitespaces)
            sections.append(MutableSection(title: title, lines: [], isApplied: false))
            currentIndex = sections.count - 1
            continue
        }
        if currentIndex == nil {
            sections.append(MutableSection(title: "系统状态", lines: [], isApplied: false))
            currentIndex = 0
        }
        if let index = currentIndex {
            sections[index].lines.append(trimmed)
        }
    }

    return sections.map { OptimizePreviewSection(title: $0.title, lines: $0.lines, isApplied: $0.isApplied) }
}

func removeOptimizeMarkers(_ raw: String) -> String {
    raw.components(separatedBy: .newlines)
        .filter { !$0.contains("MOLE_OPTIMIZE_APPLIED:") }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

enum UninstallPreviewParseSection {
    case files
    case personalDataToRemove
    case personalDataKept
}

func uninstallPreviewWithPersonalData(_ raw: String) -> String {
    guard !raw.isEmpty else { return raw }
    var lines = raw.components(separatedBy: .newlines)
    var inRetainedSection = false
    var changed = false

    for index in lines.indices {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        if trimmed.contains("保留的个人数据") || lower.contains("personal data kept") {
            lines[index] = line
                .replacingOccurrences(of: "保留的个人数据", with: "将要移除的个人数据")
                .replacingOccurrences(of: "Personal data kept", with: "Personal data to remove")
                .replacingOccurrences(of: "personal data kept", with: "personal data to remove")
            inRetainedSection = true
            changed = true
            continue
        }

        guard inRetainedSection else { continue }
        if trimmed.isEmpty || lower.contains("dry run complete") || trimmed.contains("预览完成") {
            inRetainedSection = false
            continue
        }
        if let markerRange = line.range(of: "⊙") {
            lines[index] = line.replacingCharacters(in: markerRange, with: "✓")
        }
    }

    return changed ? lines.joined(separator: "\n") : raw
}

func parseUninstallPreviewSummary(_ raw: String) -> UninstallPreviewSummary? {
    guard !raw.isEmpty else { return nil }

    let matchedCountText = firstMatch(in: raw, pattern: #"已匹配\s*([0-9]+)\s*个应用"#)
        ?? firstMatch(in: raw, pattern: #"(?i)matched\s+([0-9]+)\s+app"#)
    var appItemCount = 0
    var fileCount = 0
    var personalDataCount = 0
    var retainedCount = 0
    var systemFileCount = 0
    var reviewOnlyCount = 0
    var section: UninstallPreviewParseSection?

    for rawLine in raw.components(separatedBy: .newlines) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        if trimmed.contains("将要移除的文件") || lower.contains("files to be removed") {
            section = .files
            continue
        }
        if trimmed.contains("将要移除的个人数据") || lower.contains("personal data to remove") {
            section = .personalDataToRemove
            continue
        }
        if trimmed.contains("保留的个人数据") || lower.contains("personal data kept") {
            section = .personalDataKept
            continue
        }

        guard let section, let marker = trimmed.first else { continue }
        let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        let textLower = text.lowercased()

        switch marker {
        case "◎":
            if section == .files {
                if text.hasPrefix("系统:") || text.hasPrefix("系统：") || textLower.hasPrefix("system:") {
                    systemFileCount += 1
                } else if text.contains("仅需检查") || textLower.contains("review only") {
                    reviewOnlyCount += 1
                } else {
                    appItemCount += 1
                }
            }
        case "✓":
            if text.hasPrefix("系统:") || text.hasPrefix("系统：") || textLower.hasPrefix("system:") {
                systemFileCount += 1
            } else if text.contains("仅需检查") || textLower.contains("review only") {
                reviewOnlyCount += 1
            } else if section == .files {
                let pathPart = text.components(separatedBy: " , ").first ?? text
                if !pathPart.trimmingCharacters(in: .whitespaces).lowercased().hasSuffix(".app") {
                    fileCount += 1
                }
            } else if section == .personalDataToRemove {
                personalDataCount += 1
            }
        case "⊙":
            if section == .personalDataKept { retainedCount += 1 }
        default:
            break
        }
    }

    let appCount = Int(matchedCountText ?? "") ?? appItemCount
    guard appCount > 0 || fileCount > 0 || personalDataCount > 0 || retainedCount > 0
        || systemFileCount > 0 || reviewOnlyCount > 0 else { return nil }
    return UninstallPreviewSummary(
        appCount: appCount,
        fileCount: fileCount,
        personalDataCount: personalDataCount,
        retainedCount: retainedCount,
        systemFileCount: systemFileCount,
        reviewOnlyCount: reviewOnlyCount
    )
}

func parseCleanPreview(_ raw: String, whitelistPatterns: [String]) -> CleanPreview? {
    guard !raw.isEmpty else { return nil }
    var sections: [PreviewSection] = []
    var currentTitle: String?
    var currentItems: [PreviewItem] = []

    func commit() {
        if let currentTitle {
            sections.append(PreviewSection(title: currentTitle, items: currentItems))
        }
    }

    for line in raw.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("➤") {
            commit()
            currentTitle = trimmed.replacingOccurrences(of: "➤", with: "").trimmingCharacters(in: .whitespaces)
            currentItems = []
        } else if currentTitle != nil, ["○", "✓", "◎", "⊙", "•"].contains(where: { trimmed.hasPrefix($0) }) {
            let text = trimmed.replacingOccurrences(of: "○", with: "")
                .replacingOccurrences(of: "✓", with: "")
                .replacingOccurrences(of: "◎", with: "")
                .replacingOccurrences(of: "⊙", with: "")
                .replacingOccurrences(of: "•", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !cleanPreviewItemIsNoOp(text) else { continue }
            currentItems.append(
                PreviewItem(
                    text: text,
                    isWhitelisted: cleanItemMatchesWhitelist(text, patterns: whitelistPatterns)
                )
            )
        }
    }
    commit()

    let estimate = firstMatch(in: raw, pattern: #"预计可释放:\s*([^\n·]+)"#)
    let items = firstMatch(in: raw, pattern: #"预计可释放:[^\n]*?·\s*([0-9]+)\s*项"#)
        ?? firstMatch(in: raw, pattern: #"预计可释放:[^\n]*?([0-9]+)\s*项"#)
    return CleanPreview(raw: raw, estimated: estimate?.trimmingCharacters(in: .whitespaces), itemCount: items, sections: sections)
}

func parseOperationLogEntry(_ line: String) -> ParsedOperationLogEntry? {
    let pattern = #"^\[([^\]]+)\] \[([^\]]+)\] ([A-Z_]+) (.+)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let nsRange = NSRange(line.startIndex..., in: line)
    guard let match = regex.firstMatch(in: line, range: nsRange),
          match.numberOfRanges == 5,
          let timestampRange = Range(match.range(at: 1), in: line),
          let commandRange = Range(match.range(at: 2), in: line),
          let actionRange = Range(match.range(at: 3), in: line),
          let pathRange = Range(match.range(at: 4), in: line) else { return nil }

    let command = String(line[commandRange])
    guard let runRange = command.range(of: "run=") else { return nil }
    let runId = String(command[runRange.upperBound...])
    let action = String(line[actionRange])
    let pathAndDetail = String(line[pathRange])
    var path = pathAndDetail
    var detail = ""
    if pathAndDetail.hasSuffix(")"),
       let split = pathAndDetail.range(of: " (", options: .backwards) {
        path = String(pathAndDetail[..<split.lowerBound])
        let detailStart = pathAndDetail.index(split.lowerBound, offsetBy: 2)
        detail = String(pathAndDetail[detailStart..<pathAndDetail.index(before: pathAndDetail.endIndex)])
    }
    return ParsedOperationLogEntry(
        timestamp: String(line[timestampRange]),
        runId: runId,
        action: action,
        path: path,
        detail: detail
    )
}

func cleanPreviewItemIsNoOp(_ text: String) -> Bool {
    let lower = text.lowercased()
    return text.contains("无需清理")
        || lower.contains("no cleanup")
        || lower.contains("nothing to clean")
        || lower.contains("already clean")
}

func previewItemLabel(_ text: String) -> String {
    text.components(separatedBy: " · ").first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func cleanItemMatchesWhitelist(_ text: String, patterns: [String]) -> Bool {
    let lower = text.lowercased()
    if lower.contains("whitelist") || text.contains("白名单") {
        return true
    }
    if patterns.contains("FINDER_METADATA"),
       lower.contains("finder metadata") || text.contains(".DS_Store") {
        return true
    }

    let candidates = text.components(separatedBy: " · ").compactMap { whitelistPathCandidate(from: $0) }
    guard !candidates.isEmpty else { return false }

    for rawPattern in patterns where rawPattern != "FINDER_METADATA" {
        let pattern = expandWhitelistPath(rawPattern)
        for candidate in candidates {
            if whitelistPathMatches(candidate, pattern: pattern) {
                return true
            }
        }
    }
    return false
}

func whitelistPathCandidate(from component: String) -> String? {
    var value = component.trimmingCharacters(in: .whitespaces)
    if let range = value.range(of: "~/") {
        value = String(value[range.lowerBound...])
    } else if let range = value.range(of: "$HOME/") {
        value = String(value[range.lowerBound...])
    } else if value.hasPrefix("/") {
        // Already an absolute path.
    } else {
        return nil
    }
    value = value.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:)]"))
    return value.isEmpty ? nil : value
}

func expandWhitelistPath(_ raw: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("$HOME/") {
        value = home + value.dropFirst(5)
    } else if value.hasPrefix("~/") {
        value = home + value.dropFirst(1)
    } else if value == "~" {
        value = home
    }
    return value
}

func whitelistPathMatches(_ candidate: String, pattern: String) -> Bool {
    var path = expandWhitelistPath(candidate)
    while path.count > 1 && path.hasSuffix("/") {
        path.removeLast()
    }
    var normalizedPattern = expandWhitelistPath(pattern)
    while normalizedPattern.count > 1 && normalizedPattern.hasSuffix("/") {
        normalizedPattern.removeLast()
    }
    let hasGlob = normalizedPattern.contains("*") || normalizedPattern.contains("?") || normalizedPattern.contains("[")

    if hasGlob {
        let matchesGlob = normalizedPattern.withCString { patternPointer in
            path.withCString { pathPointer in
                fnmatch(patternPointer, pathPointer, 0) == 0
            }
        }
        if matchesGlob { return true }

        // A row may describe the parent directory of the protected path
        // (for example DerivedData while the whitelist protects DerivedData/*).
        // Mole protects that parent as well, so the GUI must classify it the same way.
        if let globIndex = normalizedPattern.firstIndex(where: { "*?[".contains($0) }) {
            var staticPrefix = String(normalizedPattern[..<globIndex])
            while staticPrefix.count > 1 && staticPrefix.hasSuffix("/") {
                staticPrefix.removeLast()
            }
            if !staticPrefix.isEmpty {
                return path == staticPrefix || staticPrefix.hasPrefix(path + "/")
            }
        }
        return false
    }

    return path == normalizedPattern
        || path.hasPrefix(normalizedPattern + "/")
        || normalizedPattern.hasPrefix(path + "/")
}

func firstMatch(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
          let resultRange = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[resultRange])
}
