import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Theme

enum Theme {
    static let background = Color(red: 0.035, green: 0.050, blue: 0.045)
    static let sidebar = Color(red: 0.050, green: 0.070, blue: 0.062)
    static let card = Color.white.opacity(0.055)
    static let cardStrong = Color.white.opacity(0.082)
    static let border = Color.white.opacity(0.085)
    static let accent = Color(red: 0.48, green: 0.88, blue: 0.66)
    static let accentSoft = Color(red: 0.30, green: 0.65, blue: 0.48)
    static let blue = Color(red: 0.42, green: 0.69, blue: 0.98)
    static let amber = Color(red: 0.98, green: 0.72, blue: 0.34)
    static let red = Color(red: 0.96, green: 0.43, blue: 0.43)
    static let text = Color(red: 0.94, green: 0.96, blue: 0.94)
    static let secondary = Color(red: 0.65, green: 0.72, blue: 0.68)
    static let tertiary = Color(red: 0.45, green: 0.52, blue: 0.48)
}

enum AppIdentity {
    static let name = "Mole Desk"
    static let developer = "Dfm007"
    static let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.3"
    static let githubURL = URL(string: "https://github.com/Dfm007/Mole-Desk")!
}
