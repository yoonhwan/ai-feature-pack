#!/usr/bin/env bash
# test_slack_mirror_urgent_desk_r1257.sh — desk 앞 [긴급] 만 슬랙 사람 채널로(claude 정지 중 GPU 과금 경보 유실 · Issue #5603)
#  R1 desk 앞 [긴급] + --urgent-seat → 게시 1 · 멘션 1   R2 desk 앞 보고 → 0   R3 desk 앞 [HIL] → 0
#  R4 planner 앞 [긴급] → 지금 길로 게시 · 멘션 1        R5 slack-oppa 발신 [긴급] → 0   R6 --urgent-seat 없이 R1 행 → 0
#  변이 M1 urgent 갈래 끔 → R1 FAIL · M2 태그 검사 끔 → R2 FAIL
# 실제 슬랙·claude 호출 0 — lib.post/read_token/save_state 스텁 · 임시 state·로그 · 자기 재호출 0 · 고정 sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${SLACK_MIRROR_KIT:-$HERE/../../harness/kit/slack-mirror}"
[ -d "$KIT" ] || { echo "FAIL kit dir missing: $KIT"; exit 1; }
out="$(python3 -I - "$KIT" <<'PYEOF' 2>&1
import argparse, json, re, sys, tempfile
from pathlib import Path

KIT = sys.argv[1]
sys.path.insert(0, KIT)
import byz_mbox_slack_mirror as bm
import mirror_backlog as bl
import mirror_lib as lib
import mirror_summary as summ
import mirror_team as mt

fails = 0
def check(name, cond, detail=""):
    global fails
    if cond:
        print(f"PASS {name}")
    else:
        fails += 1
        print(f"FAIL {name} {detail}")

posts = []
lib.read_token = lambda p: "tok"
lib.post = lambda base, tok, ch, text, thread_ts=None: (posts.append(text), f"9.{len(posts)}")[1]
lib.channel_roots = lambda *a, **k: []
lib.thread_texts = lambda *a, **k: []
lib.save_state = lambda path, st: Path(path).write_text(json.dumps(st), encoding="utf-8")
summ.summarize = lambda cmd, label, text, timeout: {"what": "GPU 가 켜져 있어요", "todo": None}
mt.build = lambda *a, **k: None

tmp = Path(tempfile.mkdtemp())
RESUME = tmp / "ft-resume-cmd.sh"
RESUME.write_text("echo 'claude --resume x'\n", encoding="utf-8")
INBOX = tmp / "ft-inbox.sh"
INBOX.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
DESK, PLAN, MENTION = "byz-planner-desk-claude#90", "byz-planner-master-claude#192", "U123"

def row(seq, to, frm, text):
    return {"seq": seq, "ts": "2026-11-01T00:00:00", "from": frm, "to": to, "body": f"[{frm}->{to}] {text}"}

def run(name, rows, urgent=r"^byz-planner-desk-claude#\d+$", cls=None):
    global posts
    posts = []
    d = tmp / name
    (d / "state").mkdir(parents=True, exist_ok=True)
    log = d / "mailbox.log.jsonl"
    log.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    (d / "state" / "byz_mbox_slack_mirror.p.json").write_text(json.dumps({"last_seq": 0, "pending": None}), encoding="utf-8")
    a = argparse.Namespace(project="p", mailbox=str(log), seat=r"^byz-planner-master-claude#\d+$", channel="C1", repo="",
                           state_dir=str(d / "state"), token_file="~/.hermes/secrets/x.env", mention=MENTION, summarizer_cmd="stub",
                           summary_timeout=7.0, api_base="http://stub", planner_seats="", resume_script=str(RESUME),
                           inbox_bin=str(INBOX), dry_run=False, backlog_max=50, interval=5.0, once=True)
    if urgent is not None:
        a.urgent_seat = urgent
    (cls or bm.Mirror)(a).run_pass()
    return [t for t in posts if " 시작 — " not in t]

