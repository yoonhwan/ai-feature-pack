#!/usr/bin/env bash
# test_question_board.sh — 질문 보드: 바이트 상한 3500 + 닫는 사건 = planner 인박스 (R49 · 설계 DESIGN-r49-question-board-20261008 §3 ①~⑨ + §2-r2)
#  ① 36건 → ≤3500 · 오래된 5 + 외 31건  ② 바이트 경계 3499·3500·3501  ③ 첫 줄만 3500 초과 · 멀티바이트 경계  ④ 두 목록 + 경고 2종
#  ⑤ &<> 이스케이프  ⑥ 혼합 그룹 · EMPTY · 파서 변이 대조  ⑦ 실패 7종 = 닫기 0 + 경고 + ERROR + 보드 갱신 진행
#  ⑧ 큐에 없는 seq = ingest 1회(멱등) · ingest 실패 = 인박스 밖  ⑨ 패스당 show 1회  ⑩ --inbox-bin 없으면 exit 1
# 실제 슬랙·인박스·tmux 호출 0 — 스텁 ft-inbox.sh · 슬랙 함수 스텁(받은 text 기록) · 임시 큐 파일.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${SLACK_MIRROR_KIT:-$HERE/../../harness/kit/slack-mirror}"
[ -d "$KIT" ] || { echo "FAIL kit dir missing: $KIT"; exit 1; }
out="$(python3 -I - "$KIT" <<'PYEOF' 2>&1
import argparse, contextlib, io, json, os, subprocess, sys, tempfile, time
from pathlib import Path

KIT = sys.argv[1]
sys.path.insert(0, KIT)
import mirror_board as mb
import mirror_lib as lib
import mirror_questions as mq
import mirror_share as ms

fails = 0
def check(name, cond, detail=""):
    global fails
    if cond:
        print(f"PASS {name}")
    else:
        fails += 1
        print(f"FAIL {name} {detail}")

nb = lambda s: len(s.encode("utf-8"))
tmp = Path(tempfile.mkdtemp())
root = tmp / "root"
inbox = root / ".fable-team" / "state" / "inbox"
inbox.mkdir(parents=True)
PLANNER = "byz-planner-master-claude#12"
QUEUE = inbox / "byz-planner-master-claude.jsonl"

# 슬랙 스텁 — 받은 text 를 기록한다(API 0)
sent = []
lib.paged = lambda *a, **k: []
lib.post = lambda base, tok, ch, text, *a, **k: (sent.append(text), "9.1")[1]
lib.api_call = lambda base, tok, method, params, **k: (sent.append(params["text"]), {"ok": True})[1]
ms.live_planner = lambda seats=None: (PLANNER, "살아 있음")

# 스텁 ft-inbox.sh — show 출력·rc 는 파일로 고정 · ingest 는 큐 파일에 seq 를 덧붙인다(STUB_INGEST_FAIL 있으면 rc=1)
stub = tmp / "ft-inbox.sh"
stub.write_text('''#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case "$1" in
  show) cat "$STUB_SHOW"; exit "$(cat "$STUB_RC" 2>/dev/null || echo 0)" ;;
  ingest) [ -e "$STUB_INGEST_FAIL" ] && { echo "REJECT seq=$2 없음" >&2; exit 1; }
          python3 -c 'import json,sys; open(sys.argv[1], "a").write(json.dumps({"seq": int(sys.argv[2])}) + "\\n")' "$FT_ROOT/.fable-team/state/inbox/byz-planner-master-claude.jsonl" "$2" ;;
esac
''', encoding="utf-8")
stub.chmod(0o755)
os.environ.update(STUB_LOG=str(tmp / "stub.log"), STUB_SHOW=str(tmp / "show.txt"), STUB_RC=str(tmp / "rc.txt"), STUB_INGEST_FAIL=str(tmp / "ingest_fail"))
def calls(verb):
    p = tmp / "stub.log"
    return sum(1 for ln in (p.read_text(encoding="utf-8").splitlines() if p.exists() else []) if ln.split()[0] == verb)
def reset(show="EMPTY\n", rc=0, queue=(), ingest_fail=False):
    for n in ("stub.log", "ingest_fail"):
        (tmp / n).unlink(missing_ok=True)
    (tmp / "show.txt").write_text(show, encoding="utf-8")
    (tmp / "rc.txt").write_text(str(rc), encoding="utf-8")
    QUEUE.write_text("".join(json.dumps({"seq": s}) + "\n" for s in queue), encoding="utf-8")
    if ingest_fail:
        (tmp / "ingest_fail").write_text("1", encoding="utf-8")
