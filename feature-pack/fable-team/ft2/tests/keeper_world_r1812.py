"""r1812 ft2 keeper 시험 대역 — test_pi_keeper_r1812.py 가 부른다(시험 아님 · 이름에 test_ 없음).
임시 git 리포 2쌍(BYZ 대역 main·ops/main-base · 팩 대역 main) · 가짜 tmux(FT_TMUX · 세션 목록·capture 고정 · 호출 기록) ·
가짜 ft-seat-close·쪽지·reap(인자 기록 · rc 파일) · 주입 시계 · 임시 root 만 쓴다(실 tmux·명부·runtime 0).
"""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
OLD = FT2.parent / "legacy" / "1.x" / "harness"          # ⑤ 1.x 승계 도구 — 임시 cwd 에서 스텁과만 실행
T0, NOW, TEAM, AB = 1794000000.0, "2026-11-13T10:00:00", "harness", "ab" * 20
TEAMS = "| 팀 | 폴더 |\n|---|---|\n| harness | `$FT_HARNESS_ROOT/design/harness/` |\n| planner | `design/teams/planner/` |\n"
TMUX = r'''#!__PY__
import json, os, sys
st, a = os.environ["FAKE_TMUX"], sys.argv[1:]
d, name = json.load(open(st)), sys.argv[-1].lstrip("=").rstrip(":")  # r1822 pane 대상 `=이름:`
open(st + ".log", "a").write(json.dumps(a) + "\n")
if a[0] == "kill-session": d["alive"].remove(name); json.dump(d, open(st, "w"))
if a[0] == "capture-pane" and d.get("cap_rc"): sys.exit(d["cap_rc"])   # r2055 ㉒(마) capture 실패
if a[0] == "capture-pane": sys.stdout.write(d["pane"].get(name, ""))
if a[0] == "list-sessions": sys.stdout.write("".join(x + "\n" for x in d["alive"])); sys.exit(0)  # r1898 B3 바퀴당 1회
if a[0] == "has-session" and name not in d["alive"]: sys.stderr.write("can't find session: %s\n" % name)
if a[0] == "display-message" and "#{session_path}" in a[-1]:   # r2055 장기 좌석 jsonl 폴더(World.round 가 /seats/<이름> 세션 파일을 둠)
    t = a[a.index("-t") + 1].lstrip("=").rstrip(":"); sys.stdout.write(d.get("path", {}).get(t, "/seats/" + t) + "\n"); sys.exit(0 if t in d["alive"] else 1)
if a[0] == "display-message" and "#{pane_pid}" in a[-1]:   # r2055 A13 raw pane_pid · d["pid"][이름] = "pid\tcmd"(기본 100 pi · "" = 실패) · 죽은 세션 = rc1
    t = a[a.index("-t") + 1].lstrip("=").rstrip(":"); p = d.get("pid", {}).get(t, "100\tpi") if t in d["alive"] else None; sys.stdout.write((p or "") + "\n"); sys.exit(0 if p else 1)
if a[0] == "display-message" and "#{session_created}" in a[-1]:   # r2055 좌석 시작(기본 0 = 폴더 jsonl 전부)
    t = a[a.index("-t") + 1].lstrip("=").rstrip(":"); sys.stdout.write("%d\n" % d.get("born", {}).get(t, 0)); sys.exit(0 if t in d["alive"] else 1)
if a[0] == "display-message":   # r1839 #{session_attached} · 실제 tmux 처럼 `=이름`(콜론 없음)·없는 세션 = rc0 빈 줄
    t = a[a.index("-t") + 1]; sys.stdout.write("%s\n" % (d.get("att", {}).get(t[1:-1], 0) if t.endswith(":") and t[1:-1] in d["alive"] else "")); sys.exit(d.get("att_rc", 0))
sys.exit(0 if name in d["alive"] or a[0] == "kill-session" else 1)
'''
TMUXC = r'''#!__PY__
import json, os, re, sys
st = os.environ["FAKE_TMUX"]   # r2055 A13 tmuxc clean 대역 — .clean 파일 = 그 줄 그대로 · 없으면 살아 있는 세션 중 pane 끝 12줄(입력줄 제외)에 일함 근거 없는 세션
if os.path.exists(st + ".tmuxc_rc"): sys.exit(int(open(st + ".tmuxc_rc").read()))
if os.path.exists(st + ".clean"): sys.stdout.write(open(st + ".clean").read()); sys.exit(0)
d = json.load(open(st))
busy = lambda p: any(re.search("Working|esc to interrupt|[\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f]", x) for x in p.rstrip("\n").splitlines()[-12:] if not x.lstrip().startswith(("\u276f", "\u203a")))
sys.stdout.write("".join(x + "\n" for x in d["alive"] if not busy(d["pane"].get(x, ""))))
'''
PS = r'''#!__PY__
import os, sys
if sys.argv[1:] != ["-A", "-o", "pid=,ppid=,pcpu=,comm="]: os.execv("/bin/ps", ["ps"] + sys.argv[1:])   # r2055 A13 keeper settle 표만 가짜
st = os.environ["FAKE_TMUX"]
if os.path.exists(st + ".ps_rc"): sys.exit(int(open(st + ".ps_rc").read()))
sys.stdout.write(open(st + ".ps").read() if os.path.exists(st + ".ps") else "100 1 0.0 zsh\n101 100 0.0 pi\n")
'''
STUB = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\necho "STUB $1"\nexit "$(cat "$0.rc" 2>/dev/null || echo 0)"\n'
# 카드 ft2-done-seat-short-idle A4 — mbox 대역은 `peek --rows`(새 문)에만 머리줄을 답한다(`pending=` = `.pending` 파일 · 없으면 0).
# 옛 문(`peek <좌석>`)은 지금처럼 STUB 줄 = 설치된 옛 mbox 꼴(mail-unknown 그대로 · 다른 시험의 기대를 바꾸지 않는다).
MBOX = ('#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\n'
        'if [ "$1" = peek ] && [ "$3" = "--rows" ]; then echo "pending=$(cat "$0.pending" 2>/dev/null || echo 0) scanned=1 lineage=0"; '
        'exit "$(cat "$0.peekrc" 2>/dev/null || echo 0)"; fi\n'
        'echo "STUB $1"\nexit "$(cat "$0.rc" 2>/dev/null || echo 0)"\n')
