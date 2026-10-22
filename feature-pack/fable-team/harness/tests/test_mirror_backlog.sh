#!/usr/bin/env bash
# test_mirror_backlog.sh — 밀린 쪽지가 상한을 넘으면 원문 대신 요약 1통(r739 · 오빠 슬랙 1792659217 «다시 보냄»)
#  ⓐ 밀린 게시 대상 300건(상한 50) → 지금 판은 300회 원문(변이 ⓗ 가 이 사실을 잡는다)
#  ⓑ 후판 1패스 = 게시 1회(요약 «300건 밀림(seq 101~400) · 원문은 mbox 원장») · last_seq=400 저장 · 요약기 호출 0
#  ⓒ 밀린 3건(≤ 상한) = 지금처럼 한 줄씩 3회(회귀 0)  ⓓ 게시 대상 아닌 행은 셈에 안 넣음
#  ⓔ pending 이 있으면 pending 먼저 1회 게시한 뒤 묶음 판정  ⓕ --backlog-max 0 = 묶음 끔
# 실제 슬랙·claude 호출 0 — lib.post/read_token/save_state 스텁 · 임시 state·로그.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
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

SEAT = re.compile(r"^byz-planner-master-claude#\d+$")
posts, sums, saved = [], [], {}
lib.read_token = lambda p: "tok"
lib.post = lambda base, tok, ch, text, thread_ts=None: (posts.append(text), f"9.{len(posts)}")[1]
lib.channel_roots = lambda *a, **k: []
lib.thread_texts = lambda *a, **k: []
lib.save_state = lambda path, st: (saved.__setitem__(str(path), json.loads(json.dumps(st))), Path(path).write_text(json.dumps(st), encoding="utf-8"))
summ.summarize = lambda cmd, label, text, timeout: (sums.append(text), {"what": "요약", "todo": None})[1]
mt.build = lambda *a, **k: None

tmp = Path(tempfile.mkdtemp())
RESUME = tmp / "ft-resume-cmd.sh"
RESUME.write_text("echo 'claude --resume x'\n", encoding="utf-8")
INBOX = tmp / "ft-inbox.sh"
INBOX.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")

def row(seq, to="byz-planner-master-claude#12", frm="n#0", body=None):
    return {"seq": seq, "ts": "2026-10-22T18:00:00", "from": frm, "to": to,
            "body": body or f"[{frm}->{to}] 보고 {seq}"}

def run(name, rows, last_seq, max_n=50, pending=None):
    """미러 1패스 — 임시 state·로그 · 게시 기록을 돌려준다."""
    global posts, sums
    posts, sums = [], []
    d = tmp / name
    (d / "state").mkdir(parents=True, exist_ok=True)
    log = d / "mailbox.log.jsonl"
    log.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    st = {"last_seq": last_seq, "pending": pending}
    (d / "state" / "byz_mbox_slack_mirror.p.json").write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    a = argparse.Namespace(project="p", mailbox=str(log), seat=r"^byz-planner-master-claude#\d+$", channel="C1", repo="",
                           state_dir=str(d / "state"), token_file="~/.hermes/secrets/x.env", mention="", summarizer_cmd="stub",
                           summary_timeout=7.0, api_base="http://stub", planner_seats="", resume_script=str(RESUME),
                           inbox_bin=str(INBOX), dry_run=False, backlog_max=max_n, interval=5.0, once=True)
    m = bm.Mirror(a)
    m.run_pass()
    out = json.loads((d / "state" / "byz_mbox_slack_mirror.p.json").read_text(encoding="utf-8"))
    cards = [t for t in posts if " 시작 — " not in t]  # 뿌리 글(스레드 생성)은 게시 건수에서 뺀다
    return cards, sums, out

BACKLOG = [row(s) for s in range(101, 401)]  # 300건 · 전부 게시 대상

# ⓑ 후판 — 1통 요약 · 요약기 호출 0 · last_seq=400
p, s, st = run("back", BACKLOG, 100)
check("ⓑ 밀린 300건(상한 50) → 게시 1회", len(p) == 1, f"{len(p)}건: {p[:1]}")
check("ⓑ 본문 «밀린 쪽지 300건을 건너뛰었어요(seq 101~400)» + 원장 안내", bool(p) and "밀린 쪽지 300건을 건너뛰었어요(seq 101~400)" in p[0] and "원문은 mbox 원장에 있어요" in p[0], str(p[:1]))
check("ⓑ 「할 일 없음」 줄 · 원문 본문 0", bool(p) and "할 일 없음" in p[0] and "보고 101" not in p[0], str(p[:1]))
check("ⓑ 요약기 호출 0(묶음은 요약하지 않는다)", s == [], str(len(s)))
check("ⓑ last_seq=400 저장 · pending 없음", st.get("last_seq") == 400 and not st.get("pending"), str(st))

