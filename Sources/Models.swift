import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Status models

struct StatusSnapshot: Decodable {
    let collectedAt: String?
    let host: String?
    let platform: String?
    let uptime: String?
    let procs: UInt64?
    let hardware: HardwareInfo?
    let healthScore: Int?
    let healthScoreMsg: String?
    let cpu: CPUStatus?
    let gpu: [GPUStatus]?
    let memory: MemoryStatus?
    let disks: [DiskStatus]?
    let trashSize: UInt64?
    let diskIO: DiskIOStatus?
    let network: [NetworkStatus]?
    let networkHistory: NetworkHistory?
    let batteries: [BatteryStatus]?
    let thermal: ThermalStatus?
    let topProcesses: [TopProcess]?
    let processAlerts: [ProcessAlert]?
}

struct HardwareInfo: Decodable {
    let model: String?
    let cpuModel: String?
    let totalRam: String?
    let diskSize: String?
    let osVersion: String?
    let refreshRate: String?
}

struct CPUStatus: Decodable {
    let usage: Double?
    let perCore: [Double]?
    let load1: Double?
    let load5: Double?
    let load15: Double?
    let coreCount: Int?
    let logicalCpu: Int?
}

struct GPUStatus: Decodable, Identifiable {
    let name: String?
    let usage: Double?
    let memoryUsed: Double?
    let memoryTotal: Double?
    let note: String?
    var id: String { name ?? UUID().uuidString }
}

struct MemoryStatus: Decodable {
    let used: UInt64?
    let total: UInt64?
    let available: UInt64?
    let usedPercent: Double?
    let swapUsed: UInt64?
    let swapTotal: UInt64?
    let cached: UInt64?
    let pressure: String?
}

struct DiskStatus: Decodable, Identifiable {
    let mount: String?
    let device: String?
    let used: UInt64?
    let total: UInt64?
    let usedPercent: Double?
    let fstype: String?
    let external: Bool?
    let smartStatus: String?
    let purgeable: UInt64?
    var id: String { device ?? mount ?? UUID().uuidString }
}

struct DiskIOStatus: Decodable {
    let readRate: Double?
    let writeRate: Double?
}

struct NetworkStatus: Decodable, Identifiable {
    let name: String?
    let rxRateMbs: Double?
    let txRateMbs: Double?
    let ip: String?
    var id: String { name ?? UUID().uuidString }
}

struct NetworkHistory: Decodable {
    let rxHistory: [Double]?
    let txHistory: [Double]?
}

struct BatteryStatus: Decodable {
    let percent: Double?
    let status: String?
    let timeLeft: String?
    let health: String?
    let cycleCount: Int?
    let capacity: Int?
}

struct ThermalStatus: Decodable {
    let cpuTemp: Double?
    let gpuTemp: Double?
    let batteryTemp: Double?
    let fanSpeed: Int?
    let fanCount: Int?
    let systemPower: Double?
    let adapterPower: Double?
}

struct TopProcess: Decodable, Identifiable {
    let pid: Int?
    let name: String?
    let command: String?
    let cpu: Double?
    let memory: Double?
    let memoryBytes: UInt64?
    var id: Int { pid ?? Int.random(in: 1...Int.max) }
}

struct ProcessAlert: Decodable, Identifiable {
    let pid: Int?
    let name: String?
    let cpu: Double?
    let threshold: Double?
    let status: String?
    let triggeredAt: String?
    var id: String { "\(pid ?? 0)-\(name ?? "")-\(triggeredAt ?? "")" }
}

// MARK: - Analyze and history models

struct AnalyzeEntry: Decodable, Identifiable {
    let scanStatus: String?
    let name: String
    let path: String
    let size: Int64
    let isDir: Bool
    let insight: Bool?
    let cleanable: Bool?
    let lastAccess: String?
    var id: String { path }
}

struct LargeFile: Decodable, Identifiable {
    let name: String
    let path: String
    let size: Int64
    var id: String { path }
}

struct AnalyzeResponse: Decodable {
    let scanStatus: String?
    let path: String
    let overview: Bool
    let entries: [AnalyzeEntry]
    let largeFiles: [LargeFile]?
    let totalSize: Int64?
    let totalFiles: Int64?
}

struct HistoryActions: Decodable {
    let removed: Int?
    let trashed: Int?
    let skipped: Int?
    let failed: Int?
    let rebuilt: Int?
    let other: Int?
}

struct HistorySession: Decodable, Identifiable {
    let command: String
    let runId: String?
    let attribution: String?
    let startedAt: String
    let endedAt: String?
    let items: Int?
    let size: String?
    let operationCount: Int?
    let failedTasks: Int?
    let actions: HistoryActions?

    var id: String { (runId?.isEmpty == false ? runId! : "\(command)-\(startedAt)") }
}

