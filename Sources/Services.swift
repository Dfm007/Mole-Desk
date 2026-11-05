import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

// MARK: - Paths and process runner

enum MolePaths {
    static let root: String = {
        let resources = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        return resources.appendingPathComponent("Mole").path
    }()

    static var entry: URL { URL(fileURLWithPath: root).appendingPathComponent("mole") }
    static var status: URL { URL(fileURLWithPath: root).appendingPathComponent("bin/status-go") }
    static var analyze: URL { URL(fileURLWithPath: root).appendingPathComponent("bin/analyze-go") }
    static var history: URL { URL(fileURLWithPath: root).appendingPathComponent("bin/history.sh") }
    static var askpass: URL {
        let resources = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        return resources.appendingPathComponent("bin/mole-askpass")
    }
    static var fastUninstall: URL {
        let resources = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        return resources.appendingPathComponent("bin/mole-uninstall-fast")
    }
}

struct CommandResult: Sendable {
    let output: String
    let status: Int32
    let timedOut: Bool
}

enum Runner {
    static func run(
        _ executable: URL,
        _ arguments: [String],
        extraEnvironment: [String: String] = [:],
        input: String? = nil,
        timeout: TimeInterval = 600,
        onOutput: ((String) -> Void)? = nil
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: MolePaths.root)

                var environment = ProcessInfo.processInfo.environment
                let shimPath = Bundle.main.resourceURL?.appendingPathComponent("bin").path ?? ""
                environment["PATH"] = (shimPath.isEmpty ? "" : shimPath + ":") + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                environment["MOLE_LANG"] = "zh_CN"
                environment["NO_COLOR"] = "1"
                environment["TERM"] = "dumb"
                for (key, value) in extraEnvironment {
                    environment[key] = value
                }
                process.environment = environment

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                if let input {
                    let inputPipe = Pipe()
                    process.standardInput = inputPipe
                    do {
                        try process.run()
                        if let data = input.data(using: .utf8) {
                            inputPipe.fileHandleForWriting.write(data)
                        }
                        try? inputPipe.fileHandleForWriting.close()
                    } catch {
                        continuation.resume(returning: CommandResult(output: error.localizedDescription, status: -1, timedOut: false))
                        return
                    }
                } else {
                    process.standardInput = FileHandle.nullDevice
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(returning: CommandResult(output: error.localizedDescription, status: -1, timedOut: false))
                        return
                    }
                }

                let lock = NSLock()
                var didTimeout = false
                let timeoutWork = DispatchWorkItem {
                    lock.lock()
                    if process.isRunning {
                        didTimeout = true
                    }
                    lock.unlock()
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

                let readGroup = DispatchGroup()
                let outputLock = NSLock()
                var collected = Data()

                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    var data = Data()
                    while true {
                        let chunk = pipe.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        data.append(chunk)
                        if let onOutput {
                            onOutput(String(decoding: chunk, as: UTF8.self))
                        }
                    }
                    outputLock.lock()
                    collected = data
                    outputLock.unlock()
                    readGroup.leave()
                }

                process.waitUntilExit()
                readGroup.wait()
                timeoutWork.cancel()

                lock.lock()
                let timedOut = didTimeout
                lock.unlock()

                outputLock.lock()
                let data = collected
                outputLock.unlock()

                let output = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                continuation.resume(returning: CommandResult(output: output, status: process.terminationStatus, timedOut: timedOut))
            }
        }
    }
}
