import AppKit
import Foundation
import SwiftUI

extension AppModel {
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
}
