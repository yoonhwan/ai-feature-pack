// AIRAG.app: menu-bar app that runs the consumer tick (one pass) every 5 minutes.
// The child is started directly with Process (no shell, no launchctl, no `open`), so that the app stays the
// responsible process for every "other apps' data" request the tick and its `op` grandchild make.
// Section 1 is pure logic (tested by macos/AIRAGTests/main.swift, built with -D AIRAG_TEST); section 2 is the app.
// Nothing here prints a key or a token; the log line parser keeps only fixed-shape status words.

import Foundation

// MARK: - 1. Pure logic

struct TickStatus: Equatable {
    var ts: Date?
    var status: String
    var code: String?
}

enum Light: Equatable { case green, yellow, red, gray }

/// A pass older than this turns the icon red (the loop is silently dead).
let staleAfterSeconds: TimeInterval = 900
let passIntervalSeconds: TimeInterval = 300
let killGraceSeconds: TimeInterval = 10
let appBundleID = "com.byourz.airag"

private let wordCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")

/// Status and code are shown in a menu: keep only short fixed-shape words, never free text.
func safeWord(_ raw: String) -> String? {
    guard !raw.isEmpty, raw.count <= 48, raw.unicodeScalars.allSatisfy({ wordCharacters.contains($0) }) else { return nil }
    return raw
}

/// `2026-10-18T00:45:17.319231+00:00` -> Date (the fractional part has 6 digits, which ISO8601DateFormatter rejects).
func parseTickTimestamp(_ text: String) -> Date? {
    var t = text
    if let dot = t.firstIndex(of: ".") {
        var end = t.index(after: dot)
        while end < t.endIndex, t[end].isASCII, t[end].isNumber { end = t.index(after: end) }
        t.removeSubrange(dot..<end)
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: t)
}

/// Last non-empty line of a tick log chunk -> status. A line that is not a JSON object with a safe `status` gives nil.
func parseLastLogLine(_ text: String) -> TickStatus? {
    let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        .map { $0.trimmingCharacters(in: .whitespaces) }
    guard let line = lines.last(where: { !$0.isEmpty }),
          let data = line.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let rawStatus = object["status"] as? String, let status = safeWord(rawStatus) else { return nil }
    let code = (object["code"] as? String).flatMap(safeWord)
    let ts = (object["ts"] as? String).flatMap(parseTickTimestamp)
    return TickStatus(ts: ts, status: status, code: code)
}

/// Icon colour. Gray = stopped. Red = bad status, or no pass for more than 15 minutes (K4).
/// The staleness clock never starts before the app itself started, so an old log line does not turn a fresh app red.
func lightFor(last: TickStatus?, now: Date, appStart: Date, stopped: Bool) -> Light {
    if stopped { return .gray }
    let reference = max(last?.ts ?? .distantPast, appStart)
    if now.timeIntervalSince(reference) > staleAfterSeconds { return .red }
    guard let last = last else { return .yellow }
    switch last.status {
    case "ok": return .green
    case "skipped", "degraded": return .yellow
    default: return .red
    }
}

func statusLine(last: TickStatus?, now: Date, light: Light, running: Bool, stopped: Bool, launchFailed: Bool,
                timeZone: TimeZone = .current) -> String {
    var parts: [String] = []
    if stopped { parts.append("정지됨") } else if running { parts.append("패스 실행 중") }
    if launchFailed { parts.append("tick 실행 실패 (python 경로 확인)") }
    if let last = last {
        var text = last.status
        if let code = last.code { text += " (\(code))" }
        if let ts = last.ts {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm:ss"
            parts.append("마지막 패스 \(formatter.string(from: ts)), \(text)")
        } else {
            parts.append("마지막 패스 시각 없음, \(text)")
        }
    } else {
        parts.append("아직 패스 기록 없음")
    }
    if light == .red && !stopped && !launchFailed && last != nil { parts.append("15분 넘게 멈춤 또는 실패") }
    return parts.joined(separator: " / ")
}

enum PathCheck: Equatable {
    case ok
    case translocated
    case wrongLocation
}

/// The app must run from ~/Applications/AIRAG.app; anywhere else (Downloads, a translocated copy) may change its identity (K8).
func checkAppPath(bundlePath: String, home: String) -> PathCheck {
    if bundlePath.contains("/AppTranslocation/") { return .translocated }
    let expected = URL(fileURLWithPath: home).appendingPathComponent("Applications/AIRAG.app").standardizedFileURL.path
    let actual = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
    return actual == expected ? .ok : .wrongLocation
}

struct AppSettings: Equatable {
    var python: String
    var config: String
    var credentials: String
    var logDir: String
}

