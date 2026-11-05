import AppKit
import Foundation
import SwiftUI

extension AppModel {
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
}