def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)   # 기준판 = keeper.py 없음 → Red
    return module
def _git(cwd, *a):
    return subprocess.run(["git", "-C", str(cwd)] + list(a), capture_output=True, text=True, timeout=25, check=True).stdout.strip()
def _lines(path):
    return Path(str(path)).read_text(encoding="utf-8").splitlines() if Path(str(path)).exists() else []
def _put(path, body):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(body if isinstance(body, str) else json.dumps(body), encoding="utf-8")
class World:
    def __init__(s, tmp, mp, ft2=FT2, old=OLD):
        mp.setenv("FT_NOW", NOW)
        s.tmp, s.ft2, s.old, s.t, s.root, b = tmp, ft2, old, T0, tmp / "root", tmp / "bin"
        s.CLI = _mod(ft2 / "core" / "cli.py", "kc_%d" % id(s))
        for name in ("byz", "pack"):
            _git(tmp.parent, "init", "-q", "--bare", "-b", "main", str(tmp / (name + ".git")))
            _git(tmp, "init", "-q", "-b", "main", "seed-" + name)
            for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false"), ("remote.origin.url", str(tmp / (name + ".git")))):
                _git(tmp / ("seed-" + name), "config", k, v)
            s.commit(name, {"design/TEAMS.md": TEAMS}, "main")
        s.commit("byz", {}, "ops/main-base", new=True)
        _git(tmp, "clone", "-q", str(tmp / "byz.git"), "root"), _git(tmp, "clone", "-q", str(tmp / "pack.git"), "pack")
        lk = old / "bin" / "ft-land-kind-lib.sh"   # r2274 설치본 자리(<root>/.fable-team/bin) — ft2 사본 변이 시험도 같은 lib 를 읽는다
        lk.exists() and _put(s.root / ".fable-team" / "bin" / lk.name, lk.read_text(encoding="utf-8"))
        mp.setenv("FT2_PACK_REPO", str(tmp / "pack"))   # r2274 card_stage 착지 sha 찾기도 임시 팩만(실 팩 0)
        for name, body in (("tmux", TMUX.replace("__PY__", sys.executable)), ("tmuxc", TMUXC.replace("__PY__", sys.executable)), ("close", STUB), ("mbox", MBOX),
                           ("reap", '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n')):
            _put(b / name, body), (b / name).chmod(0o755)
        _put(tmp / "psbin" / "ps", PS.replace("__PY__", sys.executable)), (tmp / "psbin" / "ps").chmod(0o755)   # r2055 A13 가짜 ps(PATH · ps 만 있는 폴더)
        s.tm, s.close, s.mbox, s.state = b / "tmux.json", b / "close", b / "mbox", s.root / ".fable-team" / "state"
        _put(s.tm, {"alive": [], "pane": {}})
        s.env = dict(os.environ, FT_TMUX=str(b / "tmux"), FAKE_TMUX=str(s.tm), FT2_PACK_REPO=str(tmp / "pack"),
                     FT_SEAT_CLOSE_BIN=str(s.close), FT2_KEEPER_MBOX=str(s.mbox), FT_NOW=NOW,
                     FT2_PI_SESSIONS=str(tmp / "pi-sessions"), FT2_TMUXC=str(b / "tmuxc"), FT2_CLAUDE_PROJECTS=str(tmp / "claude-projects"),
                     PATH=str(tmp / "psbin") + os.pathsep + os.environ["PATH"])
        for team in (TEAM, "planner"):
            _put(s.root / ".fable-team" / ("seats-%s.json" % team), {"_master": "M-" + team})
        _put(s.state / "disk-alarm.log", ""), os.utime(s.state / "disk-alarm.log", (T0, T0))   # r2238 하루 정리 살아 있음(나이 0) = 생존 검사 줄·쪽지 0
    @property
    def K(s):
        return _mod(s.ft2 / "adapters" / "pi" / "keeper.py", "kp_%d" % id(s))
    def commit(s, name, files, branch, new=False):
        seed = s.tmp / ("seed-" + name)
        if _git(seed, "symbolic-ref", "--short", "HEAD") != branch:
            _git(seed, "checkout", "-q", *(["-b"] if new else []), branch)
        for rel, body in files.items():
            _put(seed / rel, body)
        _git(seed, "add", "-A"), _git(seed, "commit", "-q", "--allow-empty", "-m", "x"), _git(seed, "push", "-q", "origin", branch)
        return _git(seed, "rev-parse", "HEAD")
    def card(s, work, sha=None, stage="진행", folder="design/harness", refs=("main", "ops/main-base")):
        for ref in refs:
            s.commit("byz", {"%s/indices/%s/%s-x.md" % (folder, stage, work): "# 인덱스: %s\n- 상태: 대기\n- 남은 범위: 없음\n" % work
                             + ("- 착지: %s\n" % sha if sha else "")}, ref)
    def pack_sha(s):
        return s.commit("pack", {"p.txt": str(os.urandom(4))}, "main")
    def work(s, work, done=False, team=TEAM, intent=True, alive=False, pane="✻ Brewed for 3s\n❯ ", holder=None,
             seat=None, turn="stop"):
        """일 1개 = submit→assign→deliver(→complete) · intent(holder=seat) · Pi 세션 jsonl 마지막 줄 stopReason=turn(None=파일 0)."""
        holder = holder or "byz-%s-nano-%s-t#0" % (team, work)
        steps = [["submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work],
                 ["assign", "--work", work, "--holder", holder, "--evidence", "v1,v2"], ["deliver", "--work", work]]
        for argv in steps + ([["complete", "--work", work, "--attempt", "a1"]] if done else []):
            out, rc = s.CLI.run(argv + ["--root", str(s.root), "--team", team])
            assert rc == 0, out
        _put(s.state / "ft20-switch" / (team + ".json"), "{}")
        seat, tree = seat or holder, str(s.tmp / "wt" / work)
        if intent:
            body = {"FT2_HOLDER": seat, "state": "opened", "worktree": tree, "at": "2026-01-01T00:00:00"}
            _put(s.runtime(team) / "launch" / ("%s@a1.intent" % work), body)
        if turn:
            last = {"type": "message", "message": {"role": "assistant", "stopReason": turn}}
            log = Path(s.env["FT2_PI_SESSIONS"]) / ("--%s--" % tree.strip("/").replace("/", "-")) / "s.jsonl"
            _put(log, '{"type": "session"}\n' + json.dumps(last) + "\n")
            os.utime(log, (s.t - 7200, s.t - 7200))   # r2055 A6 닫기 = jsonl 무활동 ≥ PARK_IDLE(기본 2시간 쉼)
        d = json.loads(s.tm.read_text(encoding="utf-8"))
        d["alive"], d["pane"][seat] = d["alive"] + ([seat] if alive else []), pane
        return _put(s.tm, d) or seat
    def runtime(s, team=TEAM):
        return s.root / ".fable-team" / "teams" / team / "runtime"
    def journal(s, team=TEAM):
        return [json.loads(x) for p in sorted(s.runtime(team).glob("journal*.jsonl")) for x in _lines(p)]
    def kinds(s, kind, team=TEAM):
        return sum(rec["kind"] == kind for rec in s.journal(team))
    def keeper(s):
        return s.K.Keeper(str(s.root), env=s.env, now=lambda: s.t)
    def round(s, k=None):
        for seat in json.loads(s.tm.read_text(encoding="utf-8"))["alive"]:   # r2055 장기 좌석 세션 파일(/seats/<이름> · 없을 때만 · 2시간 쉼)
            log = Path(s.env["FT2_PI_SESSIONS"]) / ("--seats-%s--" % seat) / "s.jsonl"
            if not log.exists():
                _put(log, '{"type": "session"}\n'), os.utime(log, (s.t - 7200, s.t - 7200))
        k = k or s.keeper()
        assert k.run_once() == 0
        return k.lines
    def tmux(s, verb):
        return [a for a in map(json.loads, _lines(str(s.tm) + ".log")) if a[0] == verb]
    def succession(s, old, new, resume=True):
        """r2055 S2 — 후계 [레디] 영수(우편 로그) + 구 좌석 검증된 재개 기록 = 직전 세대 닫기 자격(hil.md)."""
        comm, rs = s.tmp / "comm", s.tmp / "resume"
        s.env.update(FT2_MAILBOX_DIR=str(comm), FT2_SEAT_RESUME_DIR=str(rs))
        comm.mkdir(exist_ok=True)
        with open(comm / "mailbox.log.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"from": new, "to": old, "body": "[레디] %s <- %s · 항목 1" % (new, old)}, ensure_ascii=False) + "\n")
        if resume:
            s.resume(old)
    def resume(s, seat, uuid=None):
        """r2055 S2 검증된 재개 기록 — 실제 pi 세션 파일(cwd 세션 폴더 · 이름 끝 = uuid) + seat-resume/<좌석>.json."""
        uuid, rs = uuid or "u-" + seat.replace("#", "-"), s.tmp / "resume"
        s.env.update(FT2_SEAT_RESUME_DIR=str(rs))
        log = Path(s.env["FT2_PI_SESSIONS"]) / ("--%s--" % str(s.root).strip("/").replace("/", "-")) / ("2026-11-01_%s.jsonl" % uuid)
        _put(log, '{"type": "session"}\n'), os.utime(log, (s.t - 7200, s.t - 7200))   # Q1 ① 장기 좌석 나이 = 이 파일 mtime(2시간 쉼)
        _put(rs / (seat + ".json"), {"name": seat, "uuid": uuid, "engine": "pi", "cwd": str(s.root), "jsonl": str(log)})
    def enable(s, team=TEAM):
        _put(s.root / ".fable-team" / "teams" / team / "CLOSE-NEXT.enabled", "enabled\n")