struct HistoryFileEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let action: String
    let path: String
    let detail: String

    var actionTitle: String {
        switch action {
        case "REMOVED": return "已删除"
        case "TRASHED": return "已移入废纸篓"
        case "REBUILT": return "已重建"
        case "FAILED", "TASK_FAILED": return "失败"
        default: return action
        }
    }
}

struct ParsedOperationLogEntry {
    let timestamp: String
    let runId: String
    let action: String
    let path: String
    let detail: String
}

struct HistoryLogs: Decodable {
    let operations: String?
    let deletions: String?
}

struct HistoryResponse: Decodable {
    let logs: HistoryLogs?
    let limit: Int?
    let sessions: [HistorySession]
}

struct AppEntry: Decodable, Identifiable, Hashable {
    let name: String
    let bundleId: String
    let source: String
    let uninstallName: String
    let path: String
    let size: String
    var id: String { path }
}

// MARK: - Preview models

struct PreviewItem: Identifiable {
    let id = UUID()
    let text: String
    let isWhitelisted: Bool
}

struct PreviewSection: Identifiable {
    let title: String
    let items: [PreviewItem]
    var id: String { title }
}

struct CleanPreview {
    let raw: String
    let estimated: String?
    let itemCount: String?
    let sections: [PreviewSection]

    var whitelistedCount: Int {
        sections.reduce(0) { partial, section in
            partial + section.items.filter(\.isWhitelisted).count
        }
    }

    var pendingItemCount: Int {
        sections.reduce(0) { partial, section in
            partial + section.items.filter { !$0.isWhitelisted }.count
        }
    }
}

struct UninstallPreviewSummary {
    let appCount: Int
    let fileCount: Int
    let personalDataCount: Int
    let retainedCount: Int
    let systemFileCount: Int
    let reviewOnlyCount: Int

    var relatedFileCount: Int { fileCount + systemFileCount }
    var pendingItemCount: Int { appCount + relatedFileCount + personalDataCount }

    var breakdownText: String {
        var parts = [
            "应用本体 \(appCount) 个",
            "关联/系统文件 \(relatedFileCount) 项"
        ]
        if personalDataCount > 0 {
            parts.append("个人数据 \(personalDataCount) 项")
        }
        if retainedCount > 0 {
            parts.append("保留 \(retainedCount) 项")
        }
        if reviewOnlyCount > 0 {
            parts.append("仅需检查 \(reviewOnlyCount) 项")
        }
        return parts.joined(separator: " · ")
    }
}

struct OptimizePreviewSection: Identifiable {
    let id = UUID()
    let title: String
    let lines: [String]
    let isApplied: Bool
}

enum PendingKind {
    case clean
    case optimize
    case uninstall(AppEntry)
}

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let kind: PendingKind
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}

// MARK: - Whitelist

enum WhitelistMode: String, CaseIterable, Identifiable {
    case clean
    case optimize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "清理保护"
        case .optimize: return "优化排除"
        }
    }

    var shortTitle: String {
        switch self {
        case .clean: return "清理白名单"
        case .optimize: return "优化白名单"
        }
    }

    var explanation: String {
        switch self {
        case .clean: return "匹配这些路径或通配符的项目不会在深度清理中删除。"
        case .optimize: return "匹配这些任务或路径的优化项会被跳过。"
        }
    }

    var fileURL: URL {
        let name = self == .clean ? "whitelist" : "whitelist_optimize"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mole")
            .appendingPathComponent(name)
    }

    var header: String {
        switch self {
        case .clean:
            return """
            # Mole Whitelist - Protected paths won't be deleted
            # Saved selections replace optional defaults; built-in safety protections still apply.
            # Add one pattern per line to keep items safe.
            """
        case .optimize:
            return "# Mole Optimization Whitelist - These checks will be skipped during optimization"
        }
    }
}

// MARK: - App sections

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case clean
    case uninstall
    case optimize
    case analyze
    case history
    case whitelist
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "系统概览"
        case .clean: return "深度清理"
        case .uninstall: return "应用卸载"
        case .optimize: return "系统优化"
        case .analyze: return "磁盘分析"
        case .history: return "历史记录"
        case .whitelist: return "白名单"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "实时健康、资源与进程"
        case .clean: return "扫描缓存、日志与残留"
        case .uninstall: return "移除应用及关联文件"
        case .optimize: return "修复缓存与系统服务"
        case .analyze: return "逐层查看磁盘空间"
        case .history: return "所有 Mole 操作记录"
        case .whitelist: return "保护不想清理的路径"
        case .about: return "版本、开发者与 GitHub"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .clean: return "sparkles"
        case .uninstall: return "trash.slash"
        case .optimize: return "wrench.and.screwdriver"
        case .analyze: return "chart.pie"
        case .history: return "clock.arrow.circlepath"
        case .whitelist: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }
}