URG = row(1, DESK, PLAN, "[긴급] h5517 ccu GPU 2대 끄기 — 70분+ 과금 중")
# R1
p = run("r1", [URG])
check("R1 desk 앞 [긴급] → 게시 1", len(p) == 1, f"{len(p)}건")
check("R1 멘션 1개", bool(p) and p[0].count(f"<@{MENTION}>") == 1, str(p[:1]))
# R2
p = run("r2", [row(1, DESK, PLAN, "보고 — 작업 끝났어요")])
check("R2 desk 앞 보고(태그 없음) → 게시 0", p == [], str(p))
# R3
p = run("r3", [row(1, DESK, PLAN, "[HIL] 정할 것 있어요")])
check("R3 desk 앞 [HIL] → 게시 0", p == [], str(p))
# R4
p = run("r4", [row(1, PLAN, "byz-x-master-claude#1", "[긴급] GPU 켜져 있어요")])
check("R4 planner 앞 [긴급] → 게시 1 · 멘션 1", len(p) == 1 and p[0].count(f"<@{MENTION}>") == 1, str(p[:1]))
check("R4 라벨 긴급 → 머리표 이슈보고", bool(p) and p[0].startswith("[이슈보고]"), str(p[:1]))
# R5
p = run("r5", [row(1, DESK, "slack-oppa", "[긴급] 오빠 글")])
check("R5 slack-oppa 발신 [긴급] → 게시 0(메아리 금지)", p == [], str(p))
# R6
p = run("r6", [URG], urgent=None)
check("R6 --urgent-seat 없이 R1 행 → 게시 0", p == [], str(p))
p = run("r6b", [URG], urgent="")
check("R6 --urgent-seat 빈 값 → 게시 0", p == [], str(p))
# 혼합 5행 — 올라가는 것은 R1·R4 두 건뿐
mix = [row(1, PLAN, "n#0", "보고 a"), URG | {"seq": 2}, row(3, DESK, PLAN, "보고 b"), row(4, DESK, PLAN, "[HIL] c"), row(5, DESK, "slack-oppa", "[긴급] d")]
p = run("mix", mix)
check("혼합 5행 → 게시 2(planner 보고 + desk 긴급)", len(p) == 2, f"{len(p)}건")

# 변이 M1 — urgent 갈래 끔(`urgent and urgent.search(to)` 의 urgent 를 None 취급) → R1 FAIL
src = Path(KIT, "mirror_backlog.py").read_text(encoding="utf-8")
a1 = "bool(urgent and urgent.search(to) and"
assert src.count(a1) == 1
ns = {"__name__": "mutant_backlog"}
sys.path.insert(0, KIT)
exec(compile(src.replace(a1, "bool(False and"), "mutant1", "exec"), ns)
real = bl.is_target
bl.is_target = ns["is_target"]
p = run("m1", [URG])
bl.is_target = real
check("M1 변이: urgent 갈래 끔 → R1 게시 0(R1 FAIL 로 잡힘)", p == [], str(p))
# 변이 M2 — 태그 검사 끔 → desk 앞 보고도 올라감(R2 FAIL)
a2 = ' and lib.classify(str(row.get("body", "")))[0] == "긴급")'
assert src.count(a2) == 1
ns2 = {"__name__": "mutant_backlog2"}
exec(compile(src.replace(a2, ")"), "mutant2", "exec"), ns2)
bl.is_target = ns2["is_target"]
p = run("m2", [row(1, DESK, PLAN, "보고 — 작업 끝났어요")])
bl.is_target = real
check("M2 변이: 태그 검사 끔 → desk 앞 보고도 게시 1(R2 FAIL 로 잡힘)", len(p) == 1, f"{len(p)}건")

print(f"RESULT fail={fails}")
sys.exit(1 if fails else 0)
PYEOF
)"
rc=$?
echo "$out"
if [ "$rc" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILED"; exit 1