/// Defaults are the paths of the installed consumer (design G3). `~/.config/airag/app.json` may override any of the four
/// keys `python`, `config`, `credentials`, `log_dir`; a non-string, empty, or non-absolute value is ignored.
func resolveSettings(home: String, json: Data?) -> AppSettings {
    var settings = AppSettings(
        python: home + "/.local/share/airag/runtime/bin/python",
        config: home + "/.local/share/airag/projects/ai-feature-pack/runtime.json",
        credentials: home + "/.config/airag/credential-source.json",
        logDir: home + "/.local/share/airag/logs")
    guard let json = json, let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return settings }
    func pick(_ key: String) -> String? {
        guard var value = object[key] as? String, !value.isEmpty else { return nil }
        if value.hasPrefix("~/") { value = home + "/" + value.dropFirst(2) }
        return value.hasPrefix("/") ? value : nil
    }
    if let v = pick("python") { settings.python = v }
    if let v = pick("config") { settings.config = v }
    if let v = pick("credentials") { settings.credentials = v }
    if let v = pick("log_dir") { settings.logDir = v }
    return settings
}

/// Same argument list as the launchd plist template (design G3).
func tickArguments(_ settings: AppSettings) -> [String] {
    ["-m", "airag_consumer.tick", "--config", settings.config, "--credentials", settings.credentials,
     "--log-dir", settings.logDir]
}

/// Newest-first list of `tick-YYYYMMDD.log` names (the day file rolls over at midnight; `tick.lock` and others are skipped).
func tickLogNamesNewestFirst(_ names: [String]) -> [String] {
    names.filter { name in
        guard name.hasPrefix("tick-"), name.hasSuffix(".log") else { return false }
        let middle = name.dropFirst(5).dropLast(4)
        return middle.count == 8 && middle.allSatisfy { $0.isASCII && $0.isNumber }
    }.sorted(by: >)
}

protocol Cancellable { func cancel() }

/// Start / stop / pass loop with injected clock, child launcher and signal sender, so K5 is testable without a child.
/// Main-thread only. Stop = cancel the next pass + SIGTERM to the running child, SIGKILL after the grace (K5).
final class PassController {
    enum State: Equatable { case stopped, waiting, running }

    private(set) var state: State = .stopped
    private(set) var pid: Int32?
    private(set) var lastLaunchFailed = false
    var onChange: () -> Void = {}

    private let interval: TimeInterval
    private let killGrace: TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Cancellable
    /// Starts one tick; `onExit` must be called later (never inside `launch`). Returns the child pid, or nil if it did not start.
    private let launch: (@escaping () -> Void) -> Int32?
    private let signal: (Int32, Int32) -> Void
    private var nextPass: Cancellable?
    private var killTimer: Cancellable?

    init(interval: TimeInterval = passIntervalSeconds, killGrace: TimeInterval = killGraceSeconds,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Cancellable,
         launch: @escaping (@escaping () -> Void) -> Int32?,
         signal: @escaping (Int32, Int32) -> Void) {
        self.interval = interval
        self.killGrace = killGrace
        self.schedule = schedule
        self.launch = launch
        self.signal = signal
    }

    /// True while a stop was asked but the old child has not exited yet.
    var isStopping: Bool { state == .stopped && pid != nil }

    func start() {
        guard state == .stopped, pid == nil else { return }
        runPass()
    }

    func stop() {
        nextPass?.cancel()
        nextPass = nil
        state = .stopped
        if let child = pid, killTimer == nil {
            signal(child, SIGTERM)
            killTimer = schedule(killGrace) { [weak self] in
                guard let self = self, self.pid == child else { return }
                self.signal(child, SIGKILL)
            }
        }
        onChange()
    }

    private func runPass() {
        nextPass = nil
        state = .running
        if let child = launch({ [weak self] in self?.passFinished() }) {
            pid = child
            lastLaunchFailed = false
        } else {
            pid = nil
            lastLaunchFailed = true
            scheduleNext()
        }
        onChange()
    }

    private func passFinished() {
        pid = nil
        killTimer?.cancel()
        killTimer = nil
        if state == .running { scheduleNext() }
        onChange()
    }

    private func scheduleNext() {
        state = .waiting
        nextPass = schedule(interval) { [weak self] in
            guard let self = self, self.state == .waiting else { return }
            self.runPass()
        }
    }
}

// MARK: - 2. App

#if !AIRAG_TEST
import AppKit
import ServiceManagement

private final class DispatchCancellable: Cancellable {
    private let item: DispatchWorkItem
    init(_ item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
}

private func mainSchedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> Cancellable {
    let item = DispatchWorkItem(block: action)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    return DispatchCancellable(item)
}

private func loadSettings() -> AppSettings {
    let home = NSHomeDirectory()
    let path = home + "/.config/airag/app.json"
    var json: Data?
    if let handle = FileHandle(forReadingAtPath: path) {
        json = try? handle.read(upToCount: 4096)
        try? handle.close()
    }
    return resolveSettings(home: home, json: json)
}

/// The tick child: python run directly. stdout is dropped (the tick writes its own log line); stderr goes to
/// `app.err.log`, truncated every pass so it cannot grow.
private func makeTickProcess(_ settings: AppSettings, onTerminate: @escaping () -> Void) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: settings.python)
    process.arguments = tickArguments(settings)
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    let errPath = settings.logDir + "/app.err.log"
    let fd = open(errPath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
    process.standardError = fd >= 0 ? FileHandle(fileDescriptor: fd, closeOnDealloc: true) : FileHandle.nullDevice
    process.terminationHandler = { _ in onTerminate() }
    return process
}

