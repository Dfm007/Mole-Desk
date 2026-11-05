import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Analyze

struct AnalyzeView: View {
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

struct AnalyzeRow: View {
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