ns = argparse.Namespace(inbox_bin=str(stub), api_base="http://invalid.example", channel="C")
def store(n, base=int(time.time()) - 20 * 3600, state="open", what=lambda i: f"유료 결제 라이브 전환 승인 여부를 정해 주세요 {i}번 사안 요지"):
    p = tmp / f"q{len(list(tmp.glob('q*.json')))}.json"
    for i in range(n):
        mq.add(p, 100 + i, {"key": f"#{900 + i}-결제라이브전환", "seat": f"s#{i}", "what": what(i), "options": [], "thread_ts": f"{i}.1"})
    d = mq.load(p)
    for i, e in enumerate(d["open"].values()):
        e["asked_at"], e["state"] = base + i * 60, state
    mq._save(p, d)
    return p
def board_text(p):
    sent.clear()
    mq.update_board(p, "http://invalid.example", "tok", "C", "seats")
    return sent[-1] if sent else mq.load(p)["meta"]["board_text"]  # 글이 같으면 API 0 — 게시돼 있는 글을 본다

# ── ① 36건 → 슬랙 스텁이 받은 text ≤ 3500 · 오래된 5 + 외 31건
q36 = store(36)
d36 = mq.load(q36)
naive = f"{mq.BOARD_HEAD} 36건 — 결정 자리: {PLANNER} — " + " · ".join(f"{lib.esc(e['key'])} {lib.esc(e['what'])[:40]} (0분)" for e in d36["open"].values())
check("① 픽스처 현실성: 옛 방식(전부 이어 붙임)은 거부선(4000) 초과", nb(naive) > 4000, nb(naive))
t36 = board_text(q36)
lines = t36.split("\n")
oldest5 = [e["key"] for e in sorted(d36["open"].values(), key=lambda e: e["asked_at"])[:5]]
sixth = sorted(d36["open"].values(), key=lambda e: e["asked_at"])[5]["key"]
check("① 슬랙 스텁 text ≤ 3500 바이트", nb(t36) <= 3500, nb(t36))
check("① 가장 오래된 5줄 + `… 외 31건`", [ln.split()[0] for ln in lines[1:6]] == oldest5 and lines[6] == "… 외 31건" and len(lines) == 7, t36)
check("① 6번째 이후 질문은 보드에 없다", sixth not in t36)
check("① 첫 줄 = 건수 + 결정 자리", lines[0] == f"[상태] 결정 대기 36건 — 결정 자리: {PLANNER}", lines[0])
check("① 저장소 항목은 지우지 않는다(open 36 그대로)", len(mq.load(q36)["open"]) == 36)
if os.environ.get("QB_PRINT"):
    print(f"BOARD_BEGIN bytes={nb(t36)}\n{t36}\nBOARD_END")

# ── ② 바이트 경계 3499·3500·3501 (최종 text 기준)
for n, want_fold in ((3499, False), (3500, False), (3501, True)):
    one = "x" * (n - 2)  # "H\n" + one → n 바이트
    r = mb.fit_board("H", [(None, [one])])
    check(f"② 경계 {n}: 최종 ≤ 3500", nb(r) <= 3500, nb(r))
    check(f"② 경계 {n}: " + ("한 줄이 접힘" if want_fold else "그대로 실림"), (r == "H\n… 외 1건") if want_fold else (r == f"H\n{one}" and nb(r) == n), nb(r))
# 접기 표식 예산을 «미리» 포함 — 줄 2개: 첫 줄 + 접기 줄이 딱 맞는 경우
r = mb.fit_board("H", [(None, ["a" * 3400, "b" * 100])])
check("② 줄 1 만 실리고 접기 표식 포함해도 ≤ 3500", nb(r) <= 3500 and r.endswith("… 외 1건") and "b" * 10 not in r, nb(r))

# ── ③ 첫 줄만 3500 초과(결정 자리 사유가 김) → 정확히 ≤ 3500 + `…` · 멀티바이트(3바이트 한글)가 경계에 걸려도 깨짐 0
huge = "가" * 2000
t = mb.render_board({"1": {"state": "open", "key": "#1", "what": "요지", "asked_at": 0}}, now=60.0, place=huge)
check("③ 첫 줄만 3500 초과 → ≤ 3500 + `…`", nb(t) <= 3500 and t.endswith("…") and "\n" not in t, nb(t))
check("③ 3바이트 경계 절단 — 깨진 문자 0 · UTF-8 왕복", "�" not in t and t.encode("utf-8").decode("utf-8") == t)

