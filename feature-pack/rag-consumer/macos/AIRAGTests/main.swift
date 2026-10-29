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


// --- Pass controller, fake world (R2: the group, not the leader, decides when a pass is over)
final class FakeTimer: Cancellable {
    let delay: TimeInterval
    let action: () -> Void
    var cancelled = false
    var fired = false
    init(_ delay: TimeInterval, _ action: @escaping () -> Void) { self.delay = delay; self.action = action }
    func cancel() { cancelled = true }
}

/// A fake process world. `alive` = groups that still have members. TERM is ignored unless `termKills`;
/// KILL empties the group at once (the leader's exit callback still arrives later, by hand).
final class FakeOps: ProcessOps {
    var spawns = 0
    var exits: [(Int32) -> Void] = []
    var signals: [(Int32, Int32)] = []
    var spawnResult: [Int32?] = []
    var alive = Set<Int32>()
    var termKills = false
    var killKills = true
    func spawn(onExit: @escaping (Int32) -> Void) -> Int32? {
        spawns += 1
        let group = spawnResult.isEmpty ? Int32(100 + spawns) : spawnResult.removeFirst()
        if let group = group { alive.insert(group); exits.append(onExit) }
        return group
    }
    func signalGroup(_ pgid: Int32, _ sig: Int32) {
        signals.append((pgid, sig))
        if (sig == SIGTERM && termKills) || (sig == SIGKILL && killKills) { alive.remove(pgid) }
    }
    func groupAlive(_ pgid: Int32) -> Bool { alive.contains(pgid) }
}

final class Rig {
    var timers: [FakeTimer] = []
    let ops = FakeOps()
    var changes = 0
    lazy var controller = PassController(
        interval: 300, killGrace: 10, pollInterval: 0.2, cleanupGrace: 5,
        schedule: { delay, action in
            let timer = FakeTimer(delay, action)
            self.timers.append(timer)
            return timer
        },
        ops: ops)
    init() { controller.onChange = { self.changes += 1 } }
    func live(_ delay: TimeInterval) -> [FakeTimer] { timers.filter { $0.delay == delay && !$0.cancelled && !$0.fired } }
    func fire(_ timer: FakeTimer) { timer.fired = true; timer.action() }
    func signalCount(_ sig: Int32) -> Int { ops.signals.filter { $0.1 == sig }.count }
}

do {  // K5 on the group: stop = TERM to the group, KILL after the grace
    let rig = Rig()
    rig.controller.start()
    check(rig.ops.spawns == 1 && rig.controller.state == .running && rig.controller.group == 101, "start launches one pass")
    rig.controller.start()
    check(rig.ops.spawns == 1, "start while running does nothing")
    rig.controller.stop()
    check(rig.ops.signals.count == 1 && rig.ops.signals[0] == (101, SIGTERM), "K5: stop sends SIGTERM to the group")
    check(rig.controller.state == .stopped && rig.controller.isStopping, "K5: stopping while the group lives")
    check(rig.live(10).count == 1, "K5: SIGKILL is scheduled for 10 s later")
    rig.controller.stop()
    check(rig.signalCount(SIGTERM) == 1, "K5: second stop does not signal again")
    rig.controller.start()
    check(rig.ops.spawns == 1, "K5: start is refused while the group is still there")
    rig.fire(rig.live(10)[0])
    check(rig.ops.signals.last! == (101, SIGKILL), "K5: group still alive after 10 s gets SIGKILL")
    rig.ops.exits[0](9)
    check(rig.controller.group == nil && !rig.controller.isStopping, "group empty and leader gone clears the stop")
    check(rig.live(300).isEmpty && rig.ops.spawns == 1, "K5: no next pass after stop")
    rig.controller.start()
    check(rig.ops.spawns == 2 && rig.controller.state == .running, "restart after stop launches a new pass")
}

do {  // the whole group ends within the grace: the kill timer is cancelled
    let rig = Rig()
    rig.controller.start()
    rig.controller.stop()
    rig.ops.alive.remove(101)
    rig.ops.exits[0](15)
    let kill = rig.timers.first { $0.delay == 10 }!
    check(kill.cancelled, "kill timer is cancelled once the group is empty")
    rig.fire(kill)
    check(rig.signalCount(SIGKILL) == 0, "late kill timer sends no SIGKILL")
}

