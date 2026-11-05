import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Uninstall

struct UninstallView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""

    private var filteredApps: [AppEntry] {
        if search.trimmingCharacters(in: .whitespaces).isEmpty { return model.apps }
        return model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.bundleId.localizedCaseInsensitiveContains(search)
                || $0.path.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "应用卸载",
                subtitle: "应用本体默认移入废纸篓，个人数据默认保留",
                trailing: AnyView(
                    Button {
                        Task { await model.loadApps(force: true) }
                    } label: { Label("刷新列表", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.appsLoading)
                )
            )

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
                TextField("搜索应用、Bundle ID 或路径", text: $search)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.text)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("已安装应用").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("\(filteredApps.count)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    }
                    .padding(14)
                    Divider().overlay(Theme.border)
                    if model.appsLoading && model.apps.isEmpty {
                        ProgressView().padding(30)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(filteredApps) { app in
                                    AppRow(app: app, selected: model.selectedApp?.id == app.id) {
                                        model.selectApp(app)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(width: 370)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))

                if let app = model.selectedApp {
                    UninstallDetailView(model: model, app: app)
                } else {
                    EmptyStateCard(icon: "trash.slash", title: "选择一个应用", text: "从左侧列表选择应用后，可先预览关联文件，再执行卸载。")
                }
            }
        }
        .padding(28)
        .task { await model.loadApps() }
    }
}

struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.accent.opacity(0.18) : Theme.cardStrong)
                    .frame(width: 34, height: 34)
                    .overlay(Text(app.name.prefix(1).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(selected ? Theme.accent : Theme.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(app.path).font(.system(size: 9)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.size).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary)
                    if app.source == "Homebrew" {
                        Text("Brew").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.blue)
                    }
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.cardStrong : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct UninstallDetailView: View {
    @ObservedObject var model: AppModel
    let app: AppEntry

    private var removePersonalDataBinding: Binding<Bool> {
        Binding(
            get: { model.uninstallRemovesPersonalData },
            set: { model.setUninstallRemovesPersonalData($0, for: app) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 13).fill(Theme.cardStrong).frame(width: 54, height: 54)
                    .overlay(Text(app.name.prefix(1).uppercased()).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.accent))
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                    Text(app.bundleId).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    Text(app.path).font(.system(size: 9)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                Spacer()
                Text(app.size).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Theme.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await model.previewUninstall(app) }
                } label: { Label("预览关联文件", systemImage: "doc.text.magnifyingglass") }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    model.requestUninstall(app)
                } label: { Label("卸载应用", systemImage: "trash") }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(model.uninstallRaw.isEmpty)
            }

            if model.uninstallRaw.isEmpty {
                EmptyStateCard(icon: "doc.text.magnifyingglass", title: "尚未预览", text: "先查看 Mole 将删除的路径，确认无误后再执行。")
            } else {
                if let summary = model.uninstallPreviewSummary {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            UninstallMetricTile(
                                title: "待移除项目",
                                value: "\(summary.pendingItemCount) 项",
                                icon: "trash",
                                color: Theme.red
                            )
                            UninstallMetricTile(
                                title: "个人数据",
                                value: "\(summary.personalDataCount) 项",
                                icon: "person.crop.circle",
                                color: summary.personalDataCount > 0 ? Theme.amber : Theme.accent
                            )
                            UninstallMetricTile(
                                title: "保留项目",
                                value: "\(summary.retainedCount) 项",
                                icon: "checkmark.shield",
                                color: summary.retainedCount > 0 ? Theme.blue : Theme.accent
                            )
                        }
                        Text(summary.breakdownText)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("卸载预览").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text(model.uninstallRemovesPersonalData ? "个人数据一并移除" : "默认保留个人数据")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(model.uninstallRemovesPersonalData ? Theme.red : Theme.accent)
                    }
                    ScrollView {
                        Text(model.uninstallRaw)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 140, maxHeight: 230)
                    Divider().overlay(Theme.border)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: removePersonalDataBinding) {
                            Text("不保留个人数据")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        .toggleStyle(.checkbox)
                        .tint(Theme.red)
                        Text("勾选后会重新生成预览，并将「保留的个人数据」一并移入废纸篓。受系统保护或与其他应用共享的数据仍会保留。")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 20)
                    }
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            }

            if !model.uninstallResult.isEmpty {
                LogDisclosure(title: "本次卸载输出", text: model.uninstallResult, expanded: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

struct UninstallMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardStrong, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}