# ── ④ 두 목록 + 경고 2종 동시
both = {}
both.update({str(i): {"state": "open", "key": f"#{i}", "what": "대기 요지" * 8, "asked_at": i} for i in range(36)})
both.update({str(100 + i): {"state": "delivered", "key": f"#{100 + i}", "what": "전달 요지" * 8, "asked_at": i} for i in range(12)})
t = mb.render_board(both, now=7200.0, place=PLANNER, notes=["인박스 밖 2건", "정리 확인 불가(show rc=1)"])
check("④ 두 목록 + 경고 2종: ≤ 3500", nb(t) <= 3500, nb(t))
check("④ 경고 2종은 첫 줄 끝", t.split("\n")[0].endswith("인박스 밖 2건 — 정리 확인 불가(show rc=1)"), t.split("\n")[0])
check("④ planner 전달됨 12건 제목 + 두 접기 표식(외 31건 · 외 7건)", "planner 전달됨 12건" in t and "… 외 31건" in t and "… 외 7건" in t, t)

# ── ⑤ `&<>` 이스케이프로 길어지는 요지 — 단언 대상 = 슬랙 스텁이 받은 실제 text
amp = store(36, what=lambda i: "<&>" * 13)
t = board_text(amp)
check("⑤ &<> 이스케이프 뒤 실제 text ≤ 3500", nb(t) <= 3500 and "&lt;" in t and "<" not in t and ">" not in t, nb(t))

# ── ⑥ 닫는 사건: 혼합 그룹 · EMPTY
def scenario(open_seqs, queue, show, expect_open, expect_resolved, name, rc=0):
    reset(show=show, rc=rc, queue=queue)
    p = tmp / f"s{name}.json"
    for s in open_seqs:
        mq.add(p, s, {"key": f"#{s}", "seat": "s#1", "what": "w", "options": [], "thread_ts": f"{s}.1"})
    mb.sweep(ns, p, "seats", root)
    d = mq.load(p)
    return sorted(int(k) for k in d["open"]) == expect_open and sorted(int(k) for k in d["resolved"]) == expect_resolved, d
MIX = "[HIL] g1 seq=10,11 미닫힘=11 from=byz-cfo-master#53 원문=/p/10.txt | 첫 줄\n"
ok, d = scenario([10, 11], [10, 11], MIX, [11], [10], "mix")
check("⑥ 혼합 그룹 `seq=10,11 미닫힘=11` → 10 닫힘 · 11 open", ok, d)
ok, d = scenario([10, 11, 12], [10, 11, 12], "EMPTY\n", [], [10, 11, 12], "empty")
check("⑥ `EMPTY` → 큐에 있는 열린 질문 전부 닫힘", ok, d)
# 변이 대조: `seq=` 첫 값만 뽑는 잘못된 파서로 바꾸면 위 기대가 어긋난다(= 이 시험이 FAIL 로 바뀐다)
real = mb.parse_show
mb.parse_show = lambda out: {int(out.split("seq=")[1].split(",")[0].split()[0])} if out.strip() != "EMPTY" else set()
ok_mut, _ = scenario([10, 11], [10, 11], MIX, [11], [10], "mut")
mb.parse_show = real
check("⑥ 변이 대조: `seq=` 첫 값만 뽑는 파서 → 혼합 그룹 시험이 FAIL", not ok_mut)

# ── ⑦ 실패 7종: 닫기 0 + 경고 + stderr ERROR + 보드 갱신은 진행
def failing(name, show="EMPTY\n", rc=0, queue=(10, 11), planner=PLANNER, corrupt=False, want="정리 확인 불가"):
    reset(show=show, rc=rc, queue=queue)
    if corrupt:
        QUEUE.write_text("{깨짐\n", encoding="utf-8")
    p = tmp / f"f{name}.json"
    for s in (10, 11):
        mq.add(p, s, {"key": f"#{s}", "seat": "s#1", "what": "w", "options": [], "thread_ts": f"{s}.1"})
    ms.live_planner = lambda seats=None: (planner, "세션 없음" if planner is None else "살아 있음")
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        mb.sweep(ns, p, "seats", root)
    ms.live_planner = lambda seats=None: (PLANNER, "살아 있음")
    board = board_text(p)
    notes = mq.load(p)["meta"].get("board_notes", [])
    check(f"⑦ {name}: 닫기 0", len(mq.load(p)["open"]) == 2 and not mq.load(p)["resolved"])
    check(f"⑦ {name}: 보드 첫 줄 경고 + stderr ERROR + 갱신 진행", want in board.split("\n")[0] and "ERROR:" in err.getvalue() and bool(notes), (board, err.getvalue()))