do {  // R2 direct cause: the leader exits, orphans stay; the kill timer must survive
    let rig = Rig()
    rig.controller.start()
    rig.controller.stop()
    rig.ops.exits[0](15)  // leader gone, group still has members
    check(rig.controller.group == 101 && rig.controller.isStopping, "R2: leader exit with orphans keeps the stop open")
    check(rig.live(10).count == 1, "R2: kill timer is not cancelled by the leader's exit")
    check(rig.live(0.2).count == 1, "R2: the group is polled after the leader is gone")
    rig.controller.start()
    check(rig.ops.spawns == 1, "R2: start is refused while orphans live")
    rig.fire(rig.live(10)[0])
    check(rig.signalCount(SIGKILL) == 1, "R2: orphans get SIGKILL after the grace")
    rig.fire(rig.live(0.2)[0])
    check(rig.controller.group == nil && rig.live(300).isEmpty, "R2: group empty ends the stop, no pass is scheduled")
    rig.controller.start()
    check(rig.ops.spawns == 2, "R2: start works once the group is empty")
}

do {  // orphan after a normal pass: draining until the group is empty, only then waiting
    let rig = Rig()
    rig.controller.start()
    rig.ops.exits[0](0)  // leader ends, a grandchild stays
    check(rig.controller.state == .draining, "R2: orphans make the pass draining")
    check(rig.signalCount(SIGTERM) == 1 && rig.ops.signals[0] == (101, SIGTERM), "R2: orphans get SIGTERM at once")
    check(rig.live(300).isEmpty, "R2: no next pass while draining")
    rig.controller.start()
    check(rig.ops.spawns == 1, "R2: start while draining does nothing")
    rig.fire(rig.live(0.2)[0])
    check(rig.controller.state == .draining && rig.live(0.2).count == 1, "R2: still alive, poll again")
    rig.ops.alive.remove(101)
    rig.fire(rig.live(0.2)[0])
    check(rig.controller.state == .waiting && rig.live(300).count == 1 && rig.controller.group == nil,
          "R2: waiting only after the group is empty")
}

do {  // stubborn orphan after a pass: KILL after the grace, then normal flow
    let rig = Rig()
    rig.controller.start()
    rig.ops.exits[0](0)
    rig.fire(rig.live(10)[0])
    check(rig.signalCount(SIGKILL) == 1 && !rig.ops.alive.contains(101), "R2: stubborn orphan gets SIGKILL")
    rig.fire(rig.live(0.2)[0])
    check(rig.controller.state == .waiting && rig.live(300).count == 1, "R2: next pass is scheduled after the orphan is gone")
}

do {  // stop while draining: no second TERM
    let rig = Rig()
    rig.controller.start()
    rig.ops.exits[0](0)
    rig.controller.stop()
    check(rig.signalCount(SIGTERM) == 1, "stop while draining does not send TERM again")
    check(rig.controller.state == .stopped && rig.controller.group == 101, "stop while draining stays stopping")
    rig.ops.alive.remove(101)
    rig.fire(rig.live(0.2)[0])
    check(rig.controller.group == nil && rig.live(300).isEmpty, "stop while draining: empty group ends it without a new pass")
}

do {  // cleanupFailed: SIGKILL did not empty the group
    let rig = Rig()
    rig.ops.killKills = false
    rig.controller.start()
    rig.controller.stop()
    rig.fire(rig.live(10)[0])
    check(rig.live(5).count == 1 && !rig.controller.cleanupFailed, "KILL sent, cleanup timer waits 5 s")
    rig.fire(rig.live(5)[0])
    check(rig.controller.cleanupFailed, "group survives KILL for 5 s: cleanupFailed")
    rig.controller.start()
    check(rig.ops.spawns == 1, "cleanupFailed keeps start disabled")
    rig.ops.alive.remove(101)
    rig.ops.exits[0](9)
    check(!rig.controller.cleanupFailed && rig.controller.group == nil, "cleanupFailed clears when the group finally empties")
    rig.controller.start()
    check(rig.ops.spawns == 2, "start works again after cleanupFailed cleared")
}

do {  // pass end schedules the next pass; stop cancels it; a timer that fires anyway does nothing
    let rig = Rig()
    rig.controller.start()
    rig.ops.alive.remove(101)
    rig.ops.exits[0](0)
    check(rig.controller.state == .waiting && rig.live(300).count == 1, "pass end schedules the next pass in 300 s")
    let next = rig.live(300)[0]
    rig.controller.stop()
    check(next.cancelled && rig.ops.signals.isEmpty, "K5: stop while waiting cancels the next pass, no signal")
    next.action()
    check(rig.ops.spawns == 1 && rig.controller.state == .stopped, "K5: cancelled timer that fires anyway does not launch")
}

do {
    let rig = Rig()
    rig.controller.start()
    rig.ops.alive.remove(101)
    rig.ops.exits[0](0)
    rig.fire(rig.live(300)[0])
    check(rig.ops.spawns == 2 && rig.controller.state == .running, "timer fires the next pass")
}

