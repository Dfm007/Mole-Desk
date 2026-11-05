import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Shared components

struct PageHeader: View {
    let title: String
    let subtitle: String
    let trailing: AnyView

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            trailing
        }
    }
}

struct SafetyNotice: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.16)))
    }
}

struct SummaryStat: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.13)).frame(width: 38, height: 38)
                .overlay(Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tertiary)
                Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.accent.opacity(0.8))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Text(text).font(.system(size: 10.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(24)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

struct LoadingCard: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small).tint(Theme.accent)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Spacer()
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
    }
}

struct ErrorCard: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.secondary).textSelection(.enabled)
            Spacer()
        }
        .padding(16)
        .background(Theme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.amber.opacity(0.16)))
    }
}

struct LogDisclosure: View {
    let title: String
    let text: String
    var expanded = false
    @State private var isExpanded: Bool

    init(title: String, text: String, expanded: Bool = false) {
        self.title = title
        self.text = text
        self.expanded = expanded
        self._isExpanded = State(initialValue: expanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView {
                Text(text).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.top, 8)
            }
            .frame(maxHeight: 330)
        } label: {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(red: 0.04, green: 0.10, blue: 0.07))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
            .opacity(isEnabled ? 1 : 0.38)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Theme.cardStrong.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
            .opacity(isEnabled ? 1 : 0.38)
    }
}

struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.red)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Theme.red.opacity(configuration.isPressed ? 0.13 : 0.09), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.red.opacity(0.18)))
            .opacity(isEnabled ? 1 : 0.38)
    }
}
