import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Root views

struct RootView: View {
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

struct DeterminateProgressBar: View {
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

struct IndeterminateProgressBar: View {
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

struct SidebarView: View {
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