failing("rc=0 빈 출력", show="")
failing("깨진 줄 섞임", show="[HIL] g seq=10 미닫힘=10 from=a 원문=/p | x\n이상한 줄\n")
failing("`미닫힘=x`", show="[HIL] g seq=10 미닫힘=x from=a 원문=/p | x\n")
failing("rc=1", show="", rc=1)
failing("planner None", planner=None)
failing("큐 JSON 오류", corrupt=True)
failing("EMPTY 와 다른 줄 혼합", show="EMPTY\n[HIL] g seq=10 미닫힘=10 from=a 원문=/p | x\n")

# ── ⑧ 큐에 없는 seq → ingest 1회 · 다음 패스 0(멱등) · ingest 실패 → 인박스 밖 1건
reset(show="[HIL] g seq=20 미닫힘=20 from=a 원문=/p | x\n", queue=())
p = tmp / "ing.json"
mq.add(p, 20, {"key": "#20", "seat": "s#1", "what": "w", "options": [], "thread_ts": "20.1"})
mb.sweep(ns, p, "seats", root)
check("⑧ 큐에 없는 seq → ingest 1회 · 적재된 질문은 닫히지 않음(미닫힘=20)", calls("ingest") == 1 and "20" in mq.load(p)["open"])
mb.sweep(ns, p, "seats", root)
check("⑧ 다음 패스 ingest 0(멱등)", calls("ingest") == 1, calls("ingest"))
reset(show="EMPTY\n", queue=(), ingest_fail=True)
p = tmp / "ingf.json"
mq.add(p, 21, {"key": "#21", "seat": "s#1", "what": "w", "options": [], "thread_ts": "21.1"})
with contextlib.redirect_stderr(io.StringIO()):
    mb.sweep(ns, p, "seats", root)
check("⑧ ingest 실패 → 닫지 않음(EMPTY 여도) + `인박스 밖 1건`", "21" in mq.load(p)["open"] and mq.load(p)["meta"]["board_notes"] == ["인박스 밖 1건"], mq.load(p)["meta"])
check("⑧ 인박스 밖 경고는 보드 첫 줄에 보인다", board_text(p).split("\n")[0].endswith("인박스 밖 1건"))
# 실패한 seq 는 프로세스 수명 동안 다시 부르지 않는다 — 2·3패스 ingest 0 · 경고는 3패스 모두 보드에 · ERROR 는 새 실패 때만 1회
def failed_passes():
    mb._INGEST_FAILED.clear()
    reset(show="EMPTY\n", queue=(), ingest_fail=True)
    q = tmp / "ingf3.json"
    mq.add(q, 22, {"key": "#22", "seat": "s#1", "what": "w", "options": [], "thread_ts": "22.1"})
    errs, boards, per_pass = [], [], []
    for _ in range(3):
        before = calls("ingest")
        e = io.StringIO()
        with contextlib.redirect_stderr(e):
            mb.sweep(ns, q, "seats", root)
        per_pass.append(calls("ingest") - before)
        errs.append(e.getvalue().count("ERROR:"))
        boards.append(board_text(q).split("\n")[0])
    return per_pass, errs, boards
per_pass, errs, boards = failed_passes()
check("⑧ 적재 실패 seq: 1패스 호출 1 · 2·3패스 호출 0", per_pass == [1, 0, 0], per_pass)
check("⑧ `인박스 밖 1건` 3패스 모두 보드에 유지", all(b.endswith("인박스 밖 1건") for b in boards), boards)
check("⑧ ERROR 줄은 새 실패 때만 1회", errs == [1, 0, 0], errs)
# 변이 대조: 기억 집합을 지우면(= 매 패스 다시 시도) 2패스 호출이 1 → 위 시험이 FAIL
_real_ingest = mb._ingest_missing
def _forgetful(inbox_bin, root, seqs):
    mb._INGEST_FAILED.clear()
    _real_ingest(inbox_bin, root, seqs)
