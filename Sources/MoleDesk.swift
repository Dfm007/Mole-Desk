import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - App entry

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.isRestorable = false }
        }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else { return }
        let path = args[index + 1]
        let delay: TimeInterval
        if let delayIndex = args.firstIndex(of: "--snapshot-delay"), args.indices.contains(delayIndex + 1),
           let requested = Double(args[delayIndex + 1]) {
            delay = requested
        } else {
            delay = 18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.captureSnapshot(to: path)
        }
    }

    private func captureSnapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
              let view = window.contentView else {
            NSApp.terminate(nil)
            return
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        if let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: representation)
            if let data = representation.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        NSApp.terminate(nil)
    }
}

@main
struct MoleDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Mole Desk") {
            RootView()
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 780)
    }
}