do {  // launch failure
    let rig = Rig()
    rig.ops.spawnResult = [nil]
    rig.controller.start()
    check(rig.controller.lastLaunchFailed && rig.controller.state == .waiting && rig.live(300).count == 1,
          "launch failure waits and retries in 300 s")
    rig.fire(rig.live(300)[0])
    check(!rig.controller.lastLaunchFailed && rig.controller.state == .running, "retry after launch failure clears the flag")
}

do {
    let rig = Rig()
    rig.controller.stop()
    check(rig.ops.signals.isEmpty && rig.controller.state == .stopped, "stop before start is harmless")
    check(rig.changes >= 1, "stop reports a change to the UI")
}

// --- R2 fuzz: any order of leader exit, stop, start, timers, and group emptying never starts or schedules a
// pass while a group still has members.
struct LCG {
    var state: UInt64
    mutating func next(_ n: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(n))
    }
}

do {
    var violations: [String] = []
    runs: for seed in 1...1500 {
        var rng = LCG(state: UInt64(seed))
        let rig = Rig()
        rig.ops.termKills = rng.next(3) == 0
        var leaderExited = Set<Int>()
        for step in 0..<14 {
            let event = rng.next(7)
            let spawnsBefore = rig.ops.spawns
            let blocked = !rig.ops.alive.isEmpty || rig.controller.group != nil
            switch event {
            case 0: rig.controller.stop()
            case 1: rig.controller.start()
            case 2:
                let pending = rig.timers.filter { !$0.cancelled && !$0.fired }
                if !pending.isEmpty { rig.fire(pending[rng.next(pending.count)]) }
            case 3:
                let dead = rig.timers.filter { $0.cancelled && !$0.fired }
                if !dead.isEmpty { let timer = dead[rng.next(dead.count)]; timer.fired = true; timer.action() }
            case 4:
                if let index = rig.ops.exits.indices.first(where: { !leaderExited.contains($0) }) {
                    leaderExited.insert(index)
                    rig.ops.exits[index](0)
                }
            case 5:
                if let index = leaderExited.first, rig.ops.alive.contains(Int32(101 + index)) { rig.ops.alive.remove(Int32(101 + index)) }
            default: break
            }
            let tag = "seed \(seed) step \(step) event \(event)"
            if !rig.ops.alive.isEmpty && !rig.live(300).isEmpty { violations.append("\(tag): pass scheduled while a group lives") }
            if !rig.ops.alive.isEmpty && rig.controller.state == .waiting { violations.append("\(tag): waiting while a group lives") }
            if rig.controller.state == .waiting && rig.controller.group != nil { violations.append("\(tag): waiting with a group") }
            if event == 1 && blocked && rig.ops.spawns != spawnsBefore { violations.append("\(tag): start while a group lives") }
            if violations.count >= 3 { break runs }
        }
    }
    for line in violations { print("FAIL R2 fuzz: \(line)") }
    total += 1
    if !violations.isEmpty { failures += 1 }
}

// --- Real processes (/bin/sh and sleep only). Every group is killed at the end of its test.
@discardableResult func pump(_ timeout: TimeInterval = 3, until condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() >= end { return false }
        if !RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) { Thread.sleep(forTimeInterval: 0.005) }
    }
    return true
}

let testEnvironment = ["PATH": "/usr/bin:/bin"]

final class RecordingOps: ProcessOps {
    let inner: LiveProcessOps
    var groups: [Int32] = []
    var signals: [(Int32, Int32)] = []
    init(script: String) {
        inner = LiveProcessOps(executable: "/bin/sh", arguments: ["-c", script], environment: testEnvironment, stderrPath: nil)
    }
    var spawnCount: Int { groups.count }
    func spawn(onExit: @escaping (Int32) -> Void) -> Int32? {
        let group = inner.spawn(onExit: onExit)
        if let group = group { groups.append(group) }
        return group
    }
    func signalGroup(_ pgid: Int32, _ sig: Int32) { signals.append((pgid, sig)); inner.signalGroup(pgid, sig) }
    func groupAlive(_ pgid: Int32) -> Bool { inner.groupAlive(pgid) }
    func reapAll() { for group in groups { inner.signalGroup(group, SIGKILL) } }
    func anyAlive() -> Bool { groups.contains { inner.groupAlive($0) } }
}

func liveController(_ script: String, killGrace: TimeInterval = 10) -> (PassController, RecordingOps) {
    let ops = RecordingOps(script: script)
    let controller = PassController(interval: 300, killGrace: killGrace, pollInterval: 0.05, cleanupGrace: 5,
                                    schedule: mainSchedule, ops: ops)
    return (controller, ops)
}

