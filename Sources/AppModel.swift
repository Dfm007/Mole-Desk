import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Model

@MainActor
final class AppModel: ObservableObject {
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
    @Published var uninstallPreviewBaseRaw = ""
    @Published var uninstallResult = ""
    @Published var uninstallPreviewSummary: UninstallPreviewSummary?
    @Published var uninstallRemovesPersonalData = false

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

    var started = false
    var monitorTask: Task<Void, Never>?
    var cleanProgressTotal = 0
    var cleanProgressDone = 0
    var cleanProgressLabels: Set<String> = []
    var cleanDoneLabels: Set<String> = []
    var cleanProgressBuffer = ""
    var uninstallPreviewGeneration = 0
    var uninstallProgressTotal = 0
    var uninstallProgressDone = 0
    var uninstallProgressBuffer = ""

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
