import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Optimize

struct OptimizeView: View {
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

struct OptimizePreviewView: View {
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

struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 9)).foregroundStyle(Theme.tertiary)
        }
    }
}

struct OptimizeAppliedBadge: View {
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
