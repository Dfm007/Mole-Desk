import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Whitelist

struct WhitelistView: View {
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
