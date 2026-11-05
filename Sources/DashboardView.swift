import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "系统概览",
                    subtitle: "来自 Mole Status 的实时健康数据",
                    trailing: AnyView(
                        Button {
                            Task { await model.refreshStatus() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.isRefreshingStatus)
                    )
                )

                if let snapshot = model.status {
                    dashboardContent(snapshot)
                } else if let error = model.statusError {
                    ErrorCard(message: error)
                } else {
                    LoadingCard(text: "正在收集系统状态…")
                }
            }
            .padding(28)
        }
    }

    @ViewBuilder
    private func dashboardContent(_ snapshot: StatusSnapshot) -> some View {
        let cpu = snapshot.cpu?.usage ?? 0
        let memory = snapshot.memory?.usedPercent ?? 0
        let rootDisk = snapshot.disks?.first(where: { $0.mount == "/" }) ?? snapshot.disks?.first
        let disk = rootDisk?.usedPercent ?? 0
        let networkRate = (snapshot.network?.compactMap(\.rxRateMbs).reduce(0, +) ?? 0)
            + (snapshot.network?.compactMap(\.txRateMbs).reduce(0, +) ?? 0)

        HStack(spacing: 14) {
            HealthScoreCard(score: snapshot.healthScore ?? 0, message: snapshot.healthScoreMsg ?? "")
            MetricCard(title: "CPU", value: String(format: "%.0f%%", cpu), subtitle: "\(snapshot.cpu?.logicalCpu ?? 0) 逻辑核心", icon: "cpu", color: Theme.accent, progress: cpu / 100)
            MetricCard(title: "内存", value: formatPercent(memory), subtitle: "\(formatBytes(snapshot.memory?.used)) / \(formatBytes(snapshot.memory?.total))", icon: "memorychip", color: Theme.blue, progress: memory / 100)
            DiskMetricCard(
                percent: disk,
                total: rootDisk?.total ?? 0,
                used: rootDisk?.used ?? 0,
                available: max(0, (rootDisk?.total ?? 0) - (rootDisk?.used ?? 0)),
                filesystem: rootDisk?.fstype?.uppercased() ?? "系统盘"
            )
        }

        HStack(alignment: .top, spacing: 14) {
            ChartCard(title: "CPU 使用率", value: String(format: "%.1f%%", cpu), data: model.cpuHistory, color: Theme.accent)
            ChartCard(title: "内存压力", value: formatPercent(memory), data: model.memoryHistory, color: Theme.blue)
            ChartCard(title: "网络吞吐", value: String(format: "%.2f MB/s", networkRate), data: model.networkHistory, color: Theme.amber)
        }

        HStack(alignment: .top, spacing: 14) {
            TopProcessesCard(processes: Array((snapshot.topProcesses ?? []).prefix(6)))
            SystemDetailsCard(snapshot: snapshot)
        }
    }
}

struct HealthScoreCard: View {
    let score: Int
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("健康评分").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                        .stroke(
                            AngularGradient(colors: [Theme.accent, Theme.blue, Theme.accent], center: .center),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(score)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                        Text("分").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 7) {
                    Text(healthTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(message.isEmpty ? "系统运行状态" : message).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text("实时刷新").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(width: 260, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }

    private var healthTitle: String {
        switch score {
        case 85...: return "状态优秀"
        case 70..<85: return "总体良好"
        case 50..<70: return "需要关注"
        default: return "建议维护"
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                Spacer()
            }
            Text(value).font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.75)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.tertiary).lineLimit(1)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(color).frame(width: max(4, geometry.size.width * CGFloat(max(0, min(1, progress)))))
                }
            }
            .frame(height: 5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 137, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

struct DiskMetricCard: View {
    let percent: Double
    let total: UInt64
    let used: UInt64
    let available: UInt64
    let filesystem: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.amber)
                Text("磁盘").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(filesystem).font(.system(size: 8, weight: .medium)).foregroundStyle(Theme.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(percent.rounded()))%").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text("已用").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tertiary)
            }
            HStack(spacing: 8) {
                DiskCapacityValue(label: "总容量", value: formatBytes(total))
                DiskCapacityValue(label: "已用", value: formatBytes(used))
                DiskCapacityValue(label: "可用", value: formatBytes(available))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(Theme.amber).frame(width: max(4, geometry.size.width * CGFloat(max(0, min(1, percent / 100)))))
                }
            }
            .frame(height: 5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 137, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

struct DiskCapacityValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(Theme.tertiary)
            Text(value).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChartCard: View {
    let title: String
    let value: String
    let data: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(color)
            }
            if data.count > 1 {
                Chart(Array(data.enumerated()), id: \.offset) { item in
                    AreaMark(x: .value("时间", item.offset), y: .value(title, item.element))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("时间", item.offset), y: .value(title, item.element))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...max(1, (data.max() ?? 1) * 1.25))
                .frame(height: 78)
            } else {
                HStack {
                    Spacer()
                    Text("等待数据").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    Spacer()
                }
                .frame(height: 78)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Theme.border))
    }
}

struct TopProcessesCard: View {
    let processes: [TopProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("高占用进程").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text("CPU / 内存").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
            }
            ForEach(processes) { process in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.cardStrong).frame(width: 28, height: 28)
                        .overlay(Text(process.name?.prefix(1).uppercased() ?? "?").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(process.name ?? "未知进程").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text("PID \(process.pid ?? 0)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", process.cpu ?? 0)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle((process.cpu ?? 0) > 50 ? Theme.amber : Theme.secondary)
                    Text(formatBytes(process.memoryBytes)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiary).frame(width: 54, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

struct SystemDetailsCard: View {
    let snapshot: StatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统信息").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            InfoRow(label: "系统", value: snapshot.hardware?.osVersion ?? snapshot.platform ?? "—")
            InfoRow(label: "处理器", value: snapshot.hardware?.cpuModel ?? "—")
            InfoRow(label: "运行时间", value: snapshot.uptime ?? "—")
            InfoRow(label: "进程数", value: "\(snapshot.procs ?? 0)")
            InfoRow(label: "磁盘读写", value: String(format: "R %.1f / W %.1f MB/s", snapshot.diskIO?.readRate ?? 0, snapshot.diskIO?.writeRate ?? 0))
            if let battery = snapshot.batteries?.first {
                InfoRow(label: "电池", value: "\(Int(battery.percent ?? 0))% · \(battery.status ?? "")")
            }
            Divider().overlay(Theme.border)
            if let disks = snapshot.disks, !disks.isEmpty {
                ForEach(disks.prefix(4)) { disk in
                    HStack(spacing: 8) {
                        Image(systemName: (disk.mount == "/") ? "internaldrive" : "externaldrive")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary).frame(width: 14)
                        Text(disk.mount ?? disk.device ?? "—").font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                        Spacer()
                        Text(formatBytes(disk.total)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiary)
                        Text("\(Int((disk.usedPercent ?? 0).rounded()))%").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.amber)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }
}