# ⓒ 밀린 3건 = 회귀 0 (한 줄씩 3회 · 요약 3회)
p, s, st = run("small", [row(s) for s in (101, 102, 103)], 100)
check("ⓒ 밀린 3건 → 게시 3회(요약 0)", len(p) == 3 and not any("건너뛰었어요" in t for t in p), f"{len(p)}건")
check("ⓒ last_seq=103", st.get("last_seq") == 103, str(st.get("last_seq")))
check("ⓒ 요약기 호출 3", len(s) == 3, str(len(s)))

# ⓓ 게시 대상 아닌 행은 셈에 안 넣는다 — 60건 중 55건이 남의 좌석 + 오빠 글
others = [row(s, to="other-seat#1") for s in range(200, 250)] + [row(s, frm="slack-oppa") for s in range(250, 255)]
mine = [row(s) for s in range(101, 106)]
mixed = sorted(mine + others, key=lambda r: int(str(r["seq"])))
p, s, st = run("mixed", mixed, 100)
check("ⓓ 게시 대상 5건만 셈 → 묶음 0 · 원문 5회(+공백 알림 1)", len(p) == 6 and sum("못 올라간 보고가" in t for t in p) == 1 and not any("건너뛰었어요" in t for t in p), f"{len(p)}건: {[t[:20] for t in p]}")
check("ⓓ last_seq=254(마지막 행까지 지나감)", st.get("last_seq") == 254, str(st.get("last_seq")))

# ⓔ pending 먼저 1회 → 그 다음 묶음
PEND = {"id": "#99", "seq": 100, "key": "byz-x#1", "what": "밀리기 전 쪽지", "text": "[상태] pending 원문"}
p, s, st = run("pend", BACKLOG, 100, pending=PEND)
check("ⓔ pending 먼저 + 요약 1통 = 게시 2회", len(p) == 2 and "pending 원문" in p[0] and "건너뛰었어요" in p[1], str(p))
check("ⓔ 끝 last_seq=400 · pending 비움", st.get("last_seq") == 400 and not st.get("pending"), str(st))

# ⓕ --backlog-max 0 = 묶음 끔 (300회 원문)
p, s, st = run("off", BACKLOG, 100, max_n=0)
check("ⓕ 상한 0 → 묶음 끔 · 게시 300회", len(p) == 300 and not any("건너뛰었어요" in t for t in p), f"{len(p)}건")
check("ⓕ last_seq=400", st.get("last_seq") == 400, str(st.get("last_seq")))

# ⓘ 기본값 = 50 (인자 없이 parse)
sys.argv = ["x", "--project", "p", "--mailbox", "m", "--seat", "s", "--channel", "C"]
check("ⓘ --backlog-max 기본 50", bm.parse().backlog_max == 50, str(bm.parse().backlog_max))

# ⓗ 변이 — 묶음 분기를 지우면 ⓐ(300회 원문)로 돌아간다 = 이 시험이 잡는다
src = (Path(KIT) / "byz_mbox_slack_mirror.py").read_text(encoding="utf-8")
ANCHOR = bl.SKIP_ANCHOR
assert ANCHOR in src, ANCHOR
ns = {"__name__": "mutant_mirror", "__file__": str(Path(KIT) / "byz_mbox_slack_mirror.py")}
i = src.rfind(ANCHOR)  # 파일 안 ANCHOR 문자열 상수 정의가 먼저 나오므로 «마지막» = 실제 분기
exec(compile(src[:i] + "if False:  # 묶음 끔(변이)" + src[i + len(ANCHOR):], "mutant", "exec"), ns)
real = bm.Mirror
bm.Mirror = ns["Mirror"]
p, s, st = run("mutant", BACKLOG, 100)
bm.Mirror = real
check("ⓗ 변이: 묶음 분기 삭제 → 게시 300회 원문(ⓐ FAIL 로 잡힘)", len(p) == 300 and not any("건너뛰었어요" in t for t in p), f"{len(p)}건")

print(f"RESULT fail={fails}")
sys.exit(1 if fails else 0)
PYEOF
)"
rc=$?
echo "$out"
if [ "$rc" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILED"; exit 1
