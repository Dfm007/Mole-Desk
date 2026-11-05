import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Theme

private enum Theme {
    static let background = Color(red: 0.035, green: 0.050, blue: 0.045)
    static let sidebar = Color(red: 0.050, green: 0.070, blue: 0.062)
    static let card = Color.white.opacity(0.055)
    static let cardStrong = Color.white.opacity(0.082)
    static let border = Color.white.opacity(0.085)
    static let accent = Color(red: 0.48, green: 0.88, blue: 0.66)
    static let accentSoft = Color(red: 0.30, green: 0.65, blue: 0.48)
    static let blue = Color(red: 0.42, green: 0.69, blue: 0.98)
    static let amber = Color(red: 0.98, green: 0.72, blue: 0.34)
    static let red = Color(red: 0.96, green: 0.43, blue: 0.43)
    static let text = Color(red: 0.94, green: 0.96, blue: 0.94)
    static let secondary = Color(red: 0.65, green: 0.72, blue: 0.68)
    static let tertiary = Color(red: 0.45, green: 0.52, blue: 0.48)
}

private enum AppIdentity {
    static let name = "Mole Desk"
    static let developer = "Dfm007"
    static let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    static let githubURL = URL(string: "https://github.com/Dfm007/Mole-Desk")!
}

private func formatBytes(_ value: UInt64?, countStyle: ByteCountFormatter.CountStyle = .file) -> String {
    guard let value else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: countStyle)
}

private func formatBytes(_ value: Int64?) -> String {
    guard let value else { return "—" }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

private func formatPercent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.1f%%", value)
}

private func stripTerminalOutput(_ raw: String) -> String {
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

// MARK: - Paths and process runner

private enum MolePaths {
    static let root: String = {
        let resources = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        return resources.appendingPathComponent("Mole").path
    }()

    static var entry: URL { URL(fileURLWithPath: root).appendingPathComponent("mole") }
    static var status: URL { URL(fileURLWithPath: root).appendingPathComponent("bin/status-go") }
    static var analyze: URL { URL(fileURLWithPath: root).appendingPathComponent("bin/analyze-go") }
    static var history: URL { URL(fileURLWithPath: root).appendingPathComponent("bin/history.sh") }
}

private struct CommandResult: Sendable {
    let output: String
    let status: Int32
    let timedOut: Bool
}

private enum Runner {
    static func run(
        _ executable: URL,
        _ arguments: [String],
        extraEnvironment: [String: String] = [:],
        input: String? = nil,
        timeout: TimeInterval = 600,
        onOutput: ((String) -> Void)? = nil
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: MolePaths.root)

                var environment = ProcessInfo.processInfo.environment
                let shimPath = Bundle.main.resourceURL?.appendingPathComponent("bin").path ?? ""
                environment["PATH"] = (shimPath.isEmpty ? "" : shimPath + ":") + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                environment["MOLE_LANG"] = "zh_CN"
                environment["NO_COLOR"] = "1"
                environment["TERM"] = "dumb"
                for (key, value) in extraEnvironment {
                    environment[key] = value
                }
                process.environment = environment

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                if let input {
                    let inputPipe = Pipe()
                    process.standardInput = inputPipe
                    do {
                        try process.run()
                        if let data = input.data(using: .utf8) {
                            inputPipe.fileHandleForWriting.write(data)
                        }
                        try? inputPipe.fileHandleForWriting.close()
                    } catch {
                        continuation.resume(returning: CommandResult(output: error.localizedDescription, status: -1, timedOut: false))
                        return
                    }
                } else {
                    process.standardInput = FileHandle.nullDevice
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(returning: CommandResult(output: error.localizedDescription, status: -1, timedOut: false))
                        return
                    }
                }

                let lock = NSLock()
                var didTimeout = false
                let timeoutWork = DispatchWorkItem {
                    lock.lock()
                    if process.isRunning {
                        didTimeout = true
                    }
                    lock.unlock()
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

                let readGroup = DispatchGroup()
                let outputLock = NSLock()
                var collected = Data()

                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    var data = Data()
                    while true {
                        let chunk = pipe.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        data.append(chunk)
                        if let onOutput {
                            onOutput(String(decoding: chunk, as: UTF8.self))
                        }
                    }
                    outputLock.lock()
                    collected = data
                    outputLock.unlock()
                    readGroup.leave()
                }

                process.waitUntilExit()
                readGroup.wait()
                timeoutWork.cancel()

                lock.lock()
                let timedOut = didTimeout
                lock.unlock()

                outputLock.lock()
                let data = collected
                outputLock.unlock()

                let output = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                continuation.resume(returning: CommandResult(output: output, status: process.terminationStatus, timedOut: timedOut))
            }
        }
    }
}

// MARK: - Status models