mb._ingest_missing = _forgetful
per_mut, _, _ = failed_passes()
mb._ingest_missing = _real_ingest
check("⑧ 변이 대조: 기억 집합을 지우면 2패스 호출 1 → FAIL", per_mut[1] == 1 and per_mut != [1, 0, 0], per_mut)
mb._INGEST_FAILED.clear()

# ── ⑨ 패스당 show 호출 = 1 (열린 질문 36건이어도) · 열린 질문 0 이면 0
reset(show="EMPTY\n", queue=range(100, 136))
p = tmp / "cnt.json"
for s in range(100, 136):
    mq.add(p, s, {"key": f"#{s}", "seat": "s#1", "what": "w", "options": [], "thread_ts": f"{s}.1"})
mb.sweep(ns, p, "seats", root)
check("⑨ 패스당 show 호출 = 1 · 36건 전부 닫힘", calls("show") == 1 and not mq.load(p)["open"], calls("show"))
check("⑨ 닫힌 36건 → 보드 `결정 대기 0건`", board_text(p).startswith("[상태] 결정 대기 0건"))
mb.sweep(ns, p, "seats", root)
check("⑨ 열린 질문 0 → show 호출 추가 0", calls("show") == 1)
keep = "".join(f"[HIL] g{s} seq={s} 미닫힘={s} from=a 원문=/p | x\n" for s in range(100, 105))
reset(show=keep, queue=range(100, 136))
p = tmp / "cnt31.json"
for s in range(100, 136):
    mq.add(p, s, {"key": f"#{s}", "seat": "s#1", "what": "w", "options": [], "thread_ts": f"{s}.1"})
mb.sweep(ns, p, "seats", root)
t = board_text(p)
check("⑨ 36건 중 31건 닫기 → open 5 · 보드 `결정 대기 5건` · 접기 표식 없음", sorted(int(k) for k in mq.load(p)["open"]) == list(range(100, 105)) and t.startswith("[상태] 결정 대기 5건") and "외" not in t, t)

# ── ⑩ --inbox-bin 없으면 시작 시 exit 1 (미러 · inbound 둘 다)
st = tmp / "st"
mbox = tmp / ".fable-team" / "comm"
mbox.mkdir(parents=True)
(mbox / "mailbox.log.jsonl").write_text("", encoding="utf-8")
(mbox / "mbox.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
(tmp / "tok.env").write_text("YOONHWAN_BOT_TOKEN=x\n", encoding="utf-8")
for name, argv in (("미러", ["byz_mbox_slack_mirror.py", "--project", "t", "--mailbox", str(mbox / "mailbox.log.jsonl"), "--seat", "^x$", "--channel", "C", "--state-dir", str(st), "--token-file", str(tmp / "tok.env"), "--once"]),
                   ("inbound", ["byz_slack_mbox_inbound.py", "--channel", "C", "--human", "U1", "--mbox", str(mbox / "mbox.sh"), "--seats-file", str(tmp / "seats.json"), "--state-dir", str(st), "--token-file", str(tmp / "tok.env"), "--once"])):
    r = subprocess.run([sys.executable, str(Path(KIT) / argv[0]), *argv[1:]], capture_output=True, text=True, timeout=60)
    check(f"⑩ {name}: --inbox-bin 없으면 exit 1 + 사유", r.returncode == 1 and "--inbox-bin" in r.stderr, (r.returncode, r.stderr[-200:]))
# 소스 줄 수 200 이하(고친 파일)
for f in ("mirror_board.py", "mirror_questions.py", "byz_mbox_slack_mirror.py", "byz_slack_mbox_inbound.py"):
    n = len((Path(KIT) / f).read_text(encoding="utf-8").splitlines())
    check(f"줄 수 ≤ 200: {f}", n <= 200, n)
print("FAILS", fails)
sys.exit(1 if fails else 0)
PYEOF
)"
rc=$?
echo "$out" | grep -E '^(PASS|FAIL)' || true
echo "$out" | sed -n '/^BOARD_BEGIN/,/^BOARD_END/p'
if [ "$rc" -ne 0 ]; then echo "$out" | grep -vE '^(PASS|FAIL|BOARD_)' | tail -15; echo "FAILED rc=$rc"; exit 1; fi
echo "ALL PASS"
