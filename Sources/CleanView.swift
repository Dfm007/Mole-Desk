import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Clean

struct CleanView: View {
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

struct WhitelistPreviewBadge: View {
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