private struct StatusSnapshot: Decodable {
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

private struct HardwareInfo: Decodable {
    let model: String?
    let cpuModel: String?
    let totalRam: String?
    let diskSize: String?
    let osVersion: String?
    let refreshRate: String?
}

private struct CPUStatus: Decodable {
    let usage: Double?
    let perCore: [Double]?
    let load1: Double?
    let load5: Double?
    let load15: Double?
    let coreCount: Int?
    let logicalCpu: Int?
}

private struct GPUStatus: Decodable, Identifiable {
    let name: String?
    let usage: Double?
    let memoryUsed: Double?
    let memoryTotal: Double?
    let note: String?
    var id: String { name ?? UUID().uuidString }
}

private struct MemoryStatus: Decodable {
    let used: UInt64?
    let total: UInt64?
    let available: UInt64?
    let usedPercent: Double?
    let swapUsed: UInt64?
    let swapTotal: UInt64?
    let cached: UInt64?
    let pressure: String?
}

private struct DiskStatus: Decodable, Identifiable {
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

private struct DiskIOStatus: Decodable {
    let readRate: Double?
    let writeRate: Double?
}

private struct NetworkStatus: Decodable, Identifiable {
    let name: String?
    let rxRateMbs: Double?
    let txRateMbs: Double?
    let ip: String?
    var id: String { name ?? UUID().uuidString }
}

private struct NetworkHistory: Decodable {
    let rxHistory: [Double]?
    let txHistory: [Double]?
}

private struct BatteryStatus: Decodable {
    let percent: Double?
    let status: String?
    let timeLeft: String?
    let health: String?
    let cycleCount: Int?
    let capacity: Int?
}

private struct ThermalStatus: Decodable {
    let cpuTemp: Double?
    let gpuTemp: Double?
    let batteryTemp: Double?
    let fanSpeed: Int?
    let fanCount: Int?
    let systemPower: Double?
    let adapterPower: Double?
}

private struct TopProcess: Decodable, Identifiable {
    let pid: Int?
    let name: String?
    let command: String?
    let cpu: Double?
    let memory: Double?
    let memoryBytes: UInt64?
    var id: Int { pid ?? Int.random(in: 1...Int.max) }
}

private struct ProcessAlert: Decodable, Identifiable {
    let pid: Int?
    let name: String?
    let cpu: Double?
    let threshold: Double?
    let status: String?
    let triggeredAt: String?
    var id: String { "\(pid ?? 0)-\(name ?? "")-\(triggeredAt ?? "")" }
}

// MARK: - Analyze and history models

private struct AnalyzeEntry: Decodable, Identifiable {
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

private struct LargeFile: Decodable, Identifiable {
    let name: String
    let path: String
    let size: Int64
    var id: String { path }
}

private struct AnalyzeResponse: Decodable {
    let scanStatus: String?
    let path: String
    let overview: Bool
    let entries: [AnalyzeEntry]
    let largeFiles: [LargeFile]?
    let totalSize: Int64?
    let totalFiles: Int64?
}

private struct HistoryActions: Decodable {
    let removed: Int?
    let trashed: Int?
    let skipped: Int?
    let failed: Int?
    let rebuilt: Int?
    let other: Int?
}

private struct HistorySession: Decodable, Identifiable {
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

private struct HistoryFileEntry: Identifiable {
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

private struct ParsedOperationLogEntry {
    let timestamp: String
    let runId: String
    let action: String
    let path: String
    let detail: String
}

private struct HistoryLogs: Decodable {
    let operations: String?
    let deletions: String?
}

private struct HistoryResponse: Decodable {
    let logs: HistoryLogs?
    let limit: Int?
    let sessions: [HistorySession]
}

private struct AppEntry: Decodable, Identifiable, Hashable {
    let name: String
    let bundleId: String
    let source: String
    let uninstallName: String
    let path: String
    let size: String
    var id: String { path }
}

// MARK: - Preview models

private struct PreviewItem: Identifiable {
    let id = UUID()
    let text: String
    let isWhitelisted: Bool
}

private struct PreviewSection: Identifiable {
    let title: String
    let items: [PreviewItem]
    var id: String { title }
}

private struct CleanPreview {
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

private struct OptimizePreviewSection: Identifiable {
    let id = UUID()
    let title: String
    let lines: [String]
    let isApplied: Bool
}

private enum PendingKind {
    case clean
    case optimize
    case uninstall(AppEntry)
}

private struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let kind: PendingKind
}

private struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}

// MARK: - Whitelist

private enum WhitelistMode: String, CaseIterable, Identifiable {
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

private enum AppSection: String, CaseIterable, Identifiable {
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

// MARK: - Model

@MainActor
private final class AppModel: ObservableObject {
    @Published var section: AppSection = .dashboard
    @Published var status: StatusSnapshot?
    @Published var statusError: String?
    @Published var isRefreshingStatus = false
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var networkHistory: [Double] = []

    @Published var busyMessage: String?
    @Published var busyProgress: Double?
    @Published var busyProgressText: String?
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var toast: ToastMessage?

    @Published var cleanPreview: CleanPreview?
    @Published var cleanRaw = ""
    @Published var cleanResult = ""
    @Published var optimizeRaw = ""
    @Published var optimizeSections: [OptimizePreviewSection] = []
    @Published var optimizeResult = ""

    @Published var apps: [AppEntry] = []
    @Published var appsLoading = false
    @Published var selectedApp: AppEntry?
    @Published var uninstallRaw = ""
    @Published var uninstallResult = ""

    @Published var analysis: AnalyzeResponse?
    @Published var analysisPath = NSHomeDirectory()
    @Published var analysisStatus = "选择文件夹后开始扫描"

    @Published var history: HistoryResponse?
    @Published var historyLoading = false
    @Published var historyDetails: [HistoryFileEntry] = []
    @Published var historyDetailsLoading = false
    @Published var historyDetailsError: String?

    @Published var cleanWhitelist: [String] = []
    @Published var optimizeWhitelist: [String] = []
    @Published var whitelistError: String?

    private var started = false
    private var monitorTask: Task<Void, Never>?
    private var cleanProgressTotal = 0
    private var cleanProgressDone = 0
    private var cleanProgressLabels: Set<String> = []
    private var cleanDoneLabels: Set<String> = []
    private var cleanProgressBuffer = ""

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--section"), args.indices.contains(index + 1),
           let requested = AppSection(rawValue: args[index + 1]) {
            section = requested
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        await refreshStatus()
        await loadHistory()
        loadWhitelists()
        let args = ProcessInfo.processInfo.arguments
        if let fixtureIndex = args.firstIndex(of: "--clean-fixture"),
           args.indices.contains(fixtureIndex + 1),
           let fixture = try? String(contentsOfFile: args[fixtureIndex + 1], encoding: .utf8) {
            cleanRaw = stripTerminalOutput(fixture)
            cleanPreview = parseCleanPreview(cleanRaw, whitelistPatterns: cleanWhitelist)
        }
        if let fixtureIndex = args.firstIndex(of: "--optimize-fixture"),
           args.indices.contains(fixtureIndex + 1),
           let fixture = try? String(contentsOfFile: args[fixtureIndex + 1], encoding: .utf8) {
            let raw = stripTerminalOutput(fixture)
            optimizeSections = parseOptimizePreviewSections(raw)
            optimizeRaw = removeOptimizeMarkers(raw)
        }
        if args.contains("--auto-preview") {
            switch section {
            case .clean:
                await previewClean()
            case .optimize:
                await previewOptimize()
            case .uninstall:
                await loadApps(force: true)
            case .analyze:
                let path: String
                if let index = args.firstIndex(of: "--analyze-path"), args.indices.contains(index + 1) {
                    path = args[index + 1]
                } else {
                    path = NSHomeDirectory()
                }
                await scanAnalyze(path: path)
            case .whitelist:
                loadWhitelists()
            case .dashboard, .history, .about:
                break
            }
        }
        if args.contains("--progress-demo") {
            busyMessage = "正在清理，请保持 Mole 运行…"
            busyProgress = 0.45
            busyProgressText = "9 / 20 项"
        }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                await self.refreshStatus()
            }
        }
    }

    deinit {
        monitorTask?.cancel()
    }

    func refreshStatus() async {
        guard !isRefreshingStatus else { return }
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        let result = await Runner.run(MolePaths.status, ["--json"], timeout: 12)
        guard result.status == 0 else {
            statusError = stripTerminalOutput(result.output).isEmpty ? "无法读取系统状态" : stripTerminalOutput(result.output)
            return
        }
        do {
            let decoded = try JSONDecoder.snakeCase.decode(StatusSnapshot.self, from: Data(result.output.utf8))
            status = decoded
            statusError = nil
            if let cpu = decoded.cpu?.usage { append(cpu, to: &cpuHistory) }
            if let memory = decoded.memory?.usedPercent { append(memory, to: &memoryHistory) }
            let rx = decoded.network?.compactMap(\.rxRateMbs).reduce(0, +) ?? 0
            let tx = decoded.network?.compactMap(\.txRateMbs).reduce(0, +) ?? 0
            append(rx + tx, to: &networkHistory)
        } catch {
            statusError = "状态数据解析失败：\(error.localizedDescription)"
        }
    }

    private func append(_ value: Double, to array: inout [Double]) {
        array.append(value)
        if array.count > 60 {
            array.removeFirst(array.count - 60)
        }
    }

