import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - About

struct AboutView: View {
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
