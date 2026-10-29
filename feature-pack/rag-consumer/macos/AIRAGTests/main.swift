// Pure-logic tests for AIRAG.swift (build: swiftc -D AIRAG_TEST AIRAG.swift main.swift; see build.sh `test`).
// No child process, no sleep, no file or network access: the clock, launcher and signal sender are fakes.
// Counterexamples pinned here: K4 (silent stop -> red), K5 (stop leaves a running tick), K8 (wrong app location).

import Foundation

var failures = 0
var total = 0

func check(_ condition: Bool, _ name: String, line: Int = #line) {
    total += 1
    if !condition {
        failures += 1
        print("FAIL \(name) (line \(line))")
    }
}

let t0 = parseTickTimestamp("2026-10-29T10:00:00+00:00")!
func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

// --- timestamp and log line parsing
check(parseTickTimestamp("2026-10-18T00:45:17.319231+00:00") == parseTickTimestamp("2026-10-18T00:45:17+00:00"),
      "6-digit fraction is ignored")
check(parseTickTimestamp("not a time") == nil, "bad timestamp is nil")

let okLine = #"{"exit":0,"probe":{"x":1},"status":"ok","ts":"2026-10-29T10:00:00.5+00:00"}"#
let okStatus = parseLastLogLine(okLine)
check(okStatus?.status == "ok" && okStatus?.code == nil && okStatus?.ts == t0, "ok line")

let failLine = #"{"code":"OP_READ_UNAVAILABLE","exit":30,"status":"key_error","ts":"2026-10-29T10:05:00+00:00"}"#
let failStatus = parseLastLogLine(failLine)
check(failStatus?.status == "key_error" && failStatus?.code == "OP_READ_UNAVAILABLE", "failure line keeps code")