    func loadHistory() async {
        guard !historyLoading else { return }
        historyLoading = true
        defer { historyLoading = false }
        let result = await Runner.run(MolePaths.history, ["--json"], timeout: 30)
        guard result.status == 0 else { return }
        guard let decoded = try? JSONDecoder.snakeCase.decode(HistoryResponse.self, from: Data(result.output.utf8)) else {
            return
        }
        let actualSessions = decoded.sessions.filter { session in
            guard !session.command.hasSuffix("-dry-run") else { return false }
            return (session.items ?? 0) > 0 || (session.operationCount ?? 0) > 0
        }
        history = HistoryResponse(logs: decoded.logs, limit: decoded.limit, sessions: actualSessions)
    }

    func loadHistoryDetails(for session: HistorySession) async {
        historyDetails = []
        historyDetailsError = nil
        guard let runId = session.runId, !runId.isEmpty else {
            historyDetailsError = "该记录没有可用的运行标识，无法关联文件明细。"
            return
        }
        historyDetailsLoading = true
        defer { historyDetailsLoading = false }

        let logPath = history?.logs?.operations
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/mole/operations.log").path
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            historyDetailsError = "无法读取 Mole 操作日志。"
            return
        }

        let relevantActions: Set<String> = ["REMOVED", "TRASHED", "REBUILT", "FAILED", "TASK_FAILED"]
        var entries: [HistoryFileEntry] = []
        for line in content.components(separatedBy: .newlines) {
            guard let parsed = parseOperationLogEntry(line),
                  parsed.runId == runId,
                  relevantActions.contains(parsed.action) else { continue }
            entries.append(
                HistoryFileEntry(
                    timestamp: parsed.timestamp,
                    action: parsed.action,
                    path: parsed.path,
                    detail: parsed.detail
                )
            )
        }
        historyDetails = entries
        if entries.isEmpty {
            historyDetailsError = "没有找到这次操作的文件明细，日志可能已轮转。"
        }
    }

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
        uninstallResult = ""
    }

    func previewUninstall(_ app: AppEntry) async {
        selectedApp = app
        busyMessage = "正在分析 \(app.name) 的关联文件…"
        let result = await Runner.run(
            MolePaths.entry,
            ["uninstall", "--dry-run", app.uninstallName],
            extraEnvironment: ["MO_NO_OPLOG": "1"],
            timeout: 600
        )
        uninstallRaw = stripTerminalOutput(result.output)
        busyMessage = nil
        if uninstallRaw.isEmpty {
            showToast("未能生成卸载预览", color: Theme.red)
        }
    }

    func requestUninstall(_ app: AppEntry) {
        guard !uninstallRaw.isEmpty else { return }
        pendingConfirmation = PendingConfirmation(
            title: "卸载 \(app.name)？",
            message: "应用默认会移入废纸篓，个人数据默认保留。Mole 会再次扫描关联文件，执行后可在废纸篓恢复应用本体。",
            confirmTitle: "卸载应用",
            kind: .uninstall(app)
        )
    }

