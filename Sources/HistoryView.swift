import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - History

struct HistoryView: View {
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

struct HistoryRow: View {
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

struct HistoryDetailView: View {
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

struct HistoryFileRow: View {
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
