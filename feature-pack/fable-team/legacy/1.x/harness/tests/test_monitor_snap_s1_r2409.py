"""tests/test_monitor_snap_s1_r2409.py — 모니터 스냅샷 수집기(그림자) 시험 (r2409 · 기획서 §2.1·§3 S1·§4.1).

카드 계약 K1~K6 · 반례 ①~⑧ · 변이 M1~M7. 카드의 ①~⑧ 번호를 그대로 쓰고, 기획서 §3 S1 «닫는 증거»
(반례 ③·④·⑬b·⑬c·⑭·⑮·⑲ + 진입점 대역)와 카드 표 꼬리 줄(K4=⑤ · K5=⑥ · K6=⑦⑧)을 이어 붙였다.
  K1 ① 스냅샷 파일 꼴(11칸 v·src·at·q · fact_key·fact_changed_at) · M1 칸에 src 빠짐
  K2 ② 칸 유효성(unknown = v null · 0 으로 채우지 않음 · 한 칸 실패가 다른 칸을 안 멈춤) · M2 unknown 에 값
  K3 ③④ fact_changed_at 승계(같은 열쇠 = 그대로 · 역사 절단·72시간 무관 · 직전 스냅샷 없음 = «?») · M3 매 틱 now
  K4 ⑤ directive rc 계약(rc 0·1 + 정상 첫 줄 = ok · 그 밖 = unknown) · M4 rc≠0 전부 unknown
  K5 ⑥ 역사 줄과 결정성(같은 입력·같은 at = 같은 바이트 · 열쇠 같으면 0줄 · 48시간 절단 · 키 정렬) · M5 정렬 제거
  K6 ⑦⑧ 그림자(진입점 ft-board-publish.sh --news 에서 수집 1회 · 다른 모드 0회 · 실패·상한 초과에도 기존
        collect/news/post/rc 보존) · M6 수집 rc 전파 · M7 잘못된 진입점(ft-news-tick.sh) 연결
실 Slack · 실 스냅샷 · 실 설치 · 실 launchd 0 (전부 임시 폴더 + 스텁) · 시험 1개 ≤ 70초.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIN = HERE.parent / "kit" / "fable-team" / "bin"
sys.path.insert(0, str(BIN))
import ft_monitor_snap as mon  # noqa: E402

FAIL = []


def chk(name, cond, detail=""):
    if cond:
        print(f"PASS {name}")
    else:
        print(f"FAIL {name}{(' — ' + detail) if detail else ''}")
        FAIL.append(name)


def _w(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _script(path: Path, body: str):
    _w(path, body)
    path.chmod(0o755)
    return path


def shape_violations(snap: dict) -> list:
    """K1·K2 꼴 검사 — 칸이 빠졌거나, unknown 인데 값이 있거나(0 채움), 출처가 없으면 어긋남."""
    out = []
    cells = snap.get("cells") or {}
    if sorted(cells) != sorted(mon.cells_lib.CELLS):
        out.append(f"칸 목록 다름 {sorted(cells)}")
    for name, item in cells.items():
        missing = [k for k in ("v", "src", "at", "q") if k not in item]
        if missing:
            out.append(f"{name} 칸에 {missing} 없음")
        if item.get("q") not in ("ok", "stale", "unknown"):
            out.append(f"{name} q={item.get('q')!r}")
        if item.get("q") == "unknown" and item.get("v") is not None:
            out.append(f"{name} unknown 인데 값 {item.get('v')!r} (0 채움)")
        if item.get("q") == "ok" and item.get("v") is not None and not item.get("src"):
            out.append(f"{name} 출처 없음")
    for goal, item in (snap.get("goals") or {}).items():
        if "fact_key" not in item or "fact_changed_at" not in item:
            out.append(f"{goal} fact 승계 칸 없음")
    return out


class World:
    """임시 루트 + 원천 스텁 — 실파일·실설치 손 0."""

    def __init__(self, tmp: Path):
        self.t = tmp
        self.root = tmp / "root"
        for d in ("design/teams/planner/indices/진행", "design/teams/planner/indices/대기",
                  "design/teams/harness/indices/완성", ".fable-team/state/blocks", ".fable-team/comm"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        self.snap = tmp / "board/monitor-snap.json"
        self.hist = tmp / "board/monitor-hist.jsonl"
        self.calls = tmp / "calls.log"
        self.t0 = 1795267000.0
        self.script_autonomy(0, "[자율 ON A19 · 08:57~ · 끝 없음]")
        self.script_directive(0, "담당 없는 오빠 지시 2 · 멈춘 오빠 지시 1 · 판본 x")
        self.script_hil(0, "h3 12\nh4 7\n")
        self.script_board({"harness": None, "graphics": "판정 불가(폴더 없음)"})
        self.goal_md("| 골 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 | 다음 한 수 1줄 |\n|---|---|---|---|---|---|\n"
                     "| 5 | 하네스 운영 정리 | 4 | 9 | 진행 | — |\n| 2 | B2B 토스 결제 시험 | 3 | 5 | 진행 | — |\n")
        self.reply_wait([{"q_ts": "1.1", "kind": "thread", "key": "a", "state": "open"},
                         {"q_ts": "2.2", "kind": "question", "key": "b", "state": "closed"},
                         {"q_ts": "3.3", "kind": "thread", "key": "c", "state": "open"}])
        self.stall({"ts": self.t0 - 60, "c": 1, "teams": {"harness": {"f": 1}, "ops": {"f": 1}, "cfo": {"f": 0},
                                                          "room": {"diag": "폴더 없음"}}})
        _w(self.root / ".fable-team/state/blocks/owner.json",
           json.dumps([{"tool": "ft2-keeper:stale", "seat": "x"}, {"tool": "other"}]))
        _w(self.root / ".fable-team/seats-planner.json", json.dumps({"_master": "byz-planner-master-pi#401"}))
        _w(self.root / ".fable-team/comm/mailbox.log.jsonl",
           json.dumps({"ts": "2026-11-21T22:10:00", "to": "byz-planner-master-pi#401", "from": "x",
                       "body": "[정리] 카드 대기 3 · 진행 2"}, ensure_ascii=False) + "\n")
        self.card("goal-keep", "진행", "하네스 운영 정리", ["- 대기 사유: 오빠 승인 대기"])
        self.card("goal-b2b", "대기", "B2B 토스 결제 시험", ["- 선행: r2389"])
        self.card("done-1", "완성", "하네스 운영 정리", [])
        self.git()
        os.environ.update({"FT_MONITOR_SNAP": str(self.snap), "FT_MONITOR_HIST": str(self.hist),
                           "FT_MONITOR_GOAL_MD": str(self.t / "goal.md"),
                           "FT_MONITOR_CARDS_DESIGN": str(self.root / "design"),
                           "FT_MONITOR_REPLY_WAIT": str(self.root / ".fable-team/state/desk-reply-wait.jsonl"),
                           "FT_MONITOR_STALL": str(self.root / ".fable-team/state/stall-scan.last.json"),
                           "FT_MONITOR_BLOCKS": str(self.root / ".fable-team/state/blocks"),
                           "FT_MONITOR_MAILLOG": str(self.root / ".fable-team/comm/mailbox.log.jsonl"),
                           "FT_MONITOR_SEATS_PLANNER": str(self.root / ".fable-team/seats-planner.json"),
                           "FT_MONITOR_AUTONOMY": str(self.t / "stub/autonomy.sh"),
                           "FT_MONITOR_DIRECTIVE": str(self.t / "stub/directive.py"),
                           "FT_MONITOR_HIL": str(self.t / "stub/hil.sh"),
                           "FT_MONITOR_BOARD": str(self.t / "stub/board.py")})

    def script_autonomy(self, rc, line):
        _script(self.t / "stub/autonomy.sh", f'#!/bin/sh\necho "{line}"\nexit {rc}\n')

    def script_directive(self, rc, line):
        _script(self.t / "stub/directive.py", "import sys\nprint(%r)\nsys.exit(%d)\n" % (line, rc))

    def script_hil(self, rc, out):
        _w(self.t / "stub/hil.sh", "#!/bin/sh\ncat <<'EOF_HIL'\n" + out + "EOF_HIL\nexit " + str(rc) + "\n")
        (self.t / "stub/hil.sh").chmod(0o755)

    def script_board(self, errors: dict):
        _w(self.t / "stub/collect.json",
           json.dumps({"teams": [{"key": k, "error": v} if v else {"key": k} for k, v in errors.items()]},
                      ensure_ascii=False))
        _script(self.t / "stub/board.py",
                "import sys, shutil\n"
                "out = sys.argv[sys.argv.index('--out') + 1]\n"
                f"shutil.copy({str(self.t / 'stub/collect.json')!r}, out)\n"
                f"open({str(self.calls)!r}, 'a').write('board\\n')\n")

    def goal_md(self, table: str):
        _w(self.t / "goal.md", "## 골 진행\n\n" + table + "\n")

    def reply_wait(self, rows):
        _w(self.root / ".fable-team/state/desk-reply-wait.jsonl",
           "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))

    def stall(self, doc):
        _w(self.root / ".fable-team/state/stall-scan.last.json", json.dumps(doc))

    def card(self, cid, state, goal, lines, team="planner"):
        _w(self.root / f"design/teams/{team}/indices/{state}/{cid}.md",
           f"# 인덱스: {cid}\n- 상태: {state}\n- 골좌표: {goal}\n" + "".join(l + "\n" for l in lines))

    def git(self):
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t"}

        def run(*a):
            return subprocess.run(["git", "-C", str(self.root), *a], capture_output=True, env=env)
        run("init", "-q", "-b", "main")
        run("add", "-A")
        run("commit", "-qm", "base")
        run("update-ref", "refs/remotes/origin/main", "HEAD")

    def tick(self, now: float) -> dict:
        snap, wrote, _ = mon.collect(self.root, now)
        return {"snap": snap, "hist_wrote": wrote, "bytes": self.snap.read_text(encoding="utf-8")}


class Entry:
    """실제 진입점 대역 — ft-board-publish.sh --news 를 스텁과 함께 돌린다(실 Slack·실 발행·실 스냅샷 0)."""

    def __init__(self, tmp: Path):
        self.t = tmp
        self.root = tmp / "eroot"
        for d in (".fable-team/state/board", ".fable-team/state", ".fable-team/comm"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        self.snap_log = tmp / "snap.log"
        self.board_log = tmp / "board.log"
        self.post_log = tmp / "posts.log"
        self.pub = str(BIN / "ft-board-publish.sh")
        for name, body in (("snap.py", "sys.exit(0)"), ("snap_fail.py", "sys.exit(3)"),
                           ("snap_slow.py", "time.sleep(5)\nsys.exit(0)")):
            _w(tmp / name, "import pathlib, sys, time\n"
                           f"p = pathlib.Path({str(self.snap_log)!r})\n"
                           'p.write_text((p.read_text() if p.exists() else "") + "x\\n")\n' + body + "\n")
        _script(tmp / "board.sh",
                "#!/usr/bin/env bash\n"
                f'echo "$1" >> {self.board_log}\n'
                'if [ "$1 $2" = "collect --out" ]; then echo \'{"teams":[]}\' > "$3"; exit 0; fi\n'
                'if [ "$1" = snapshot ]; then printf \'{"changes": [], "snap": "s1", "prev_day_last": ""}\'; exit 0; fi\n'
                'exit 0\n')
        _script(tmp / "post.py",
                "import sys, pathlib\n"
                f"p = pathlib.Path({str(self.post_log)!r})\n"
                'p.write_text((p.read_text(encoding="utf-8") if p.exists() else "") + "post\\n", encoding="utf-8")\n')

    def _count(self, path: Path) -> int:
        return len(path.read_text(encoding="utf-8").splitlines()) if path.exists() else 0

    def run(self, snap_bin: str = "snap.py", timeout: str = "70", args: tuple = ("--news",)) -> dict:
        # 실행마다 직전 발행 표식을 지운다 — «변화 없음» 디바운스에 가려 발행 0 이 되는 것을 막는다
        (self.root / ".fable-team/state/board/news-last.json").unlink(missing_ok=True)
        self.post_log.unlink(missing_ok=True)
        s0, b0 = self._count(self.snap_log), self._count(self.board_log)
        started = time.time()
        done = subprocess.run(["bash", self.pub, *args], capture_output=True, text=True,
                              env={**os.environ, "FT_ROOT": str(self.root),
                                   "FT_BOARD_BIN": str(self.t / "board.sh"),
                                   "FT_THREAD_POST": str(self.t / "post.py"),
                                   "FT_BOARD_POST_ARGS": "--channel C1",
                                   "FT_MONITOR_SNAP_BIN": str(self.t / snap_bin),
                                   "FT_MONITOR_SNAP_TIMEOUT": timeout,
                                   "FT_BOARD_NOW": "2026-11-21T22:00:00", "FT_SLACK_TOPIC_ONLY": "",
                                   "FT_BOARD_ONLY_CHANGED": "0"})
        return {"rc": done.returncode, "snap": self._count(self.snap_log) - s0,
                "board": self._count(self.board_log) - b0, "posts": self._count(self.post_log),
                "sec": round(time.time() - started, 1),
                "last": (self.root / ".fable-team/state/board/news-last.json").exists(),
                "err": (done.stderr.strip().splitlines() or [""])[-1]}


def main() -> int:
    t0 = time.time()
    with tempfile.TemporaryDirectory() as d:
        w = World(Path(d) / "w")

        # ── ① 스냅샷 파일 꼴 (K1) ──
        r1 = w.tick(w.t0)
        chk("① snap.json 새로 · 11칸 v·src·at·q · goals fact_key/fact_changed_at · hist +1",
            not shape_violations(r1["snap"]) and r1["hist_wrote"] == 1, str(shape_violations(r1["snap"])))
        chk("① 칸 값 실측: 골 2 · 지시 두 수 · h 2 · 막힌 세션 2 · keeper 1 · 오빠 기다림 2 · 팀 수집 실패 1",
            r1["snap"]["cells"]["goals"]["v"] == {"하네스 운영 정리": {"n": 4, "m": 9},
                                                  "B2B 토스 결제 시험": {"n": 3, "m": 5}}
            and r1["snap"]["cells"]["directives"]["v"] == {"no_owner": 2, "stopped": 1}
            and r1["snap"]["cells"]["hil"]["v"] == 2
            and r1["snap"]["cells"]["blocked_sessions"]["v"]["blocked"] == 2
            and r1["snap"]["cells"]["keeper_unknown"]["v"]["unknown_keeper"] == 1
            and r1["snap"]["cells"]["oppa_wait"]["v"]["open"] == 2
            and r1["snap"]["cells"]["collect_fail"]["v"] == {"graphics": "판정 불가(폴더 없음)"},
            str({k: v["v"] for k, v in r1["snap"]["cells"].items()}))
        chk("① 완성 카드 착지 시각 · 기다림 줄이 골별로 실림",
            r1["snap"]["cells"]["goal_facts"]["v"]["하네스 운영 정리"]["착지"].get("done-1")
            and r1["snap"]["cells"]["waiting"]["v"]["하네스 운영 정리"][0].startswith("goal-keep:"))

        # ── ② 칸 유효성 (K2) ──
        w.script_autonomy(2, "[자율 ON A19]")
        _w(w.root / ".fable-team/state/stall-scan.last.json", "{ 깨진")
        r2 = w.tick(w.t0 + 60)
        chk("② 자율 rc2 · stall 깨짐 = 그 두 칸만 unknown(v null) · 나머지 칸 값 그대로",
            r2["snap"]["cells"]["autonomy"]["q"] == "unknown" and r2["snap"]["cells"]["autonomy"]["v"] is None
            and r2["snap"]["cells"]["blocked_sessions"]["q"] == "unknown"
            and r2["snap"]["cells"]["blocked_sessions"]["v"] is None
            and r2["snap"]["cells"]["hil"]["q"] == "ok" and r2["snap"]["cells"]["goals"]["v"]
            and not shape_violations(r2["snap"]), str(shape_violations(r2["snap"])))
        w.script_autonomy(0, "[자율 ON A19 · 08:57~ · 끝 없음]")
        w.stall({"ts": w.t0, "teams": {"harness": {"f": 1}, "ops": {"f": 1}, "cfo": {"f": 0}}})
        r3 = w.tick(w.t0 + 120)
        chk("② 한 칸 unknown 이 다른 칸·hist 쓰기를 멈추지 않음(다음 틱 hist +1)",
            r3["snap"]["cells"]["autonomy"]["q"] == "ok" and r3["hist_wrote"] == 1)
        chk("② 원천이 낡으면 stale(값 유지) — stall 11분 전",
            mon.cells_lib.blocked_sessions(w.root, "x", w.t0 + 700)["q"] == "stale")

        # ── ③④ fact_changed_at 승계 (K3) ──
        chk("④ 첫 틱은 «서 있음 ?»(직전 스냅샷 없음 = fact_changed_at null)",
            r1["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"] is None)
        w.snap.unlink()
        r4 = w.tick(w.t0 + 200)
        chk("④ 스냅샷 파일을 지우면 다시 null(모르는 것을 지어내지 않음)",
            r4["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"] is None)
        r5 = w.tick(w.t0 + 260)
        w.hist.unlink(missing_ok=True)
        r6 = w.tick(w.t0 + 320)
        key6 = r6["snap"]["goals"]["하네스 운영 정리"]["fact_key"]
        r7 = w.tick(w.t0 + 320 + 72 * 3600)
        chk("③ 72시간 뒤·역사 파일 삭제 뒤에도 열쇠 같으면 승계(now 로 덮지 않음)",
            r7["snap"]["goals"]["하네스 운영 정리"]["fact_key"] == key6
            and r7["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"] is None)
        w.card("goal-keep", "진행", "하네스 운영 정리", ["- 대기 사유: DA 판정 대기"])
        r8 = w.tick(w.t0 + 320 + 72 * 3600 + 60)
        chk("③ 기다림 줄이 바뀌면 새 열쇠 · 시작점 = 지금",
            r8["snap"]["goals"]["하네스 운영 정리"]["fact_key"] != key6
            and r8["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"]
            == mon.iso(w.t0 + 320 + 72 * 3600 + 60))
        chk("③ 시작점 있는 골은 다음 틱에 그대로 승계",
            (lambda a, b: b["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"]
             == a["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"])(r8, w.tick(w.t0 + 320 + 72 * 3600 + 120)))

        # ── ⑤ directive rc 계약 (K4) ──
        for rc, line, want in ((0, "담당 없는 오빠 지시 0 · 멈춘 오빠 지시 1 · 판본", "ok"),
                               (1, "담당 없는 오빠 지시 4 · 멈춘 오빠 지시 0 · 판본", "ok"),
                               (2, "담당 없는 오빠 지시 4 · 멈춘 오빠 지시 0", "unknown"),
                               (0, "판본만 있음", "unknown")):
            w.script_directive(rc, line)
            got = mon.cells_lib.directives(w.root, mon.iso(w.t0))["q"]
            chk(f"⑤ directive rc={rc} «{line[:16]}…» = {want}", got == want, f"got {got}")
        w.script_directive(1, "담당 없는 오빠 지시 4 · 멈춘 오빠 지시 0 · 판본 x")

        # ── ⑥ 역사 줄과 결정성 (K5) ──
        w.hist.unlink(missing_ok=True)
        a = w.tick(w.t0 + 400)
        again = w.tick(w.t0 + 400)
        chk("⑥ 같은 입력·같은 at 두 번 = snap 바이트 같음 · hist 1줄만",
            again["bytes"] == a["bytes"] and a["hist_wrote"] == 1 and again["hist_wrote"] == 0)
        w.script_directive(1, "담당 없는 오빠 지시 9 · 멈춘 오빠 지시 0 · 판본 y")
        r9 = w.tick(w.t0 + 460)
        chk("⑥ 값이 바뀌면 hist +1", r9["hist_wrote"] == 1)
        rows = [json.loads(x) for x in w.hist.read_text(encoding="utf-8").splitlines() if x.strip()]
        _w(w.hist, json.dumps({**rows[0], "epoch": w.t0 + 400 - 49 * 3600}) + "\n"
           + "".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
        w.tick(w.t0 + 520)
        kept = [json.loads(x) for x in w.hist.read_text(encoding="utf-8").splitlines() if x.strip()]
        chk("⑥ 48시간 넘은 줄은 버리고 나머지는 남김",
            all(float(k["epoch"]) > w.t0 + 520 - 48 * 3600 for k in kept) and len(kept) >= 2,
            f"{[k['epoch'] for k in kept]}")
        proj_a = {"cells": {"goals": {"v": {"a": {"n": 1, "m": 2}}, "q": "ok"}}, "goals": {"g": {"n": "k"}}}
        proj_b = {"goals": {"g": {"n": "k"}}, "cells": {"goals": {"q": "ok", "v": {"a": {"m": 2, "n": 1}}}}}
        chk("⑥ 입력 dict 순서가 달라도 열쇠 = 같다(키 정렬 고정)", mon._key(proj_a) == mon._key(proj_b))
        chk("⑥ 경과 시간(«N분 전»)은 열쇠 밖 — q 만 본다(§2.4 G5)",
            "planner_check" in mon.NO_TIME)

        # ── ⑦⑧ 실제 진입점 대역 (K6) ──
        ent = Entry(Path(d) / "entry")
        news = ent.run()
        chk("⑦ --news 1회 = 수집 1회 · collect 1회 · 글 1통 · rc 0",
            news["snap"] == 1 and news["board"] >= 1 and news["posts"] == 1 and news["rc"] == 0, str(news))
        fail = ent.run("snap_fail.py")
        chk("⑧ 수집 실패(rc 3)여도 collect·글 1통·rc 0 그대로(격리) · news-last 갱신",
            fail["rc"] == 0 and fail["snap"] == 1 and fail["posts"] == 1 and fail["board"] >= 1
            and fail["last"] is True, str(fail))
        slow = ent.run("snap_slow.py", timeout="1")
        chk("⑧ 수집 상한 초과(alarm 1초 · 수집기 5초)에도 rc 0 · 글 1통",
            slow["rc"] == 0 and slow["posts"] == 1 and slow["snap"] == 1 and slow["sec"] < 4, str(slow))
        plain = ent.run(args=())
        chk("⑦ 다른 모드(--news 아님) = 수집 0회", plain["snap"] == 0, str(plain))

        # ── 변이 M1~M7 대조 ──
        snap = json.loads(w.snap.read_text(encoding="utf-8"))
        m1 = json.loads(json.dumps(snap))
        del m1["cells"]["goals"]["src"]
        chk("M1 칸에서 src 를 빼면 ① 꼴 검사가 어긋남을 말한다", shape_violations(m1) != [])
        m2 = json.loads(json.dumps(snap))
        m2["cells"]["autonomy"] = {**m2["cells"]["autonomy"], "v": "OFF", "q": "unknown"}
        chk("M2 unknown 칸에 값을 채우면 ② 검사가 어긋남을 말한다", shape_violations(m2) != [])
        cell_now = mon.cells_lib.collect_all(w.root, mon.iso(w.t0 + 900), w.t0 + 900)
        key_now = mon._fact_key("하네스 운영 정리", cell_now["goals"]["v"]["하네스 운영 정리"], cell_now)
        old_at = mon.iso(w.t0 + 100)
        prev_doc = {"goals": {"하네스 운영 정리": {"fact_key": key_now, "fact_changed_at": old_at}}}
        good = mon._goals(cell_now, prev_doc, w.t0 + 900)
        bad = {g: {"fact_key": key_now, "fact_changed_at": mon.iso(w.t0 + 900)} for g in good}
        chk("M3 매 틱 now 로 덮는 변이 = ③ 승계 시험이 갈라진다(정상은 옛 시각 유지)",
            good["하네스 운영 정리"]["fact_changed_at"] == old_at
            and bad["하네스 운영 정리"]["fact_changed_at"] != old_at)
        w.script_directive(2, "담당 없는 오빠 지시 4 · 멈춘 오빠 지시 0")
        m4 = mon.cells_lib.directives(w.root, "x")
        w.script_directive(1, "담당 없는 오빠 지시 4 · 멈춘 오빠 지시 0 · 판본 z")
        chk("M4 rc≠0 을 전부 unknown 으로 보는 변이면 rc1 정상 첫 줄도 못 읽는다(계약 위반 검출)",
            m4["q"] == "unknown")
        m5a, m5b = {"b": 1, "a": 2}, {"a": 2, "b": 1}
        chk("M5 sort_keys 를 빼면 입력 순서만 다른 같은 객체 둘의 바이트가 갈린다(정렬 검사가 잡는다)",
            json.dumps(m5a) != json.dumps(m5b) and mon._key({"cells": m5a}) == mon._key({"cells": m5b}))
        chk("M6 수집 rc 를 진입점으로 전파하는 변이 = ⑧ 이 잡는다(수집 실패 때 rc 0·글 1통이어야)",
            fail["rc"] == 0 and fail["posts"] == 1)
        tick = BIN / "ft-news-tick.sh"
        hooked = tick.exists() and "ft_monitor_snap" in tick.read_text(encoding="utf-8", errors="ignore")
        chk("M7 진입점을 ft-news-tick.sh 로 잘못 연결하는 변이 = 그 경로에 수집 0회(⑦ 이 잡는다)",
            (not hooked) and news["snap"] == 1)

    print(f"— 초 {round(time.time() - t0, 1)} · 실패 {len(FAIL)}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