do {  // T-pg
    let ops = RecordingOps(script: "sleep 30")
    let group = ops.spawn { _ in }
    check(group != nil, "T-pg: spawn returns a pid")
    if let group = group {
        check(getpgid(group) == group, "T-pg: the child leads its own process group")
        check(ops.groupAlive(group), "T-pg: group is alive after spawn")
    }
    ops.reapAll()
    check(pump { !ops.anyAlive() }, "T-pg: test group is gone after SIGKILL")
    check(!ops.inner.groupAlive(0) && !ops.inner.groupAlive(1) && !ops.inner.groupAlive(-5), "T-pg: group numbers 0, 1, negative are never alive")
}

do {  // T-stop: a leader with a child; stop must empty the whole group before start is allowed
    let (controller, ops) = liveController("sleep 30 & sleep 30")
    var staleView = false
    controller.onChange = {
        if controller.group == nil, let last = ops.groups.last, ops.inner.groupAlive(last) { staleView = true }
    }
    controller.start()
    let group = controller.group
    check(group != nil && getpgid(group ?? 0) == group, "T-stop: pass started as a group leader")
    controller.stop()
    check(controller.isStopping, "T-stop: stopping right after stop()")
    controller.start()
    check(ops.spawnCount == 1, "T-stop: start refused while the group lives")
    check(pump { controller.group == nil }, "T-stop: controller idle within 3 s")
    check(group.map { !ops.groupAlive($0) } ?? false, "T-stop: whole group is empty when the controller is idle")
    check(!staleView, "T-stop: the controller never reported idle while the group had members")
    controller.start()
    check(ops.spawnCount == 2, "T-stop: start works after the group is empty")
    controller.stop()
    check(pump { controller.group == nil }, "T-stop: second stop ends too")
    ops.reapAll()
    check(pump { !ops.anyAlive() }, "T-stop: nothing left over")
}

do {  // T-kill: the whole group ignores TERM; only SIGKILL after the grace ends it
    let (controller, ops) = liveController("trap '' TERM; sleep 30 & sleep 30", killGrace: 0.5)
    controller.start()
    let begin = Date()
    controller.stop()
    check(pump { controller.group == nil }, "T-kill: group ended within 3 s")
    check(Date().timeIntervalSince(begin) >= 0.4, "T-kill: TERM-ignoring group lived through the grace")
    check(ops.signals.contains { $0.1 == SIGKILL }, "T-kill: SIGKILL was sent")
    ops.reapAll()
    check(pump { !ops.anyAlive() }, "T-kill: nothing left over")
}

do {  // T-kill-orphan: the leader exits by itself, a TERM-ignoring orphan stays
    let (controller, ops) = liveController("trap '' TERM; sleep 30 & exit 0", killGrace: 0.5)
    var seen: [PassController.State] = []
    var earlyWaiting = false
    controller.onChange = {
        seen.append(controller.state)
        if controller.state == .waiting, let last = ops.groups.last, ops.inner.groupAlive(last) { earlyWaiting = true }
    }
    controller.start()
    check(pump { controller.state == .waiting }, "T-kill-orphan: pass ends within 3 s")
    check(seen.contains(.draining), "T-kill-orphan: the pass went through draining")
    check(!earlyWaiting, "T-kill-orphan: waiting began only after the group was empty")
    check(ops.signals.contains { $0.1 == SIGKILL }, "T-kill-orphan: SIGKILL ended the TERM-ignoring orphan")
    controller.stop()
    ops.reapAll()
    check(pump { !ops.anyAlive() }, "T-kill-orphan: nothing left over")
}

do {  // T-orphan: a plain orphan is ended by the group TERM; waiting only after the group is empty
    let (controller, ops) = liveController("sleep 30 & exit 0")
    var seen: [PassController.State] = []
    var earlyWaiting = false
    controller.onChange = {
        seen.append(controller.state)
        if controller.state == .waiting, let last = ops.groups.last, ops.inner.groupAlive(last) { earlyWaiting = true }
    }
    controller.start()
    check(pump { controller.state == .waiting }, "T-orphan: pass ends within 3 s")
    check(seen.contains(.draining), "T-orphan: the leader's exit with a live child gives draining")
    check(!earlyWaiting, "T-orphan: waiting began only after the group was empty")
    controller.stop()
    ops.reapAll()
    check(pump { !ops.anyAlive() }, "T-orphan: nothing left over")
}

do {  // the live factory wires the tick command from the settings
    let settings = resolveSettings(home: "/Users/tester", json: nil)
    let ops = makeTickOps(settings, callbackQueue: .main)
    check(ops.executable == settings.python && ops.arguments == tickArguments(settings), "makeTickOps wires python and tick arguments")
    check(ops.stderrPath == "/Users/tester/.local/share/airag/logs/app.err.log", "makeTickOps puts stderr in app.err.log")
    check(ops.environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "makeTickOps sets PATH")
    check(makeLiveController(settings: settings).state == .stopped, "makeLiveController starts stopped")
}

print("AIRAG tests: \(total - failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)