/// `--once`: one tick, then exit with the tick's exit code. 65 s cap (SIGTERM, then SIGKILL after 5 s) keeps it under 70 s.
private func runOnce(_ settings: AppSettings) -> Int32 {
    let done = DispatchSemaphore(value: 0)
    let process = makeTickProcess(settings) { done.signal() }
    do { try process.run() } catch { return 69 }
    if done.wait(timeout: .now() + 65) == .success { return process.terminationStatus }
    process.terminate()
    if done.wait(timeout: .now() + 5) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        _ = done.wait(timeout: .now() + 5)
    }
    return 124
}

private func readNewestStatus(logDir: String) -> TickStatus? {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: logDir)) ?? []
    for name in tickLogNamesNewestFirst(names).prefix(3) {
        guard let handle = FileHandle(forReadingAtPath: logDir + "/" + name) else { continue }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { continue }
        let start = size > 65536 ? size - 65536 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { continue }
        if let status = parseLastLogLine(String(decoding: data, as: UTF8.self)) { return status }
    }
    return nil
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let appStart = Date()
    private var controller: PassController!
    private var statusItem: NSStatusItem!
    private let statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let warningItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var refreshTimer: Timer?
    private var quitting = false
    private var loginError = false

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        controller = PassController(
            schedule: mainSchedule,
            launch: { [settings] onExit in
                let process = makeTickProcess(settings) { DispatchQueue.main.async { onExit() } }
                do { try process.run() } catch { return nil }
                return process.processIdentifier
            },
            signal: { pid, sig in _ = kill(pid, sig) })
        controller.onChange = { [weak self] in self?.stateChanged() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        statusLineItem.isEnabled = false
        warningItem.isEnabled = false
        warningItem.isHidden = true
        startItem = NSMenuItem(title: "시작", action: #selector(startPressed), keyEquivalent: "")
        stopItem = NSMenuItem(title: "정지", action: #selector(stopPressed), keyEquivalent: "")
        loginItem = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLogin), keyEquivalent: "")
        let logsItem = NSMenuItem(title: "로그 폴더 열기", action: #selector(openLogs), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "종료", action: #selector(quitPressed), keyEquivalent: "q")
        for item in [startItem!, stopItem!, loginItem!, logsItem, quitItem] { item.target = self }
        for item in [statusLineItem, warningItem, .separator(), startItem!, stopItem!, .separator(), loginItem!,
                     logsItem, .separator(), quitItem] { menu.addItem(item) }
        statusItem.menu = menu
        switch checkAppPath(bundlePath: Bundle.main.bundlePath, home: NSHomeDirectory()) {
        case .ok: break
        case .translocated, .wrongLocation:
            warningItem.title = "경고: ~/Applications/AIRAG.app 에서 실행해야 합니다"
            warningItem.isHidden = false
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        controller.start()
        refresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true
        controller.stop()
        return controller.pid == nil ? .terminateNow : .terminateLater
    }

    private func stateChanged() {
        if quitting, controller.pid == nil { NSApp.reply(toApplicationShouldTerminate: true) }
        refresh()
    }

    private func refresh() {
        let last = readNewestStatus(logDir: settings.logDir)
        let stopped = controller.state == .stopped
        let now = Date()
        let light = lightFor(last: last, now: now, appStart: appStart, stopped: stopped)
        var line = statusLine(last: last, now: now, light: light, running: controller.state == .running,
                              stopped: stopped, launchFailed: controller.lastLaunchFailed)
        if controller.isStopping { line = "정지 중 (도는 패스를 끝내는 중) / " + line }
        statusLineItem.title = line
        startItem.isEnabled = controller.state == .stopped && controller.pid == nil
        stopItem.isEnabled = controller.state != .stopped
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.title = loginError ? "로그인 시 실행 (변경 실패)" : "로그인 시 실행"
        let color: NSColor
        switch light {
        case .green: color = .systemGreen
        case .yellow: color = .systemYellow
        case .red: color = .systemRed
        case .gray: color = .secondaryLabelColor
        }
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "●", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 14)])
    }

    @objc private func startPressed() { controller.start() }
    @objc private func stopPressed() { controller.stop() }
    @objc private func quitPressed() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
            loginError = false
        } catch {
            loginError = true
        }
        refresh()
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: settings.logDir, isDirectory: true))
    }
}

@main
enum AIRAGMain {
    static func main() {
        let settings = loadSettings()
        if CommandLine.arguments.contains("--once") { exit(runOnce(settings)) }
        let app = NSApplication.shared
        let delegate = AppDelegate(settings: settings)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
#endif
