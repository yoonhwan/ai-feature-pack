"""tests/test_monitor_snap_s1_r2409.py — 모니터 스냅샷 수집기(그림자) 시험 (r2409 · 카드 계약 K1~K6 · 반례 ①~⑧ · 변이 M1~M7).

카드 = design/harness/indices/대기/r2409-monitor-snap-collect-shadow-s1.md(origin/ops/main-base)
  ① 원천 11개 정상 가짜 루트 → 칸 11종 · 꼴(v·src·at·q) · q=ok        (M1 못 잰 칸을 v=0·q=ok → ② FAIL)
  ② 자율 status 8초 → 그 칸 unknown·v null · 다른 칸 ok · 전체 rc 0     (기획서 ⑭)
  ③ 장부 열린 줄 9(kind=thread) → v=9·식별자 9개 / 깨진 줄 1 → unknown   (M2 kind=question 만 셈 → 첫 구 FAIL)
  ④ fact_key 같음 + 72시간 전 + hist 48시간 절단 + 새 프로세스 → 그대로 · fact_key 다름 → 지금 · 직전 스냅샷 0 → null (M3 매 틱 now)
  ⑤ rc 1 + 정상 첫 줄 → ok · rc 2 → unknown · 꼴 다름 → unknown · 둘째 줄 무관 (M4 rc 1 을 unknown 으로)
  ⑥ 같은 입력·같은 --now 2회 → 바이트 같음 · hist 2줄 · 49시간 전 줄 잘림 (M5 정렬 뺌)
  ⑦ 진입점 대역 5구 — 정상 / rc 1 / 상한(FT_MONITOR_SNAP_CAP=1) / collect rc 3 / 인자 없는 갈래 (M6 실패를 틱 실패로 · M7 ft-news-tick.sh 로 옮김)
  ⑧ 회귀 — test_board_publish_tick.sh · test_board_news_main_post_r2120.sh PASS · 수집기 실행 중 mbox send 0
변이는 사본에서만 돌리고 변이마다 원본으로 같은 사례를 1회 더 돌려 대조한다(카드 «변이» 줄).
실 Slack · 실 스냅샷 · 실 설치 · 실 launchd 0 · 시험 1개 ≤ 70초.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
HAR = HERE.parent
BIN = HAR / "kit" / "fable-team" / "bin"
PUB = BIN / "ft-board-publish.sh"
FAIL = []


def chk(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f" — {detail}" if not cond and detail else ""))
    if not cond:
        FAIL.append(name)


def _w(path: Path, text: str, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)
    return path


class Rig:
    """원천 11개가 다 정상인 가짜 루트(①). 스텁은 전부 임시 폴더 안."""

    def __init__(self, tmp: Path):
        self.t = tmp
        self.root = tmp / "root"
        self.snap = tmp / "board/monitor-snap.json"
        self.hist = tmp / "board/monitor-hist.jsonl"
        self.now = 1795267000.0
        self.logs = tmp / "logs"
        self.logs.mkdir(parents=True, exist_ok=True)
        for d in ("design/teams/harness/indices/대기", "design/teams/harness/indices/진행",
                  "design/teams/harness/indices/완성", ".fable-team/state/blocks", ".fable-team/comm"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        _w(tmp / "goal.md", "## 골 진행\n\n| 골 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 | 다음 한 수 1줄 |\n"
                            "|---|---|---|---|---|---|\n| 1 | 하네스 운영 정리 | 4 | 9 | 진행 | — |\n")
        # 카드 골좌표 = «6 · 하네스 운영 정리» — 원장 번호(1)와 어긋난 실측 꼴 · 이름으로 결속해야 한다
        self.card("hn-a", "진행", "6 · 하네스 운영 정리", ["- 대기 사유: DA 판정 대기"])
        self.card("hn-b", "완성", "6 · 하네스 운영 정리", [])
        self.reply_wait([{"q_ts": f"17.00{i}", "kind": "thread", "key": f"th{i}", "state": "open"} for i in range(9)]
                        + [{"q_ts": "1.1", "kind": "question", "key": "q-closed", "state": "closed"}])
        _w(self.root / ".fable-team/state/stall-scan.last.json",
           json.dumps({"ts": self.now - 120, "c": 1, "teams": {"harness": {"f": 1}, "ops": {"f": 0}}}))
        _w(self.root / ".fable-team/state/blocks/owner.json", json.dumps([{"tool": "ft2-keeper:stale"}]))
        _w(self.root / ".fable-team/seats-planner.json",
           json.dumps({"_master": "byz-planner-master-pi#401", "_desk": "byz-planner-desk-pi#237"}))
        _w(self.root / ".fable-team/comm/mailbox.log.jsonl",
           json.dumps({"ts": "2026-11-21T22:56:00", "to": "byz-planner-master-pi#401",
                       "body": "[정리] 카드 대기 3"}, ensure_ascii=False) + "\n")
        self.stub_autonomy(f'echo "[자율 ON A19 · 08:57~ · 끝 없음]"; exit 0', 0)
        _w(tmp / "stub/directive.sh", "#!/bin/sh\nprintf '%s\\n' '담당 없는 오빠 지시 2 · 멈춘 오빠 지시 1 · 판본 x' '둘째 줄은 안 읽는다'\n"
                                      "exit ${DIRECTIVE_RC:-0}\n", 0o755)
        _w(tmp / "stub/hil.sh", "#!/bin/sh\nprintf 'h3 12\\nh4 7\\n'\n", 0o755)
        _w(tmp / "stub/collect.json", json.dumps({"teams": [{"key": "harness"}]}))
        _w(tmp / "stub/board.py", "import sys, shutil\n"
                                  "out = sys.argv[sys.argv.index('--out') + 1]\n"
                                  f"shutil.copy({str(tmp / 'stub/collect.json')!r}, out)\n", 0o755)
        self.git()

    def card(self, cid, state, goal, lines):
        _w(self.root / f"design/teams/harness/indices/{state}/{cid}.md",
           f"# 인덱스: {cid}\n- 상태: {state}\n- 골좌표: {goal}\n" + "".join(l + "\n" for l in lines))

    def reply_wait(self, rows, extra=""):
        _w(self.root / ".fable-team/state/desk-reply-wait.jsonl",
           "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows) + extra)

    def stub_autonomy(self, body: str, rc: int):
        _w(self.t / "stub/autonomy.sh", "#!/bin/sh\n" + body + f"\nexit {rc}\n", 0o755)

    def git(self):
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t"}
        for a in (("init", "-q", "-b", "main"), ("add", "-A"), ("commit", "-qm", "base")):
            subprocess.run(["git", "-C", str(self.root), *a], capture_output=True, env=env)
        subprocess.run(["git", "-C", str(self.root), "update-ref", "refs/remotes/origin/main", "HEAD"],
                       capture_output=True, env=env)

    def env(self, over=None) -> dict:
        base = {**os.environ,
                "FT_MONITOR_SNAP": str(self.snap), "FT_MONITOR_HIST": str(self.hist),
                "FT_MONITOR_GOAL_MD": str(self.t / "goal.md"),
                "FT_MONITOR_CARDS_DESIGN": str(self.root / "design"),
                "FT_MONITOR_REPLY_WAIT": str(self.root / ".fable-team/state/desk-reply-wait.jsonl"),
                "FT_MONITOR_STALL": str(self.root / ".fable-team/state/stall-scan.last.json"),
                "FT_MONITOR_BLOCKS": str(self.root / ".fable-team/state/blocks"),
                "FT_MONITOR_MAILLOG": str(self.root / ".fable-team/comm/mailbox.log.jsonl"),
                "FT_MONITOR_SEATS_PLANNER": str(self.root / ".fable-team/seats-planner.json"),
                "FT_MONITOR_AUTONOMY": str(self.t / "stub/autonomy.sh"),
                "FT_MONITOR_DIRECTIVE": str(self.t / "stub/directive.sh"),
                "FT_MONITOR_HIL": str(self.t / "stub/hil.sh"),
                "FT_MONITOR_BOARD": str(self.t / "stub/board.py")}
        return {**base, **(over or {})}

    def run(self, now=None, over=None, bin_dir=BIN) -> dict:
        started = time.time()
        done = subprocess.run([sys.executable, str(Path(bin_dir) / "ft_monitor_snap.py"),
                               "--root", str(self.root), "--now", repr(now or self.now)],
                              capture_output=True, text=True, env=self.env(over))
        out = {"rc": done.returncode, "out": done.stdout, "err": done.stderr.strip(),
               "sec": round(time.time() - started, 2)}
        try:
            out["snap"] = json.loads(self.snap.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            out["snap"] = None
        out["hist"] = ([json.loads(x) for x in self.hist.read_text(encoding="utf-8").splitlines() if x.strip()]
                       if self.hist.exists() else [])
        out["bytes"] = self.snap.read_text(encoding="utf-8") if self.snap.exists() else ""
        return out


def shape_bad(snap: dict) -> list:
    out = []
    cells = (snap or {}).get("cells") or {}
    if len(cells) != 11:
        out.append(f"칸 {len(cells)}종")
    for name, item in cells.items():
        if sorted(item) != ["at", "q", "src", "v"]:
            out.append(f"{name} 꼴 {sorted(item)}")
        if item.get("q") not in ("ok", "stale", "unknown"):
            out.append(f"{name} q={item.get('q')!r}")
        if item.get("q") == "unknown" and item.get("v") is not None:
            out.append(f"{name} unknown 인데 v={item.get('v')!r}")
    for goal, item in ((snap or {}).get("goals") or {}).items():
        if "fact_key" not in item or "fact_changed_at" not in item:
            out.append(f"{goal} fact 칸 없음")
    return out


# ───────────────────────── 진입점 대역(⑦) ─────────────────────────
class Entry:
    """ft-board-publish.sh --news 를 스텁과 함께 돌린다. 기준판 = 같은 스크립트에서 r2409 수집 줄만 뺀 사본."""

    def __init__(self, tmp: Path):
        self.t = tmp
        self.root = tmp / "eroot"
        for d in (".fable-team/state/board", ".fable-team/state", ".fable-team/comm"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        _w(self.root / ".fable-team/seats-planner.json", json.dumps({"_desk": "byz-planner-desk-pi#237"}))
        self.snap_log = tmp / "snap.log"
        self.board_log = tmp / "board.log"
        self.post_log = tmp / "post.log"
        self.mbox_log = tmp / "mbox.log"
        self.dir = tmp / "pubbin"
        self.dir.mkdir()
        for f in BIN.iterdir():  # 나머지는 심링크(발행 스크립트만 사본 — 변이용)
            if f.is_file() and f.name != "ft-board-publish.sh":
                (self.dir / f.name).symlink_to(f)
        shutil.copy(BIN / "ft-board-publish.sh", self.dir / "ft-board-publish.sh")
        text = (BIN / "ft-board-publish.sh").read_text(encoding="utf-8").splitlines(keepends=True)
        base = [l for l in text if "r2409 K6" not in l and "monitor-snap rc=" not in l
                and "FT_MONITOR_SNAP_CAP" not in l]
        (_w(self.dir / "ft-board-publish.base.sh", "".join(base), 0o755))
        _w(tmp / "snap.py", "import sys\n" + f"open({str(self.snap_log)!r}, 'a').write('x')\n" + "sys.exit(0)\n")
        _w(tmp / "snap_rc1.py", "import sys\n" + f"open({str(self.snap_log)!r}, 'a').write('x')\n" + "sys.exit(1)\n")
        _w(tmp / "snap_slow.py", "import time, sys\n" + f"open({str(self.snap_log)!r}, 'a').write('x')\n"
                                 + "time.sleep(5)\nsys.exit(0)\n")
        _w(tmp / "board.sh", "#!/usr/bin/env bash\n" + f'echo "$1" >> {self.board_log}\n'
                             'if [ "$1 $2" = "collect --out" ]; then echo \'{"teams":[]}\' > "$3"; exit ${COLLECT_RC:-0}; fi\n'
                             'if [ "$1" = snapshot ]; then printf \'{"changes": [], "snap": "s1", "prev_day_last": ""}\'; exit 0; fi\n'
                             "exit 0\n", 0o755)
        _w(tmp / "post.py", "import sys, pathlib\n" + f"p = pathlib.Path({str(self.post_log)!r})\n"
                            + "p.write_text((p.read_text() if p.exists() else '') + 'post\\n')\n")
        _w(tmp / "mbox.sh", "#!/usr/bin/env bash\n" + f'echo "$@" >> {self.mbox_log}\n' + "exit 0\n", 0o755)

    def _count(self, p: Path) -> int:
        return len(p.read_text().splitlines()) if p.exists() else 0

    def run(self, base=False, snap="snap.py", cap="70", collect_rc="0", args=("--news",)) -> dict:
        for p in (self.snap_log, self.board_log, self.post_log, self.mbox_log):
            p.unlink(missing_ok=True)
        for f in ("news-last.json", "news-fail-last.json"):  # 표식을 지워야 30분 창이 앞 실행을 가리지 않는다
            (self.root / ".fable-team/state/board" / f).unlink(missing_ok=True)
        script = self.dir / ("ft-board-publish.base.sh" if base else "ft-board-publish.sh")
        started = time.time()
        done = subprocess.run(["bash", str(script), *args], capture_output=True, text=True,
                              env={**os.environ, "FT_ROOT": str(self.root),
                                   "FT_BOARD_BIN": str(self.t / "board.sh"),
                                   "FT_THREAD_POST": str(self.t / "post.py"),
                                   "FT_MBOX": str(self.t / "mbox.sh"),
                                   "FT_BOARD_POST_ARGS": "--channel C1",
                                   "FT_MONITOR_SNAP_BIN": str(self.t / snap),
                                   "FT_MONITOR_SNAP_CAP": cap, "COLLECT_RC": collect_rc,
                                   "FT_BOARD_NOW": "2026-11-21T22:00:00", "FT_SLACK_TOPIC_ONLY": "",
                                   "FT_BOARD_ONLY_CHANGED": "0"})
        return {"rc": done.returncode, "snap": self._count(self.snap_log),
                "board": self._count(self.board_log), "post": self._count(self.post_log),
                "mbox": self._count(self.mbox_log), "out": done.stdout,
                "err": done.stderr, "sec": round(time.time() - started, 1)}


def mutate(src_dir: Path, dst_dir: Path, name: str, old: str, new: str) -> Path:
    """bin 사본을 만들고 이름 하나만 바꾼다(원본 손 0)."""
    if not dst_dir.exists():
        shutil.copytree(src_dir, dst_dir)
    p = dst_dir / name
    text = p.read_text(encoding="utf-8")
    assert old in text, f"변이 자리 없음 {name}: {old[:40]}"
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    return dst_dir


def main() -> int:
    t0 = time.time()
    with tempfile.TemporaryDirectory() as d:
        rig = Rig(Path(d) / "rig")
        reg_procs = {name: subprocess.Popen(["bash", str(HERE / name)], stdout=subprocess.PIPE,
                                            stderr=subprocess.DEVNULL, text=True)  # ⑧ 회귀 = 처음부터 병렬
                     for name in ("test_board_publish_tick.sh", "test_board_news_main_post_r2120.sh")}

        # ① 원천 11 정상 → 칸 11종 · 꼴 · q=ok
        r1 = rig.run()
        chk("① 원천 11 정상 → 11칸 v·src·at·q · 전부 q=ok · rc 0 · 파일 0644",
            r1["rc"] == 0 and not shape_bad(r1["snap"]) and len(r1["snap"]["cells"]) == 11
            and all(c["q"] == "ok" for c in r1["snap"]["cells"].values())
            and oct(rig.snap.stat().st_mode & 0o777) == "0o644", f"{shape_bad(r1['snap'])} {r1['err'][:80]}")

        chk("① 카드 골좌표 «6 · 하네스 운영 정리» 를 원장 이름으로 결속(번호 어긋남 무관) · goals 에 원장 번호",
            set(r1["snap"]["cells"]["goal_facts"]["v"]) == {"하네스 운영 정리"}
            and set(r1["snap"]["cells"]["waiting"]["v"]) == {"하네스 운영 정리"}
            and r1["snap"]["cells"]["goals"]["v"]["하네스 운영 정리"] == {"n": 4, "m": 9, "no": "1"},
            str(r1["snap"]["cells"]["goal_facts"]["v"])[:150])

        # ② 자율 status 8초 → 그 칸만 unknown · 나머지 ok · rc 0
        rig.stub_autonomy("sleep 8\n", 0)
        r2 = rig.run(rig.now + 60)
        chk("② 자율 8초 → 그 칸 unknown·v null · 다른 칸 q=ok · 전체 rc 0",
            r2["rc"] == 0 and r2["snap"]["cells"]["autonomy"]["q"] == "unknown"
            and r2["snap"]["cells"]["autonomy"]["v"] is None
            and all(c["q"] == "ok" for k, c in r2["snap"]["cells"].items() if k != "autonomy"),
            json.dumps({k: v["q"] for k, v in r2["snap"]["cells"].items()}))
        rig.stub_autonomy('echo "[자율 ON A19 · 08:57~ · 끝 없음]"; exit 0', 0)

        # ③ 장부 열린 줄 9(thread) → v=9 · 식별자 9개 / 깨진 줄 1 → unknown
        r3 = rig.run(rig.now + 120)
        ow = r3["snap"]["cells"]["oppa_wait"]["v"]
        chk("③ 열린 줄 9(kind=thread) + 닫힌 1 → v=9 · 항목 10(식별자·닫힘 상태 · kind/q_ts 로 고유)",
            ow["open"] == 9 and len(ow["items"]) == 10
            and {i["state"] for i in ow["items"]} == {"open", "closed"}
            and len({i["key"] for i in ow["items"]}) == 10
            and any(i["id"] == "q-closed" and i["state"] == "closed" for i in ow["items"]), json.dumps(ow)[:200])
        rig.reply_wait([{"q_ts": "1.1", "kind": "thread", "key": "a", "state": "open"}], extra="{ 깨진 줄\n")
        r3b = rig.run(rig.now + 180)
        chk("③ 장부 깨진 줄 1 → 그 칸 q=unknown · v null",
            r3b["snap"]["cells"]["oppa_wait"]["q"] == "unknown" and r3b["snap"]["cells"]["oppa_wait"]["v"] is None)
        rig.reply_wait([{"q_ts": f"17.00{i}", "kind": "thread", "key": f"th{i}", "state": "open"} for i in range(9)]
                       + [{"q_ts": "1.1", "kind": "question", "key": "q-closed", "state": "closed"}])

        # ④ 승계 72시간 · fact_key 다름 → 지금 · 직전 스냅샷 0 → null
        old_at = "2026-11-18T22:56:40"
        r4a = rig.run(rig.now + 240)
        key = r4a["snap"]["goals"]["하네스 운영 정리"]["fact_key"]
        rig.snap.write_text(json.dumps({"schema": 1, "at": "", "cells": r4a["snap"]["cells"],
                                        "goals": {"하네스 운영 정리": {"fact_key": key,
                                                                   "fact_changed_at": old_at}}},
                                       ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
        rig.hist.write_text("", encoding="utf-8")  # 역사 절단(48시간) 뒤에도
        r4b = rig.run(rig.now + 300)
        chk("④ 열쇠 같음 + 72시간 전 + 역사 비움 + 새 프로세스 → fact_changed_at 그대로",
            r4b["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"] == old_at)
        rig.card("hn-a", "진행", "하네스 운영 정리", ["- 대기 사유: 오빠 승인 대기"])
        r4c = rig.run(rig.now + 360)
        chk("④ 열쇠 다름 → 지금 시각",
            r4c["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"] != old_at
            and r4c["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"].startswith("2026-11-2"))
        rig.snap.unlink()
        r4d = rig.run(rig.now + 420)
        chk("④ 직전 스냅샷 파일 0 → fact_changed_at null(«서 있음 ?»)",
            r4d["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"] is None)

        # ②b keeper 장부가 1시간 낡음 → 값 유지 · q=stale(K1 원천 표 10분 문턱)
        blocks = rig.root / ".fable-team/state/blocks/owner.json"
        old = rig.now + 480 - 3600
        os.utime(blocks, (old, old))
        r3c = rig.run(rig.now + 480)
        chk("②b keeper 장부 1시간 낡음 → v=1 · q=stale · at=장부 시각",
            r3c["snap"]["cells"]["keeper_unknown"]["q"] == "stale"
            and r3c["snap"]["cells"]["keeper_unknown"]["v"]["unknown_keeper"] == 1
            and r3c["snap"]["cells"]["keeper_unknown"]["at"] < "2026-11-21T23:00:00",
            json.dumps(r3c["snap"]["cells"]["keeper_unknown"], ensure_ascii=False)[:160])
        os.utime(blocks, (rig.now + 480, rig.now + 480))

        # ②c 카드 원천 폴더 없음 → goal_facts·waiting 만 unknown(정상 빈 목록으로 적지 않음)
        _w(rig.root / ".fable-team/state/stall-scan.last.json",
           json.dumps({"ts": rig.now + 500 - 60, "teams": {"harness": {"f": 1}}}))
        r3d = rig.run(rig.now + 500, {"FT_MONITOR_CARDS_DESIGN": str(rig.t / "없는폴더")})
        chk("②c 카드 원천 없음 → goal_facts·waiting q=unknown·v null · 원장(goals)과 다른 칸은 ok",
            r3d["snap"]["cells"]["goal_facts"]["q"] == "unknown"
            and r3d["snap"]["cells"]["goal_facts"]["v"] is None
            and r3d["snap"]["cells"]["waiting"] == {**r3d["snap"]["cells"]["waiting"], "v": None, "q": "unknown"}
            and all(c["q"] == "ok" for k, c in r3d["snap"]["cells"].items()
                    if k not in ("goal_facts", "waiting")),
            json.dumps({k: v["q"] for k, v in r3d["snap"]["cells"].items()}))

        # ⑤ directive rc 계약
        got = {}
        for rc, want in (("1", "ok"), ("2", "unknown")):
            got[rc] = rig.run(rig.now + 480, {"DIRECTIVE_RC": rc})["snap"]["cells"]["directives"]
            chk(f"⑤ rc {rc} → {want}", got[rc]["q"] == want, got[rc]["q"])
        chk("⑤ rc 1 정상 첫 줄 = 두 수", got["1"]["v"] == {"no_owner": 2, "stopped": 1}, str(got["1"]["v"]))
        _w(rig.t / "stub/bad.sh", "#!/bin/sh\nprintf '%s\\n' '판본만 있음'\nexit 0\n", 0o755)
        r5 = rig.run(rig.now + 540, {"FT_MONITOR_DIRECTIVE": str(rig.t / "stub/bad.sh")})
        chk("⑤ 첫 줄 꼴 다름 → unknown · 둘째 줄이 더 있어도 rc 1 정상은 그대로",
            r5["snap"]["cells"]["directives"]["q"] == "unknown" and got["1"]["q"] == "ok")

        # ⑥ 결정성 · hist 매 틱 1줄 · 49시간 절단
        rig.hist.unlink(missing_ok=True)
        r6a = rig.run(rig.now + 600)
        r6b = rig.run(rig.now + 600)
        chk("⑥ 같은 입력·같은 --now 2회 → snap 바이트 같음 · hist 2줄(shadow=true)",
            r6a["bytes"] == r6b["bytes"] and len(r6b["hist"]) == 2
            and all(h.get("shadow") is True for h in r6b["hist"]))
        rows = r6b["hist"]
        _w(rig.hist, json.dumps({**rows[0], "epoch": rig.now + 600 - 49 * 3600}) + "\n"
           + "".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
        r6c = rig.run(rig.now + 660)
        kept = [float(h["epoch"]) for h in r6c["hist"]]
        chk("⑥ 49시간 전 줄은 잘리고 새 줄은 남음", all(e > rig.now + 660 - 48 * 3600 for e in kept)
            and len(kept) == len(rows) + 1, str(kept))

        # ⑦ 진입점 대역 5구
        ent = Entry(Path(d) / "entry")
        base_ok = ent.run(base=True)
        mine_ok = ent.run()
        chk("⑦ 정상: 수집기 1회 ∧ collect·post 호출 수·stdout·rc = 기준판과 같음(mbox 0)",
            mine_ok["snap"] == 1 and mine_ok["rc"] == base_ok["rc"]
            and (mine_ok["board"], mine_ok["post"], mine_ok["out"]) == (base_ok["board"], base_ok["post"], base_ok["out"])
            and mine_ok["mbox"] == 0, str({k: mine_ok[k] for k in ("rc", "snap", "board", "post", "mbox")}))
        base_f = ent.run(base=True, snap="snap_rc1.py")
        mine_f = ent.run(snap="snap_rc1.py")
        chk("⑦ 수집기 rc 1 → stderr «monitor-snap rc=1» 1줄 ∧ 발행 길 그대로",
            "ft-board-publish: monitor-snap rc=1" in mine_f["err"]
            and mine_f["err"].count("monitor-snap rc=") == 1
            and (mine_f["rc"], mine_f["post"], mine_f["out"]) == (base_f["rc"], base_f["post"], base_f["out"]),
            repr(mine_f["err"][-120:]))
        base_c = ent.run(base=True, snap="snap_slow.py")
        mine_c = ent.run(snap="snap_slow.py", cap="1")
        chk("⑦ 상한 초과(FT_MONITOR_SNAP_CAP=1 · 수집기 5초) → «monitor-snap rc=» 1줄 ∧ 그대로",
            "monitor-snap rc=" in mine_c["err"] and mine_c["err"].count("monitor-snap rc=") == 1
            and (mine_c["rc"], mine_c["post"], mine_c["out"]) == (base_c["rc"], base_c["post"], base_c["out"])
            and mine_c["sec"] < 4, f"{mine_c['sec']}s {mine_c['err'][-80:]!r}")
        base_e = ent.run(base=True, collect_rc="3")
        mine_e = ent.run(collect_rc="3")
        chk("⑦ collect rc 3 → exit 3 ∧ news_fail 1통 그대로(수집 줄이 rc 를 안 가림)",
            mine_e["rc"] == 3 == base_e["rc"] and mine_e["mbox"] == base_e["mbox"] and mine_e["mbox"] == 1,
            f"rc={mine_e['rc']} mbox={mine_e['mbox']}")
        plain = ent.run(args=())
        chk("⑦ 인자 없는 갈래 → 수집기 호출 0", plain["snap"] == 0, str(plain["snap"]))

        # ⑧ 회귀 — 기존 시험 새 판 PASS · 수집기 실행 중 mbox send 0
        reg = {}
        for name, proc in reg_procs.items():
            out, _ = proc.communicate()
            reg[name] = (proc.returncode, out.count("PASS"),
                         sum(1 for l in out.splitlines() if l.startswith("FAIL")))
        chk("⑧ test_board_publish_tick · r2120 PASS · 수집기 실행 중 mbox send 0",
            all(rc == 0 and fails == 0 for rc, _, fails in reg.values()) and mine_ok["mbox"] == 0,
            str(reg))

        # ── 변이 M1~M7 (사본에서만 · 변이마다 원본 사례 1회 대조) ──
        mut = Path(d) / "mut"
        mutate(BIN, mut / "m1", "ft_monitor_snap_src.py",
               'def unk(src: str, at: str) -> dict:\n    return cell(None, src, at, "unknown")',
               'def unk(src: str, at: str) -> dict:\n    return cell(0, src, at, "ok")')
        m1 = rig.run(rig.now + 720, bin_dir=mut / "m1")
        chk("M1 못 잰 칸을 v=0·q=ok 로 → ② 가 FAIL(violation 검출)",
            m1["snap"]["cells"]["hil"]["v"] == 0 or "unknown 인데" in " ".join(shape_bad(m1["snap"]))
            or m1["snap"]["cells"]["hil"]["q"] == "ok", json.dumps(shape_bad(m1["snap"]))[:120])
        mutate(BIN, mut / "m2", "ft_monitor_snap_src.py",
               'items = [{"key": f"{k[0]}:{k[1]}", "id": str(r.get("key") or ""),\n'
               '              "state": "closed" if r.get("state") == "closed" else "open"} for k, r in sorted(last.items())]\n'
               '    v = {"open": sum(1 for i in items if i["state"] == "open"), "items": items}',
               'items = [{"key": f"{k[0]}:{k[1]}", "id": str(r.get("key") or ""),\n'
               '              "state": "closed" if r.get("state") == "closed" else "open"} for k, r in sorted(last.items())]\n'
               '    v = {"open": sum(1 for k, r in last.items() if k[0] == "question" and r.get("state") != "closed"),\n'
               '         "items": items}')
        m2 = rig.run(rig.now + 780, bin_dir=mut / "m2")
        chk("M2 kind=question 만 셈 → ③ 첫 구가 FAIL(9 아님)", m2["snap"]["cells"]["oppa_wait"]["v"]["open"] != 9,
            str(m2["snap"]["cells"]["oppa_wait"]["v"]["open"]))
        mutate(BIN, mut / "m3", "ft_monitor_snap.py",
               '            changed = old.get("fact_changed_at")  # 승계 — 시작점 없음(null)도 그대로 둔다(«서 있음 ?» · ⑬c)',
               '            changed = iso(now)')
        rig.snap.write_text(json.dumps({"schema": 1, "at": "", "cells": r4a["snap"]["cells"],
                                        "goals": {"하네스 운영 정리": {"fact_key": key,
                                                                   "fact_changed_at": old_at}}},
                                       ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
        m3 = rig.run(rig.now + 840, bin_dir=mut / "m3")
        chk("M3 매 틱 now 로 덮음 → ④ 첫 구가 FAIL(72시간 전 아님)",
            m3["snap"]["goals"]["하네스 운영 정리"]["fact_changed_at"] != old_at)
        mutate(BIN, mut / "m4", "ft_monitor_snap_cells.py", "if rc in (0, 1) and m:", "if rc == 0 and m:")
        m4 = rig.run(rig.now + 900, {"DIRECTIVE_RC": "1"}, bin_dir=mut / "m4")
        chk("M4 rc 1 을 unknown 으로 → ⑤ 첫 구 FAIL", m4["snap"]["cells"]["directives"]["q"] == "unknown")
        mutate(BIN, mut / "m5", "ft_monitor_snap.py",
               "def _dump(doc: dict) -> str:\n    return json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(\",\", \":\")) + \"\\n\"",
               "def _dump(doc: dict) -> str:\n    return json.dumps(doc, ensure_ascii=False, separators=(\",\", \":\")) + \"\\n\"")
        sys.path.insert(0, str(mut / "m5"))
        import importlib
        for mod in ("ft_monitor_snap_src", "ft_monitor_snap_cells", "ft_monitor_snap"):
            sys.modules.pop(mod, None)
        m5mod = importlib.import_module("ft_monitor_snap")
        same = m5mod._key({"cells": {"b": 1, "a": 2}}) == m5mod._key({"cells": {"a": 2, "b": 1}})
        sys.path.pop(0)
        for mod in ("ft_monitor_snap_src", "ft_monitor_snap_cells", "ft_monitor_snap"):
            sys.modules.pop(mod, None)
        chk("M5 열쇠 정렬을 뺌 → ⑥ 결정성이 FAIL(순서 다른 같은 객체가 갈림)", not same)
        mutate(Path(ent.dir), mut / "m6", "ft-board-publish.sh",
               '    || echo "ft-board-publish: monitor-snap rc=$?" >&2', '    || exit $?')
        base_m6 = ent.run(base=True, snap="snap_rc1.py")
        m6 = ent.run(snap="snap_rc1.py")
        m6["rc"] = subprocess.run(["bash", str(mut / "m6" / "ft-board-publish.sh"), "--news"],
                                  capture_output=True, text=True,
                                  env={**os.environ, "FT_ROOT": str(ent.root), "FT_BOARD_BIN": str(ent.t / "board.sh"),
                                       "FT_THREAD_POST": str(ent.t / "post.py"), "FT_MBOX": str(ent.t / "mbox.sh"),
                                       "FT_BOARD_POST_ARGS": "--channel C1",
                                       "FT_MONITOR_SNAP_BIN": str(ent.t / "snap_rc1.py"),
                                       "FT_BOARD_NOW": "2026-11-21T22:00:00"}).returncode
        chk("M6 수집 실패를 틱 실패로 올림(exit) → ⑦ 둘째 구 FAIL(rc 가 기준판과 갈림)",
            m6["rc"] != base_m6["rc"], f"{m6['rc']} vs {base_m6['rc']}")
        m7dir = mutate(Path(ent.dir), mut / "m7", "ft-board-publish.sh",
                       'perl -e "alarm ${FT_MONITOR_SNAP_CAP:-70}; exec @ARGV" python3 "${FT_MONITOR_SNAP_BIN:-$HERE/ft_monitor_snap.py}" --root "$ROOT" >/dev/null 2>&1 \\\n'
                       '    || echo "ft-board-publish: monitor-snap rc=$?" >&2',
                       ': ft-news-tick.sh 로 옮김(이 갈래 0)')
        ent.snap_log.unlink(missing_ok=True)
        (ent.root / ".fable-team/state/board/news-last.json").unlink(missing_ok=True)
        subprocess.run(["bash", str(m7dir / "ft-board-publish.sh"), "--news"], capture_output=True, text=True,
                       env={**os.environ, "FT_ROOT": str(ent.root), "FT_BOARD_BIN": str(ent.t / "board.sh"),
                            "FT_THREAD_POST": str(ent.t / "post.py"), "FT_MBOX": str(ent.t / "mbox.sh"),
                            "FT_BOARD_POST_ARGS": "--channel C1",
                            "FT_MONITOR_SNAP_BIN": str(ent.t / "snap.py"),
                            "FT_BOARD_NOW": "2026-11-21T22:00:00", "FT_BOARD_ONLY_CHANGED": "0"})
        moved = ent._count(ent.snap_log)
        chk("M7 호출 줄을 ft-news-tick.sh 로 옮김 → ⑦ 첫 구 FAIL(수집 0회)", moved == 0, f"수집 {moved}회")

    print(f"— 초 {round(time.time() - t0, 1)} · 실패 {len(FAIL)}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