    func runUninstall(_ app: AppEntry) async {
        busyMessage = "正在卸载 \(app.name)…"
        let authorized = await ensureSudoAuthorization()
        guard authorized else {
            busyMessage = nil
            showToast("未获得管理员授权，已取消卸载", color: Theme.amber)
            return
        }

        let script = """
        set timeout 1200
        log_user 1
        spawn $env(MOLE_BIN) uninstall $env(APP_NAME)
        expect {
            -re {确认|confirm} {
                send "\\r"
                exp_continue
            }
            -re {Password:|密码} {
                puts "\\n__SUDO_REQUIRED__\\n"
                exit 9
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
                "MOLE_BIN": MolePaths.entry.path,
                "APP_NAME": app.uninstallName,
                "TERM": "xterm-256color"
            ],
            timeout: 1260
        )
        uninstallResult = stripTerminalOutput(result.output)
        busyMessage = nil
        if result.status == 0 {
            showToast("\(app.name) 已卸载", color: Theme.accent)
            selectedApp = nil
            uninstallRaw = ""
            await loadApps(force: true)
        } else if uninstallResult.contains("__SUDO_REQUIRED__") {
            showToast("管理员授权已失效，请重试", color: Theme.amber)
        } else {
            showToast("卸载未完成，请查看输出", color: Theme.amber)
        }
        await refreshStatus()
        await loadHistory()
    }

    private func ensureSudoAuthorization() async -> Bool {
        let cached = await Runner.run(URL(fileURLWithPath: "/usr/bin/sudo"), ["-n", "true"], timeout: 10)
        if cached.status == 0 { return true }

        let prompt = """
        display dialog "Mole Desk 需要管理员权限来移除应用及其系统级残留文件。" default answer "" with title "Mole Desk" with icon caution with hidden answer buttons {"取消", "继续"} default button "继续"
        text returned of result
        """
        let dialog = await Runner.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", prompt], timeout: 180)
        guard dialog.status == 0 else { return false }
        let password = dialog.output.trimmingCharacters(in: .newlines)
        guard !password.isEmpty else { return false }
        let auth = await Runner.run(
            URL(fileURLWithPath: "/usr/bin/sudo"),
            ["-S", "-p", "", "-v"],
            input: password + "\n",
            timeout: 30
        )
        return auth.status == 0
    }

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

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "分析此文件夹"
        panel.message = "选择要分析磁盘占用的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await scanAnalyze(path: url.path) }
        }
    }

    func scanAnalyze(path: String) async {
        analysisPath = path
        analysisStatus = "正在扫描，首次分析可能较慢…"
        busyMessage = "正在分析磁盘占用，请稍候…"
        let result = await Runner.run(MolePaths.analyze, ["--json", path], timeout: 1800)
        busyMessage = nil
        guard result.status == 0 else {
            analysisStatus = stripTerminalOutput(result.output)
            analysis = nil
            return
        }
        do {
            let decoded = try JSONDecoder.snakeCase.decode(AnalyzeResponse.self, from: Data(result.output.utf8))
            analysis = decoded
            analysisStatus = decoded.scanStatus == "complete" ? "扫描完成" : "扫描部分完成"
        } catch {
            analysisStatus = "分析结果解析失败：\(error.localizedDescription)"
            analysis = nil
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func perform(_ kind: PendingKind) {
        Task {
            switch kind {
            case .clean:
                await runClean()
            case .optimize:
                await runOptimize()
            case .uninstall(let app):
                await runUninstall(app)
            }
        }
    }

    func showToast(_ text: String, color: Color) {
        let message = ToastMessage(text: text, color: color)
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self else { return }
            if self.toast?.id == message.id {
                self.toast = nil
            }
        }
    }
}

private extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private func parseOptimizePreviewSections(_ raw: String) -> [OptimizePreviewSection] {
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

private func removeOptimizeMarkers(_ raw: String) -> String {
    raw.components(separatedBy: .newlines)
        .filter { !$0.contains("MOLE_OPTIMIZE_APPLIED:") }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseCleanPreview(_ raw: String, whitelistPatterns: [String]) -> CleanPreview? {
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

private func parseOperationLogEntry(_ line: String) -> ParsedOperationLogEntry? {
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

private func cleanPreviewItemIsNoOp(_ text: String) -> Bool {
    let lower = text.lowercased()
    return text.contains("无需清理")
        || lower.contains("no cleanup")
        || lower.contains("nothing to clean")
        || lower.contains("already clean")
}

private func previewItemLabel(_ text: String) -> String {
    text.components(separatedBy: " · ").first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func cleanItemMatchesWhitelist(_ text: String, patterns: [String]) -> Bool {
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

private func whitelistPathCandidate(from component: String) -> String? {
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

private func expandWhitelistPath(_ raw: String) -> String {
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

private func whitelistPathMatches(_ candidate: String, pattern: String) -> Bool {
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

private func firstMatch(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
          let resultRange = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[resultRange])
}

// MARK: - Root views

private struct RootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
            Rectangle().fill(Theme.border).frame(width: 1)
            ZStack {
                Theme.background
                Group {
                    switch model.section {
                    case .dashboard: DashboardView(model: model)
                    case .clean: CleanView(model: model)
                    case .uninstall: UninstallView(model: model)
                    case .optimize: OptimizeView(model: model)
                    case .analyze: AnalyzeView(model: model)
                    case .history: HistoryView(model: model)
                    case .whitelist: WhitelistView(model: model)
                    case .about: AboutView()
                    }
                }
            }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .alert(item: $model.pendingConfirmation) { pending in
            Alert(
                title: Text(pending.title),
                message: Text(pending.message),
                primaryButton: .destructive(Text(pending.confirmTitle)) {
                    model.perform(pending.kind)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .overlay {
            if let busy = model.busyMessage {
                ZStack {
                    Color.black.opacity(0.42).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(Theme.accent)
                        Text(busy).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                        if let progress = model.busyProgress {
                            DeterminateProgressBar(progress: progress)
                                .padding(.top, 2)
                            if let progressText = model.busyProgressText {
                                Text(progressText)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.secondary)
                            }
                        } else {
                            IndeterminateProgressBar()
                                .padding(.top, 2)
                        }
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                HStack(spacing: 9) {
                    Circle().fill(toast.color).frame(width: 8, height: 8)
                    Text(toast.text).font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.border))
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast?.id)
    }
}

private struct DeterminateProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accentSoft, Theme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geometry.size.width * CGFloat(max(0, min(1, progress)))))
            }
        }
        .frame(width: 250, height: 6)
        .animation(.easeOut(duration: 0.25), value: progress)
        .accessibilityLabel("清理进度")
        .accessibilityValue("\(Int(progress * 100))%")
    }
}

private struct IndeterminateProgressBar: View {
    @State private var phase: CGFloat = -0.35

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.05), Theme.accent, Theme.accent.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(56, geometry.size.width * 0.42))
                    .offset(x: geometry.size.width * phase)
            }
            .clipShape(Capsule())
        }
        .frame(width: 250, height: 6)
        .onAppear {
            phase = -0.42
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                phase = 1.05
            }
        }
        .accessibilityLabel("正在处理")
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                appIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mole Desk").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                    Text("macOS 图形控制台").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 22)

            Text("功能").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                .textCase(.uppercase).padding(.horizontal, 20).padding(.bottom, 8)

            VStack(spacing: 5) {
                ForEach(AppSection.allCases) { item in
                    Button {
                        model.section = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 22)
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if item == .dashboard, let score = model.status?.healthScore {
                                Text("\(score)").font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(score >= 80 ? Theme.accent : Theme.amber)
                            }
                        }
                        .foregroundStyle(model.section == item ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.section == item ? Theme.cardStrong : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(model.statusError == nil ? Theme.accent : Theme.amber).frame(width: 7, height: 7)
                    Text(model.statusError == nil ? "Mole CLI 已连接" : "状态读取异常")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                Text(model.status?.hardware?.model ?? "macOS")
                    .font(.system(size: 10)).foregroundStyle(Theme.tertiary).lineLimit(1)
                Text("v\(AppIdentity.version) · \(AppIdentity.developer)")
                    .font(.system(size: 9)).foregroundStyle(Theme.tertiary.opacity(0.75))
            }
            .padding(16)
        }
        .frame(width: 224)
        .background(Theme.sidebar)
    }

    private var appIcon: some View {
        Group {
            if let image = NSImage(named: "MoleIcon") {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "sparkles").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - Dashboard

private struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "系统概览",
                    subtitle: "来自 Mole Status 的实时健康数据",
                    trailing: AnyView(
                        Button {
                            Task { await model.refreshStatus() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.isRefreshingStatus)
                    )
                )

                if let snapshot = model.status {
                    dashboardContent(snapshot)
                } else if let error = model.statusError {
                    ErrorCard(message: error)
                } else {
                    LoadingCard(text: "正在收集系统状态…")
                }
            }
            .padding(28)
        }
    }

    @ViewBuilder
    private func dashboardContent(_ snapshot: StatusSnapshot) -> some View {
        let cpu = snapshot.cpu?.usage ?? 0
        let memory = snapshot.memory?.usedPercent ?? 0
        let rootDisk = snapshot.disks?.first(where: { $0.mount == "/" }) ?? snapshot.disks?.first
        let disk = rootDisk?.usedPercent ?? 0
        let networkRate = (snapshot.network?.compactMap(\.rxRateMbs).reduce(0, +) ?? 0)
            + (snapshot.network?.compactMap(\.txRateMbs).reduce(0, +) ?? 0)

        HStack(spacing: 14) {
            HealthScoreCard(score: snapshot.healthScore ?? 0, message: snapshot.healthScoreMsg ?? "")
            MetricCard(title: "CPU", value: String(format: "%.0f%%", cpu), subtitle: "\(snapshot.cpu?.logicalCpu ?? 0) 逻辑核心", icon: "cpu", color: Theme.accent, progress: cpu / 100)
            MetricCard(title: "内存", value: formatPercent(memory), subtitle: "\(formatBytes(snapshot.memory?.used)) / \(formatBytes(snapshot.memory?.total))", icon: "memorychip", color: Theme.blue, progress: memory / 100)
            DiskMetricCard(
                percent: disk,
                total: rootDisk?.total ?? 0,
                used: rootDisk?.used ?? 0,
                available: max(0, (rootDisk?.total ?? 0) - (rootDisk?.used ?? 0)),
                filesystem: rootDisk?.fstype?.uppercased() ?? "系统盘"
            )
        }

        HStack(alignment: .top, spacing: 14) {
            ChartCard(title: "CPU 使用率", value: String(format: "%.1f%%", cpu), data: model.cpuHistory, color: Theme.accent)
            ChartCard(title: "内存压力", value: formatPercent(memory), data: model.memoryHistory, color: Theme.blue)
            ChartCard(title: "网络吞吐", value: String(format: "%.2f MB/s", networkRate), data: model.networkHistory, color: Theme.amber)
        }

        HStack(alignment: .top, spacing: 14) {
            TopProcessesCard(processes: Array((snapshot.topProcesses ?? []).prefix(6)))
            SystemDetailsCard(snapshot: snapshot)
        }
    }
}

private struct HealthScoreCard: View {
    let score: Int
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("健康评分").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                        .stroke(
                            AngularGradient(colors: [Theme.accent, Theme.blue, Theme.accent], center: .center),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(score)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                        Text("分").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 7) {
                    Text(healthTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(message.isEmpty ? "系统运行状态" : message).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text("实时刷新").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(width: 260, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }

    private var healthTitle: String {
        switch score {
        case 85...: return "状态优秀"
        case 70..<85: return "总体良好"
        case 50..<70: return "需要关注"
        default: return "建议维护"
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                Spacer()
            }
            Text(value).font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.75)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.tertiary).lineLimit(1)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(color).frame(width: max(4, geometry.size.width * CGFloat(max(0, min(1, progress)))))
                }
            }
            .frame(height: 5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 137, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

private struct DiskMetricCard: View {
    let percent: Double
    let total: UInt64
    let used: UInt64
    let available: UInt64
    let filesystem: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.amber)
                Text("磁盘").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(filesystem).font(.system(size: 8, weight: .medium)).foregroundStyle(Theme.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(percent.rounded()))%").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text("已用").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tertiary)
            }
            HStack(spacing: 8) {
                DiskCapacityValue(label: "总容量", value: formatBytes(total))
                DiskCapacityValue(label: "已用", value: formatBytes(used))
                DiskCapacityValue(label: "可用", value: formatBytes(available))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(Theme.amber).frame(width: max(4, geometry.size.width * CGFloat(max(0, min(1, percent / 100)))))
                }
            }
            .frame(height: 5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 137, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

private struct DiskCapacityValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(Theme.tertiary)
            Text(value).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChartCard: View {
    let title: String
    let value: String
    let data: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(color)
            }
            if data.count > 1 {
                Chart(Array(data.enumerated()), id: \.offset) { item in
                    AreaMark(x: .value("时间", item.offset), y: .value(title, item.element))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("时间", item.offset), y: .value(title, item.element))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...max(1, (data.max() ?? 1) * 1.25))
                .frame(height: 78)
            } else {
                HStack {
                    Spacer()
                    Text("等待数据").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    Spacer()
                }
                .frame(height: 78)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Theme.border))
    }
}

private struct TopProcessesCard: View {
    let processes: [TopProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("高占用进程").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text("CPU / 内存").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
            }
            ForEach(processes) { process in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.cardStrong).frame(width: 28, height: 28)
                        .overlay(Text(process.name?.prefix(1).uppercased() ?? "?").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(process.name ?? "未知进程").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text("PID \(process.pid ?? 0)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", process.cpu ?? 0)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle((process.cpu ?? 0) > 50 ? Theme.amber : Theme.secondary)
                    Text(formatBytes(process.memoryBytes)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiary).frame(width: 54, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

private struct SystemDetailsCard: View {
    let snapshot: StatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统信息").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            InfoRow(label: "系统", value: snapshot.hardware?.osVersion ?? snapshot.platform ?? "—")
            InfoRow(label: "处理器", value: snapshot.hardware?.cpuModel ?? "—")
            InfoRow(label: "运行时间", value: snapshot.uptime ?? "—")
            InfoRow(label: "进程数", value: "\(snapshot.procs ?? 0)")
            InfoRow(label: "磁盘读写", value: String(format: "R %.1f / W %.1f MB/s", snapshot.diskIO?.readRate ?? 0, snapshot.diskIO?.writeRate ?? 0))
            if let battery = snapshot.batteries?.first {
                InfoRow(label: "电池", value: "\(Int(battery.percent ?? 0))% · \(battery.status ?? "")")
            }
            Divider().overlay(Theme.border)
            if let disks = snapshot.disks, !disks.isEmpty {
                ForEach(disks.prefix(4)) { disk in
                    HStack(spacing: 8) {
                        Image(systemName: (disk.mount == "/") ? "internaldrive" : "externaldrive")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary).frame(width: 14)
                        Text(disk.mount ?? disk.device ?? "—").font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                        Spacer()
                        Text(formatBytes(disk.total)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiary)
                        Text("\(Int((disk.usedPercent ?? 0).rounded()))%").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.amber)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }
}

// MARK: - Clean

private struct CleanView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "深度清理",
                    subtitle: "先扫描预览，再决定是否执行",
                    trailing: AnyView(
                        HStack(spacing: 10) {
                            Button {
                                Task { await model.previewClean() }
                            } label: { Label("扫描预览", systemImage: "magnifyingglass") }
                                .buttonStyle(SecondaryButtonStyle())
                            Button {
                                model.requestClean()
                            } label: { Label("执行清理", systemImage: "sparkles") }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(model.cleanPreview == nil)
                        }
                    )
                )

                SafetyNotice(
                    icon: "checkmark.shield",
                    title: "删除前先预览",
                    text: "扫描不会修改文件。当前有 \(model.cleanWhitelist.count) 条清理保护规则；执行时 Mole 仍会按安全边界删除缓存与残留，必要时弹出管理员授权。"
                )

                if let preview = model.cleanPreview {
                    HStack(spacing: 14) {
                        SummaryStat(title: "预计可释放", value: preview.estimated ?? "—", icon: "externaldrive.badge.checkmark", color: Theme.accent)
                        SummaryStat(title: "待清理项", value: "\(preview.pendingItemCount) 项", icon: "square.stack.3d.up", color: Theme.blue)
                        SummaryStat(
                            title: "白名单命中",
                            value: preview.whitelistedCount > 0 ? "\(preview.whitelistedCount) 项" : "未命中",
                            icon: "checkmark.shield",
                            color: Theme.accent
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Text("扫描明细").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            LegendDot(color: Theme.amber, text: "待清理")
                            LegendDot(color: Theme.accent, text: "白名单")
                            LegendDot(color: Theme.tertiary, text: "无需清理")
                        }
                        ForEach(preview.sections) { section in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(section.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                                if section.items.isEmpty {
                                    Text("无需清理").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                                } else {
                                    ForEach(section.items) { item in
                                        HStack(alignment: .top, spacing: 7) {
                                            Circle()
                                                .fill(item.isWhitelisted ? Theme.accent : Theme.amber)
                                                .frame(width: 4, height: 4)
                                                .padding(.top, 5)
                                            Text(item.text)
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 6)
                                            if item.isWhitelisted {
                                                WhitelistPreviewBadge()
                                            }
                                        }
                                    }
                                }
                            }
                            if section.id != preview.sections.last?.id {
                                Divider().overlay(Theme.border)
                            }
                        }
                    }
                    .padding(17)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))

                    LogDisclosure(title: "查看完整扫描输出", text: preview.raw)
                } else {
                    EmptyStateCard(
                        icon: "sparkles",
                        title: "还没有扫描",
                        text: "点击“扫描预览”查看可释放空间。预览完成前不会删除任何文件。"
                    )
                }

                if !model.cleanResult.isEmpty {
                    LogDisclosure(title: "本次清理结果", text: model.cleanResult, expanded: true)
                }
            }
            .padding(28)
        }
    }
}

private struct WhitelistPreviewBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 7, weight: .bold))
            Text("白名单")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.accent.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(Theme.accent.opacity(0.20)))
        .fixedSize()
    }
}

// MARK: - Optimize

private struct OptimizeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "系统优化",
                    subtitle: "修复缓存、数据库、Spotlight 与网络服务",
                    trailing: AnyView(
                        HStack(spacing: 10) {
                            Button {
                                Task { await model.previewOptimize() }
                            } label: { Label("检查项目", systemImage: "stethoscope") }
                                .buttonStyle(SecondaryButtonStyle())
                            Button {
                                model.requestOptimize()
                            } label: { Label("开始优化", systemImage: "wrench.and.screwdriver") }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(model.optimizeRaw.isEmpty)
                        }
                    )
                )

                SafetyNotice(
                    icon: "exclamationmark.shield",
                    title: "部分优化需要管理员权限",
                    text: "当前有 \(model.optimizeWhitelist.count) 条优化排除规则。执行时可能弹出 macOS 管理员授权窗口，建议先关闭浏览器、设计软件和数据库应用。"
                )

                if model.optimizeRaw.isEmpty {
                    EmptyStateCard(
                        icon: "wrench.and.screwdriver",
                        title: "先检查当前系统",
                        text: "点击“检查项目”生成优化预览，再决定是否执行。"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("优化预览").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            Text("只读检查").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent)
                        }
                        OptimizePreviewView(sections: model.optimizeSections)
                    }
                    .padding(17)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))

                    LogDisclosure(title: "查看完整预览", text: model.optimizeRaw)
                }

                if !model.optimizeResult.isEmpty {
                    LogDisclosure(title: "本次优化结果", text: model.optimizeResult, expanded: true)
                }
            }
            .padding(28)
        }
    }
}

private struct OptimizePreviewView: View {
    let sections: [OptimizePreviewSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let appliedCount = sections.filter(\.isApplied).count
            HStack(spacing: 8) {
                Text("待执行项")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                Text("\(appliedCount) 项")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.amber)
                Spacer()
                LegendDot(color: Theme.amber, text: "待执行")
                LegendDot(color: Theme.accent, text: "不执行/诊断")
            }
            .padding(.bottom, 2)

            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(section.isApplied ? Theme.amber : Theme.accent)
                        if section.isApplied {
                            OptimizeAppliedBadge()
                        } else if section.title == "系统状态" {
                            Text("仅诊断")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.08), in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(.top, 2)

                    if section.title == "系统状态" {
                        Text("以下为运行状态和诊断信息，不会作为优化任务执行。")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiary)
                    }

                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(section.isApplied ? Theme.amber : Theme.accent)
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(trimmed).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 9)).foregroundStyle(Theme.tertiary)
        }
    }
}

private struct OptimizeAppliedBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 7, weight: .bold))
            Text("待执行")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.amber.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(Theme.amber.opacity(0.20)))
        .fixedSize()
    }
}

// MARK: - Uninstall

private struct UninstallView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""

    private var filteredApps: [AppEntry] {
        if search.trimmingCharacters(in: .whitespaces).isEmpty { return model.apps }
        return model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.bundleId.localizedCaseInsensitiveContains(search)
                || $0.path.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "应用卸载",
                subtitle: "应用本体默认移入废纸篓，个人数据默认保留",
                trailing: AnyView(
                    Button {
                        Task { await model.loadApps(force: true) }
                    } label: { Label("刷新列表", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.appsLoading)
                )
            )

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
                TextField("搜索应用、Bundle ID 或路径", text: $search)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.text)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("已安装应用").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("\(filteredApps.count)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    }
                    .padding(14)
                    Divider().overlay(Theme.border)
                    if model.appsLoading && model.apps.isEmpty {
                        ProgressView().padding(30)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(filteredApps) { app in
                                    AppRow(app: app, selected: model.selectedApp?.id == app.id) {
                                        model.selectApp(app)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(width: 370)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))

                if let app = model.selectedApp {
                    UninstallDetailView(model: model, app: app)
                } else {
                    EmptyStateCard(icon: "trash.slash", title: "选择一个应用", text: "从左侧列表选择应用后，可先预览关联文件，再执行卸载。")
                }
            }
        }
        .padding(28)
        .task { await model.loadApps() }
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.accent.opacity(0.18) : Theme.cardStrong)
                    .frame(width: 34, height: 34)
                    .overlay(Text(app.name.prefix(1).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(selected ? Theme.accent : Theme.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(app.path).font(.system(size: 9)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.size).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary)
                    if app.source == "Homebrew" {
                        Text("Brew").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.blue)
                    }
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.cardStrong : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct UninstallDetailView: View {
    @ObservedObject var model: AppModel
    let app: AppEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 13).fill(Theme.cardStrong).frame(width: 54, height: 54)
                    .overlay(Text(app.name.prefix(1).uppercased()).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.accent))
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                    Text(app.bundleId).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    Text(app.path).font(.system(size: 9)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                Spacer()
                Text(app.size).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Theme.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await model.previewUninstall(app) }
                } label: { Label("预览关联文件", systemImage: "doc.text.magnifyingglass") }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    model.requestUninstall(app)
                } label: { Label("卸载应用", systemImage: "trash") }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(model.uninstallRaw.isEmpty)
            }

            if model.uninstallRaw.isEmpty {
                EmptyStateCard(icon: "doc.text.magnifyingglass", title: "尚未预览", text: "先查看 Mole 将删除的路径，确认无误后再执行。")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("卸载预览").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("默认移入废纸篓").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.accent)
                    }
                    ScrollView {
                        Text(model.uninstallRaw)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 180, maxHeight: 310)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            }

            if !model.uninstallResult.isEmpty {
                LogDisclosure(title: "本次卸载输出", text: model.uninstallResult, expanded: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

// MARK: - Analyze

private struct AnalyzeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "磁盘分析",
                    subtitle: "逐个文件夹查看真实占用",
                    trailing: AnyView(
                        HStack(spacing: 10) {
                            Button {
                                Task { await model.scanAnalyze(path: NSHomeDirectory()) }
                            } label: { Label("分析主目录", systemImage: "house") }
                                .buttonStyle(SecondaryButtonStyle())
                            Button {
                                model.chooseFolder()
                            } label: { Label("选择文件夹", systemImage: "folder") }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    )
                )

                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.amber)
                    Text(model.analysisPath).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Spacer()
                    Text(model.analysisStatus).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))

                if let analysis = model.analysis {
                    HStack(spacing: 14) {
                        SummaryStat(title: "总占用", value: formatBytes(analysis.totalSize), icon: "externaldrive", color: Theme.amber)
                        SummaryStat(title: "文件数量", value: "\(analysis.totalFiles ?? 0)", icon: "doc.on.doc", color: Theme.blue)
                        SummaryStat(title: "扫描状态", value: analysis.scanStatus == "complete" ? "完成" : "部分完成", icon: "checkmark.circle", color: Theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("占用排行").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            Text("点击文件夹继续深入").font(.system(size: 9)).foregroundStyle(Theme.tertiary)
                        }
                        ForEach(Array(analysis.entries.sorted { $0.size > $1.size }.prefix(12))) { entry in
                            Button {
                                if entry.isDir { Task { await model.scanAnalyze(path: entry.path) } }
                                else { model.revealInFinder(entry.path) }
                            } label: {
                                AnalyzeRow(entry: entry, maxSize: analysis.entries.map(\.size).max() ?? 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(17)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))

                    if let large = analysis.largeFiles, !large.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("大文件").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                            ForEach(large.prefix(8)) { file in
                                Button { model.revealInFinder(file.path) } label: {
                                    HStack {
                                        Image(systemName: "doc.fill").foregroundStyle(Theme.blue)
                                        Text(file.name).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                                        Spacer()
                                        Text(formatBytes(file.size)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.tertiary)
                                    }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(17)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
                    }
                } else {
                    EmptyStateCard(icon: "chart.pie", title: "选择一个目录", text: "分析主目录或选择任意文件夹。首次扫描可能需要一些时间，结果会显示真实占用排行。")
                }
            }
            .padding(28)
        }
    }
}

private struct AnalyzeRow: View {
    let entry: AnalyzeEntry
    let maxSize: Int64

    var body: some View {
        let ratio = maxSize > 0 ? Double(entry.size) / Double(maxSize) : 0
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: entry.isDir ? "folder.fill" : "doc.fill")
                    .font(.system(size: 10)).foregroundStyle(entry.isDir ? Theme.amber : Theme.blue)
                Text(entry.name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                Spacer()
                Text(formatBytes(entry.size)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                if entry.isDir {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.tertiary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.045))
                    Capsule().fill(entry.isDir ? Theme.amber.opacity(0.72) : Theme.blue.opacity(0.62))
                        .frame(width: max(3, proxy.size.width * CGFloat(ratio)))
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Whitelist

private struct WhitelistView: View {
    @ObservedObject var model: AppModel
    @State private var mode: WhitelistMode = .clean
    @State private var manualPattern = ""

    private var patterns: [String] { model.whitelist(for: mode) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "白名单",
                    subtitle: "保护重要路径，避免被清理或优化",
                    trailing: AnyView(
                        Button {
                            model.chooseWhitelistPath(mode: mode)
                        } label: { Label("选择文件或文件夹", systemImage: "folder.badge.plus") }
                            .buttonStyle(PrimaryButtonStyle())
                    )
                )

                SafetyNotice(
                    icon: "checkmark.shield",
                    title: "内置安全保护始终生效",
                    text: "白名单只增加保护，不会关闭 Mole 对系统目录、共享目录和危险路径的硬性防护。支持 ~、绝对路径和 * 通配符。"
                )

                HStack(spacing: 8) {
                    ForEach(WhitelistMode.allCases) { item in
                        Button {
                            mode = item
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item == .clean ? "sparkles" : "wrench.and.screwdriver")
                                Text(item.title)
                                Text("\(model.whitelist(for: item).count)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.white.opacity(0.07), in: Capsule())
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(mode == item ? Theme.text : Theme.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(mode == item ? Theme.cardStrong : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(mode == item ? Theme.border : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button {
                        model.loadWhitelists()
                    } label: { Label("重新读取", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(mode.explanation).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    HStack(spacing: 9) {
                        Image(systemName: "terminal").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        TextField("输入路径或通配符，例如 ~/Library/Caches/MyApp/*", text: $manualPattern)
                            .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text)
                            .onSubmit(addManual)
                        Button {
                            addManual()
                        } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                            .frame(width: 24, height: 24)
                            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Theme.cardStrong, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border))
                }

                if patterns.isEmpty {
                    EmptyStateCard(
                        icon: "checkmark.shield",
                        title: "还没有自定义规则",
                        text: "选择不想被清理的文件或文件夹，或手动输入通配符规则。"
                    )
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("保护规则").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text("\(patterns.count) 条").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.tertiary)
                        }
                        .padding(14)
                        Divider().overlay(Theme.border)
                        ForEach(Array(patterns.enumerated()), id: \.offset) { index, pattern in
                            HStack(spacing: 10) {
                                Image(systemName: pattern == "FINDER_METADATA" ? "tag" : "shield.lefthalf.filled")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(pattern == "FINDER_METADATA" ? Theme.blue : Theme.accent)
                                    .frame(width: 18)
                                Text(pattern)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    model.removeWhitelistPattern(pattern, mode: mode)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Theme.tertiary)
                                        .frame(width: 26, height: 24)
                                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            if index != patterns.count - 1 { Divider().overlay(Theme.border.opacity(0.55)) }
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
                }

                HStack(spacing: 10) {
                    Image(systemName: "doc.text").foregroundStyle(Theme.tertiary)
                    Text(mode.fileURL.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.openWhitelistFile(mode)
                    } label: { Label("用默认编辑器打开", systemImage: "arrow.up.forward.app") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(13)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            }
            .padding(28)
        }
        .defaultScrollAnchor(.top)
        .task { model.loadWhitelists() }
    }

    private func addManual() {
        if model.addWhitelistPattern(manualPattern, mode: mode) {
            manualPattern = ""
        }
    }
}

// MARK: - About

private struct AboutView: View {
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "关于",
                    subtitle: "Mole 的 macOS 图形界面",
                    trailing: AnyView(EmptyView())
                )

                HStack(alignment: .top, spacing: 20) {
                    appIcon
                    VStack(alignment: .leading, spacing: 7) {
                        Text(AppIdentity.name)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text("macOS 清理、卸载、优化与系统监控图形界面")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                        HStack(spacing: 8) {
                            infoBadge(label: "版本", value: AppIdentity.version)
                            infoBadge(label: "开发者", value: AppIdentity.developer)
                        }
                        .padding(.top, 3)
                    }
                    Spacer()
                }
                .padding(22)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 10).fill(Theme.cardStrong).frame(width: 36, height: 36)
                            .overlay(Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("项目仓库").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("查看源码、提交问题和获取后续更新").font(.system(size: 9)).foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                    }

                    Link(destination: AppIdentity.githubURL) {
                        HStack(spacing: 9) {
                            Image(systemName: "link").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                            Text("github.com/Dfm007/Mole-Desk")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Theme.cardStrong, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AppIdentity.githubURL.absoluteString, forType: .string)
                            copied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                copied = false
                            }
                        } label: {
                            Label(copied ? "已复制" : "复制链接", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Link(destination: AppIdentity.githubURL) {
                            Label("在浏览器中打开", systemImage: "safari")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Spacer()
                    }
                }
                .padding(18)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shippingbox").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.blue).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("内置运行环境").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        Text("Mole CLI 已打包在 Mole Desk 内部，不依赖外部 Mole 文件夹。清理白名单、历史记录和日志保存在当前用户目录。")
                            .font(.system(size: 10)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(15)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            }
            .padding(28)
        }
        .defaultScrollAnchor(.top)
    }

    private var appIcon: some View {
        Group {
            if let image = NSImage(named: "MoleIcon") {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "sparkles").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.accent)
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border))
    }

    private func infoBadge(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tertiary)
            Text(value).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.cardStrong, in: Capsule())
        .overlay(Capsule().stroke(Theme.border))
    }
}

// MARK: - History

private struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var selectedSession: HistorySession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "历史记录",
                    subtitle: "仅显示实际执行的操作，预览不会记录",
                    trailing: AnyView(
                        Button {
                            Task { await model.loadHistory() }
                        } label: { Label("刷新记录", systemImage: "arrow.clockwise") }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(model.historyLoading)
                    )
                )

                if let history = model.history, !history.sessions.isEmpty {
                    let sessions = history.sessions
                    HStack(spacing: 14) {
                        SummaryStat(title: "最近会话", value: "\(sessions.count)", icon: "clock", color: Theme.blue)
                        SummaryStat(title: "清理次数", value: "\(sessions.filter { $0.command.hasPrefix("clean") }.count)", icon: "sparkles", color: Theme.accent)
                        if let latest = sessions.first {
                            SummaryStat(title: "最近操作", value: commandTitle(latest.command), icon: "arrow.clockwise", color: Theme.amber)
                        }
                    }

                    VStack(spacing: 0) {
                        HStack {
                            Text("操作").frame(width: 130, alignment: .leading)
                            Text("开始时间").frame(width: 150, alignment: .leading)
                            Spacer()
                            Text("项目").frame(width: 60, alignment: .trailing)
                            Text("大小").frame(width: 80, alignment: .trailing)
                            Text("状态").frame(width: 70, alignment: .trailing)
                            Text("").frame(width: 14)
                        }
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 15).padding(.vertical, 11)
                        Divider().overlay(Theme.border)
                        ForEach(sessions) { session in
                            Button {
                                selectedSession = session
                                Task { await model.loadHistoryDetails(for: session) }
                            } label: {
                                HistoryRow(session: session)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if session.id != sessions.last?.id { Divider().overlay(Theme.border.opacity(0.6)) }
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
                } else if model.historyLoading {
                    LoadingCard(text: "正在读取历史记录…")
                } else {
                    EmptyStateCard(icon: "clock.arrow.circlepath", title: "暂无记录", text: "执行一次清理或优化后，记录会显示在这里。")
                }
            }
            .padding(28)
        }
        .task {
            if model.history == nil { await model.loadHistory() }
        }
        .sheet(item: $selectedSession) { session in
            HistoryDetailView(model: model, session: session)
        }
    }
}

private struct HistoryRow: View {
    let session: HistorySession

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(commandTitle(session.command)).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .frame(width: 130, alignment: .leading)
            Text(session.startedAt).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiary).frame(width: 150, alignment: .leading)
            Spacer()
            Text("\(session.items ?? 0)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary).frame(width: 60, alignment: .trailing)
            Text(session.size ?? "—").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary).frame(width: 80, alignment: .trailing)
            Text((session.failedTasks ?? 0) > 0 ? "有问题" : "完成")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle((session.failedTasks ?? 0) > 0 ? Theme.amber : Theme.accent)
                .frame(width: 70, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 14)
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var color: Color {
        if session.command.hasPrefix("clean") { return Theme.accent }
        if session.command.hasPrefix("optimize") { return Theme.blue }
        if session.command.hasPrefix("uninstall") { return Theme.red }
        return Theme.amber
    }
}

private struct HistoryDetailView: View {
    @ObservedObject var model: AppModel
    let session: HistorySession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commandTitle(session.command))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("执行明细 · \(session.startedAt)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.cardStrong, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                SummaryStat(title: "处理项目", value: "\(session.items ?? 0)", icon: "doc.on.doc", color: Theme.accent)
                SummaryStat(title: "释放空间", value: session.size ?? "—", icon: "externaldrive", color: Theme.blue)
                SummaryStat(title: "文件明细", value: "\(model.historyDetails.count)", icon: "list.bullet.rectangle", color: Theme.amber)
            }

            Text("仅显示删除、移入废纸篓、重建和失败等实际变更项。")
                .font(.system(size: 9))
                .foregroundStyle(Theme.tertiary)

            Divider().overlay(Theme.border)

            if model.historyDetailsLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text("正在读取文件明细…").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer()
                }
                .padding(16)
            } else if let error = model.historyDetailsError, model.historyDetails.isEmpty {
                EmptyStateCard(icon: "doc.text.magnifyingglass", title: "没有可用明细", text: error)
            } else if model.historyDetails.isEmpty {
                EmptyStateCard(icon: "doc.text.magnifyingglass", title: "没有可用明细", text: "这次操作没有记录文件路径，或日志已经轮转。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.historyDetails) { entry in
                            HistoryFileRow(entry: entry)
                            if entry.id != model.historyDetails.last?.id {
                                Divider().overlay(Theme.border.opacity(0.55))
                            }
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            }
        }
        .padding(22)
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.background)
    }
}

private struct HistoryFileRow: View {
    let entry: HistoryFileEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(actionColor)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.actionTitle)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(actionColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(actionColor.opacity(0.09), in: Capsule())
                    Spacer()
                    Text(entry.timestamp)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                }
                Text(entry.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    private var actionColor: Color {
        switch entry.action {
        case "REMOVED", "TRASHED":
            return Theme.accent
        case "REBUILT":
            return Theme.blue
        case "FAILED", "TASK_FAILED":
            return Theme.amber
        default:
            return Theme.secondary
        }
    }
}

private func commandTitle(_ raw: String) -> String {
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

// MARK: - Shared components

private struct PageHeader: View {
    let title: String
    let subtitle: String
    let trailing: AnyView

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            trailing
        }
    }
}

private struct SafetyNotice: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.16)))
    }
}

private struct SummaryStat: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.13)).frame(width: 38, height: 38)
                .overlay(Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tertiary)
                Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
    }
}

private struct EmptyStateCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.accent.opacity(0.8))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Text(text).font(.system(size: 10.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(24)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

private struct LoadingCard: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small).tint(Theme.accent)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Spacer()
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
    }
}

private struct ErrorCard: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.secondary).textSelection(.enabled)
            Spacer()
        }
        .padding(16)
        .background(Theme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.amber.opacity(0.16)))
    }
}

private struct LogDisclosure: View {
    let title: String
    let text: String
    var expanded = false
    @State private var isExpanded: Bool

    init(title: String, text: String, expanded: Bool = false) {
        self.title = title
        self.text = text
        self.expanded = expanded
        self._isExpanded = State(initialValue: expanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView {
                Text(text).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.top, 8)
            }
            .frame(maxHeight: 330)
        } label: {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(red: 0.04, green: 0.10, blue: 0.07))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
            .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Theme.cardStrong.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
            .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.red)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Theme.red.opacity(configuration.isPressed ? 0.13 : 0.09), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.red.opacity(0.18)))
            .opacity(isEnabled ? 1 : 0.38)
    }
}

// MARK: - App entry

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.isRestorable = false }
        }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else { return }
        let path = args[index + 1]
        let delay: TimeInterval
        if let delayIndex = args.firstIndex(of: "--snapshot-delay"), args.indices.contains(delayIndex + 1),
           let requested = Double(args[delayIndex + 1]) {
            delay = requested
        } else {
            delay = 18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.captureSnapshot(to: path)
        }
    }

    private func captureSnapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
              let view = window.contentView else {
            NSApp.terminate(nil)
            return
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        if let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: representation)
            if let data = representation.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        NSApp.terminate(nil)
    }
}

@main
struct MoleDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Mole Desk") {
            RootView()
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 780)
    }
}