check(parseLastLogLine(okLine + "\n" + failLine + "\n\n  \n")?.status == "key_error", "last non-empty line wins")
check(parseLastLogLine("") == nil, "empty text is nil")
check(parseLastLogLine("garbage") == nil, "garbage is nil")
check(parseLastLogLine(#"{"status":"ok""#) == nil, "cut line (tail chunk start) is nil")
check(parseLastLogLine("[1,2]") == nil, "non-object JSON is nil")
check(parseLastLogLine(#"{"exit":0}"#) == nil, "missing status is nil")
check(parseLastLogLine(#"{"status":"ok sk-abcdef secret"}"#) == nil, "free text in status is refused")
check(parseLastLogLine(#"{"status":"key_error","code":"a b"}"#)?.code == nil, "free text in code is dropped")
check(parseLastLogLine(#"{"status":"ok"}"#)?.ts == nil, "missing ts keeps status")

// --- K4: icon colour, silent stop
let appStart = at(0)
func light(_ status: String?, lastAt: TimeInterval?, now: TimeInterval, start: TimeInterval = 0, stopped: Bool = false) -> Light {
    let last = status.map { TickStatus(ts: lastAt.map(at), status: $0, code: nil) }
    return lightFor(last: last, now: at(now), appStart: at(start), stopped: stopped)
}
check(light("ok", lastAt: 0, now: 60) == .green, "fresh ok is green")
check(light("ok", lastAt: 0, now: 900) == .green, "exactly 15 min is still green")
check(light("ok", lastAt: 0, now: 901) == .red, "K4: ok older than 15 min is red")
check(light("skipped", lastAt: 0, now: 60) == .yellow, "skipped is yellow")
check(light("degraded", lastAt: 0, now: 60) == .yellow, "degraded is yellow")
check(light("key_error", lastAt: 0, now: 60) == .red, "key_error is red")
check(light("internal_error", lastAt: 0, now: 60) == .red, "internal_error is red")
check(light("brand_new_status", lastAt: 0, now: 60) == .red, "unknown status is red")
check(light("ok", lastAt: 0, now: 100_000, stopped: true) == .gray, "stopped is gray even when stale")
check(light(nil, lastAt: nil, now: 60) == .yellow, "no log yet, app young: yellow")
check(light(nil, lastAt: nil, now: 901) == .red, "K4: no log at all for 15 min is red")
check(light("ok", lastAt: -86_400, now: 60, start: 0) == .green, "old log line, app just started: not red yet")
check(light("ok", lastAt: -86_400, now: 901, start: 0) == .red, "old log line, loop dead for 15 min: red")
check(light("ok", lastAt: 10_000, now: 1000, start: 0) == .green, "log ts in the future is not stale")
check(light("ok", lastAt: nil, now: 901, start: 0) == .red, "status without ts is judged from app start")

// --- status line
let utc = TimeZone(identifier: "UTC")!
let lineOk = statusLine(last: TickStatus(ts: t0, status: "ok", code: nil), now: at(60), light: .green,
                        running: false, stopped: false, launchFailed: false, timeZone: utc)
check(lineOk == "마지막 패스 10:00:00, ok", "status line ok: \(lineOk)")
let lineFail = statusLine(last: TickStatus(ts: t0, status: "key_error", code: "OP_READ_UNAVAILABLE"), now: at(60),
                          light: .red, running: true, stopped: false, launchFailed: false, timeZone: utc)
check(lineFail.contains("패스 실행 중") && lineFail.contains("key_error (OP_READ_UNAVAILABLE)"), "status line shows status and code")
let lineStopped = statusLine(last: nil, now: at(60), light: .gray, running: false, stopped: true, launchFailed: false)
check(lineStopped == "정지됨 / 아직 패스 기록 없음", "status line stopped, no log")
check(statusLine(last: nil, now: at(60), light: .yellow, running: false, stopped: false, launchFailed: true).contains("tick 실행 실패"),
      "status line shows launch failure")
check(statusLine(last: TickStatus(ts: t0, status: "ok", code: nil), now: at(2000), light: .red, running: false,
                 stopped: false, launchFailed: false, timeZone: utc).contains("15분 넘게"), "status line explains stale red")

// --- K8: app location
let home = "/Users/tester"
check(checkAppPath(bundlePath: "/Users/tester/Applications/AIRAG.app", home: home) == .ok, "K8: ~/Applications is ok")
check(checkAppPath(bundlePath: "/Users/tester/Applications/AIRAG.app/", home: home) == .ok, "K8: trailing slash is ok")
check(checkAppPath(bundlePath: "/Users/tester/Applications/./AIRAG.app", home: home) == .ok, "K8: dot segment is ok")
check(checkAppPath(bundlePath: "/Users/tester/Downloads/AIRAG.app", home: home) == .wrongLocation, "K8: Downloads is wrong")
check(checkAppPath(bundlePath: "/Applications/AIRAG.app", home: home) == .wrongLocation, "K8: /Applications is wrong")
check(checkAppPath(bundlePath: "/Users/other/Applications/AIRAG.app", home: home) == .wrongLocation, "K8: other user's folder is wrong")
check(checkAppPath(bundlePath: "/Users/tester/Applications/AIRAG.app.zip/AIRAG.app", home: home) == .wrongLocation,
      "K8: lookalike path is wrong")
check(checkAppPath(bundlePath: "/private/var/folders/ab/T/AppTranslocation/1234-ABCD/d/AIRAG.app", home: home) == .translocated,
      "K8: translocated copy is named as such")
check(checkAppPath(bundlePath: "/Users/tester/Applications/AIRAG.app", home: "/Users/tester/") == .ok, "K8: home with trailing slash")

// --- settings and tick arguments (design G3)
let defaults = resolveSettings(home: home, json: nil)
check(tickArguments(defaults) == [
    "-m", "airag_consumer.tick",
    "--config", "/Users/tester/.local/share/airag/projects/ai-feature-pack/runtime.json",
    "--credentials", "/Users/tester/.config/airag/credential-source.json",
    "--log-dir", "/Users/tester/.local/share/airag/logs"], "default tick arguments match the plist")
check(defaults.python == "/Users/tester/.local/share/airag/runtime/bin/python", "default python")
let overridden = resolveSettings(home: home, json: Data(#"{"python":"~/rt/bin/python","log_dir":"/tmp/x","config":"relative/path","credentials":5}"#.utf8))
check(overridden.python == "/Users/tester/rt/bin/python", "override with ~ expansion")
check(overridden.logDir == "/tmp/x", "override absolute path")
check(overridden.config == defaults.config, "relative override is ignored")
check(overridden.credentials == defaults.credentials, "non-string override is ignored")
check(resolveSettings(home: home, json: Data("not json".utf8)) == defaults, "bad JSON gives defaults")
check(resolveSettings(home: home, json: Data(#"{"python":""}"#.utf8)) == defaults, "empty override is ignored")

// --- log file names
check(tickLogNamesNewestFirst(["tick.lock", "tick-20261018.log", "tick-20261029.log", "tick-2026102.log", "tick-2026102x.log",
                                "app.err.log", "launchd.out.log", "tick-20261017.log"])
      == ["tick-20261029.log", "tick-20261018.log", "tick-20261017.log"], "log names: newest first, junk skipped")
check(tickLogNamesNewestFirst([]).isEmpty, "log names: empty")

// --- K5: stop = cancel next pass + SIGTERM, SIGKILL after 10 s
final class FakeTimer: Cancellable {
    let delay: TimeInterval
    let action: () -> Void
    var cancelled = false
    init(_ delay: TimeInterval, _ action: @escaping () -> Void) { self.delay = delay; self.action = action }
    func cancel() { cancelled = true }
}

final class Rig {
    var timers: [FakeTimer] = []
    var launches = 0
    var exits: [() -> Void] = []
    var signals: [(Int32, Int32)] = []
    var launchResult: [Int32?] = []
    var changes = 0
    lazy var controller = PassController(
        interval: 300, killGrace: 10,
        schedule: { delay, action in
            let timer = FakeTimer(delay, action)
            self.timers.append(timer)
            return timer
        },
        launch: { onExit in
            self.launches += 1
            let pid = self.launchResult.isEmpty ? Int32(100 + self.launches) : self.launchResult.removeFirst()
            if pid != nil { self.exits.append(onExit) }
            return pid
        },
        signal: { pid, sig in self.signals.append((pid, sig)) })
    init() { controller.onChange = { self.changes += 1 } }
    func live(delay: TimeInterval) -> [FakeTimer] { timers.filter { $0.delay == delay && !$0.cancelled } }
}

do {
    let rig = Rig()
    rig.controller.start()
    check(rig.launches == 1 && rig.controller.state == .running && rig.controller.pid == 101, "start launches one pass")
    rig.controller.start()
    check(rig.launches == 1, "start while running does nothing")
    rig.controller.stop()
    check(rig.signals.count == 1 && rig.signals[0] == (101, SIGTERM), "K5: stop sends SIGTERM to the running child")
    check(rig.controller.state == .stopped && rig.controller.isStopping, "K5: stopping state while child lives")
    check(rig.live(delay: 10).count == 1, "K5: SIGKILL is scheduled for 10 s later")
    rig.controller.stop()
    check(rig.signals.count == 1, "K5: second stop does not signal again")
    rig.controller.start()
    check(rig.launches == 1, "K5: start is refused while the old child is still stopping")
    rig.live(delay: 10)[0].action()
    check(rig.signals.count == 2 && rig.signals[1] == (101, SIGKILL), "K5: child still alive after 10 s gets SIGKILL")
    rig.exits[0]()
    check(rig.controller.pid == nil && !rig.controller.isStopping, "child exit clears the stop")
    check(rig.live(delay: 300).isEmpty && rig.launches == 1, "K5: no next pass after stop")
    rig.controller.start()
    check(rig.launches == 2 && rig.controller.state == .running, "restart after stop launches a new pass")
}

do {
    let rig = Rig()
    rig.controller.start()
    rig.controller.stop()
    rig.exits[0]()  // child ends within the grace
    let kill = rig.timers.first { $0.delay == 10 }!
    check(kill.cancelled, "K5: kill timer is cancelled when the child exits in time")
    kill.action()
    check(rig.signals.count == 1, "K5: late kill timer does not send SIGKILL")
}

do {
    let rig = Rig()
    rig.controller.start()
    rig.exits[0]()
    check(rig.controller.state == .waiting && rig.live(delay: 300).count == 1, "pass end schedules the next pass in 300 s")
    let next = rig.live(delay: 300)[0]
    rig.controller.stop()
    check(next.cancelled && rig.signals.isEmpty, "K5: stop while waiting cancels the next pass, no signal")
    next.action()  // a timer that already fired must not launch
    check(rig.launches == 1 && rig.controller.state == .stopped, "K5: cancelled timer that fires anyway does not launch")
}

do {
    let rig = Rig()
    rig.controller.start()
    rig.exits[0]()
    rig.live(delay: 300)[0].action()
    check(rig.launches == 2 && rig.controller.state == .running, "timer fires the next pass")
}

do {
    let rig = Rig()
    rig.launchResult = [nil]
    rig.controller.start()
    check(rig.controller.lastLaunchFailed && rig.controller.state == .waiting && rig.live(delay: 300).count == 1,
          "launch failure waits and retries in 300 s")
    rig.live(delay: 300)[0].action()
    check(!rig.controller.lastLaunchFailed && rig.controller.state == .running, "retry after launch failure clears the flag")
}

do {
    let rig = Rig()
    rig.controller.stop()
    check(rig.signals.isEmpty && rig.controller.state == .stopped, "stop before start is harmless")
    check(rig.changes >= 1, "stop reports a change to the UI")
}

print("AIRAG tests: \(total - failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)
