#!/usr/bin/env bash
# test_slack_readonly_share.sh — 슬랙 = 읽기 전용 공유판 (판정 497 · 설계 DESIGN-slack-readonly-share-20261008 §4-r2)
#  ① 답장 요구 문구 출력 0  ② 요약 교정  ③ Q 표기 경계  ④ live_planner 사유 5종·살아 있음  ⑤ _hil_route 무시·멘션 조건
#  ⑥ 모든 글 첫 줄 머리표  ⑦ 머리표 도입 전 첫 줄도 같은 글로 찾기  ⑧ inbound 전달  ⑨ 옛 원장 이관 fixture 4
# 슬랙 API·실제 tmux·실제 LLM 0 — 함수 직접 호출 + 가짜 tmux 스텁 + 가짜 요약기 + 가짜 history.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${SLACK_MIRROR_KIT:-$HERE/../../scripts/harness-install/slack-mirror}"
[ -d "$KIT" ] || { echo "FAIL kit dir missing: $KIT"; exit 1; }
out="$(python3 -I - "$KIT" <<'PYEOF' 2>&1
import argparse, json, os, re, stat, sys, tempfile, textwrap
from pathlib import Path

KIT = sys.argv[1]
sys.path.insert(0, KIT)
import byz_github_slack_mirror as gm
import byz_proposal_publish as pp
import byz_slack_mbox_inbound as bi
import byz_thread_post as tp
import magazine_reattach as mre
import magazine_slack as ms_
import magazine_summary as msum
import mirror_inbound as ib
import mirror_lib as lib
import mirror_plan
import mirror_questions as mq
import mirror_share as ms
import mirror_summary as summ
import resume_block as rb
from byz_mbox_slack_mirror import format_gap

fails = 0
def check(name, cond, detail=""):
    global fails
    if cond:
        print(f"PASS {name}")
    else:
        fails += 1
        print(f"FAIL {name} {detail}")

tmp = Path(tempfile.mkdtemp())
# 가짜 tmux: has-session -t =NAME → FAKE_TMUX_ALIVE(공백 구분) 에 NAME 이 있으면 0, 없으면 1
stub = tmp / "tmux"
stub.write_text('#!/usr/bin/env bash\n[ "$1" = has-session ] || exit 2\nname="${3#=}"\ncase " ${FAKE_TMUX_ALIVE:-} " in *" $name "*) exit 0;; esac\nexit 1\n')
stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
os.environ["MIRROR_TMUX"] = str(stub)
resume = tmp / "ft-resume-cmd.sh"
resume.write_text('#!/usr/bin/env bash\necho "tmuxc resume $1"\n')
seats = tmp / "seats-planner.json"
def write_seats(master, hil_route="byz-planner-master-claude#11"):
    seats.write_text(json.dumps({"_master": master, "_hil_route": hil_route}), encoding="utf-8")
def alive(*names):
    os.environ["FAKE_TMUX_ALIVE"] = " ".join(names)
os.environ.pop("MIRROR_PLANNER_SEATS", None)
HEADS = ("[작업상황] ", "[이슈보고] ", "[변경내용] ", "[상태] ")
BAN = ("답하는 법", "답해 주세요", "다시 답해", "확인해 주세요", "답을 기다리는", "번호나 한 줄", "이 스레드에 답", "오빠 판정", "오빠 할 일", "오빠가 결정할 것", "오빠 결정")
def clean(name, text):
    bad = [b for b in BAN if b in text] + re.findall(r"(?<![A-Za-z0-9])Q\d+(?!\d)", text)
    check(f"① 답장 요구 0: {name}", not bad, f"{bad} in {text[:200]!r}")

# ── ④ live_planner 사유 5종 + 살아 있음 (⑤ _hil_route 가 달라도 _master)
write_seats("byz-planner-master-claude#12"); alive("byz-planner-master-claude#11", "byz-planner-master-claude#12")
name, why = ms.live_planner(seats)
check("④ 살아 있음 → _master 이름 (_hil_route=#11 이어도 #12)", name == "byz-planner-master-claude#12", (name, why))
check("⑤ _hil_route 는 읽지 않는다", name != "byz-planner-master-claude#11")
r = {}
r["명부 없음"] = ms.live_planner(tmp / "none.json")
bad_json = tmp / "bad.json"; bad_json.write_text("{ not json")
r["JSON 오류"] = ms.live_planner(bad_json)
nomaster = tmp / "nomaster.json"; nomaster.write_text(json.dumps({"_hil_route": "x#1"}))
r["_master 없음"] = ms.live_planner(nomaster)
os.environ["MIRROR_TMUX"] = str(tmp / "no-such-tmux")
r["tmux 실행 실패"] = ms.live_planner(seats)
os.environ["MIRROR_TMUX"] = str(stub); alive()
r["세션 없음"] = ms.live_planner(seats)
for why, (n, got) in r.items():
    check(f"④ 사유 「{why}」 → 이름 None · 사유 일치", n is None and got == why, (n, got))
alive("byz-planner-master-claude#12")
line_ok = ms.decision_line("byz-x#1", seats)
check("③ 결정 자리 줄(살아 있음)", line_ok.startswith("결정 자리: byz-planner-master-claude#12 (그 세션이 인터뷰를 띄웁니다)") and "질문 올린 좌석: byz-x#1" in line_ok, line_ok)
alive()
line_bad = ms.decision_line("byz-x#1", seats)
check("③ 결정 자리 줄(세션 없음) = 확인 불가 · 대체 이름 0", "확인 불가" in line_bad and "세션 없음" in line_bad and "#12" not in line_bad and "#11" not in line_bad, line_bad)

# ── ③ 검사 정규식 반례 (A-r3)
for t, expect_none in (("전문을 확인해 주세요", True), ("Q3", True), ("Q3에 대해", True), ("(질문Q12)", True), ("이 스레드에 답해 주세요", True),
                       ("FAQ3", False), ("Q 만 단독", False), ("정상 문장이에요", False)):
    check(f"③ share_guard({t!r}) {'걸림' if expect_none else '통과'}", (ms.share_guard(t) is None) == expect_none)

# ── ② 요약 교정 — 가짜 요약기(LLM 0)
fake_sum = tmp / "sum.py"
fake_sum.write_text("import os, sys\nsys.stdin.read()\nprint(os.environ['FAKE_SUMMARY'])\n")
def summarize(obj, label="보고", text="본문입니다."):
    os.environ["FAKE_SUMMARY"] = json.dumps(obj, ensure_ascii=False)
    return summ.summarize(f"{sys.executable} {fake_sum}", label, text, 20)
row = {"from": "byz-x#1", "seq": 7}
alive("byz-planner-master-claude#12")
s = summarize({"what": "전문을 확인해 주세요", "todo": None})
card = lib.format_row(row, "보고", "U1", s, "본문입니다. 둘째 문장", block="BLK", seats=str(seats))
check("② 요약 성공 + what 답장 요구 → 교정 표시 + 원문 첫 문장", "(요약 문구 교정)" in card and "본문입니다." in card and "확인해 주세요" not in card, card)
s = summarize({"what": "슬랙이 켜졌어요", "todo": "이 스레드에 답해 주세요"}, "HIL", "본문입니다. 이 스레드에 답해 주세요")  # todo 는 원문에서 복사된 문장일 때만 남는다(판정 423 ②)
card = lib.format_row(row, "HIL", "U1", s, "본문", block="BLK", seats=str(seats))
check("② todo 답장 요구 + HIL → 「정할 것: 전문 참고」 + 교정", "정할 것: 전문 참고" in card and "(요약 문구 교정)" in card and "답해 주세요" not in card, card)
card = lib.format_row(row, "보고", "", None, "전문을 확인해 주세요. 나머지 문장", block="BLK", seats=str(seats))
check("② 요약 실패 + 원문 첫 문장이 답장 요구 → 생략 문구", "원문 요약 생략 — 아래 전문 참고" in card and "(요약 문구 교정)" in card and "(원문 그대로)" in card, card)
for qtxt in ("Q3 질문입니다", "Q3에 대해 알려요", "(질문Q12) 입니다"):
    s = summarize({"what": qtxt, "todo": None})
    card = lib.format_row(row, "보고", "", s, "원문 본문", block="BLK", seats=str(seats))
    check(f"③ what={qtxt!r} → 교정", "(요약 문구 교정)" in card, card)
for okt in ("FAQ3 문서를 고쳤어요", "Q 단독 표기는 통과"):
    s = summarize({"what": okt, "todo": None})
    card = lib.format_row(row, "보고", "", s, "원문 본문", block="BLK", seats=str(seats))
    check(f"③ what={okt!r} → 통과(교정 0)", "(요약 문구 교정)" not in card and okt in card, card)
full = "이 스레드에 답해 주세요 — 원문 그대로 남는다"
card = lib.format_row(row, "보고", "", summarize({"what": "정상이에요", "todo": None}), "본문", block="BLK", full=full, seats=str(seats))
check("② 전문 인용 블록은 원문 보존 + 머리 줄 교체", full in card and "전문(원문 그대로 · 이 스레드는 답을 받지 않습니다)" in card, card)

# ── ① HIL 카드 렌더 (RESULT 에 복붙할 가짜 HIL 카드) + 13 문구 출력 0
s = summarize({"what": "배포 방식을 정해야 해요", "todo": "A 와 B 중 하나를 정해요"}, "HIL")
opts = mq.parse_options("어떻게 할까요?\n1) A 로 간다\n2) B 로 간다")
hil_card = lib.format_row(row, "HIL", "U0AC2JF0M7D", s, "원문", block=rb.mirror_block({"from": "byz-x#1", "seq": 7}, "HIL", resume),
                          urls=["https://github.com/o/r/issues/7"], options_text=mq.format_options(opts), seats=str(seats))
print("HIL_CARD_BEGIN\n" + hil_card + "\nHIL_CARD_END")
clean("HIL 카드", hil_card)
check("① HIL 카드: 첫 줄 머리표 + 결정 자리 줄 + 선택지(참고)", hil_card.startswith("[이슈보고] ") and "\n<@U0AC2JF0M7D> 결정 자리: byz-planner-master-claude#12" in hil_card and "선택지(참고): 1) A 로 간다 2) B 로 간다" in hil_card, hil_card)
check("① 「다음」 칸 = 결정 대기", "다음: 결정 대기" in hil_card)
clean("선택지 없는 HIL", lib.format_row(row, "HIL", "U1", None, "아무 말", block="BLK", options_text=mq.format_options([]), seats=str(seats)))
check("① format_options 빈 선택지 = 빈 문자열(줄 생략)", mq.format_options([]) == "")
check("⑤ 멘션은 결정 자리 줄에만 — 보고(비 HIL)에는 멘션 0", "<@" not in lib.format_row(row, "보고", "U1", None, "아무 말", block="BLK", seats=str(seats)))
check("⑤ HIL 인데 멘션 칸이 비면 멘션 0", "<@" not in lib.format_row(row, "HIL", "", None, "아무 말", block="BLK", seats=str(seats)))

# ── ① 보드 · ④ 결정 자리 확인 불가 문구
board = mq.render_board({"1": {"state": "open", "key": "#7", "what": "이 스레드에 답해 주세요", "asked_at": 0},
                         "2": {"state": "delivered", "key": "#8", "what": "정상 요지", "asked_at": 0}}, now=120.0, place=ms.place_text(seats))
clean("보드", board)
check("① 보드 제목 [상태] 결정 대기 + 결정 자리 · planner 전달됨", board.startswith("[상태] 결정 대기 1건 — 결정 자리: ") and "planner 전달됨 1건" in board, board)

# ── ① mirror_plan — 되묻기 0 · 수신자 = @planner 역할
qpath = tmp / "q.json"
mq.add(qpath, 11, {"key": "#7", "seat": "byz-cfo-master-claude#53", "what": "x", "options": [], "thread_ts": "100.1"})
mq.add(qpath, 12, {"key": "#7", "seat": "byz-cfo-master-claude#53", "what": "y", "options": [], "thread_ts": "100.1"})
a_plan = argparse.Namespace(api_base="http://invalid.example", channel="C", seats_file=str(tmp / "seats-x.json"))
lib.paged = lambda *a, **k: []
for label, m in (("새 글", {"text": "새 글", "thread_ts": ""}), ("질문 여럿", {"text": "답이에요", "thread_ts": "100.1"}),
                 ("없는 번호", {"text": "Q99 답이에요", "thread_ts": "100.1"}), ("열린 질문 없음", {"text": "그냥 글", "thread_ts": "900.1"})):
    p = mirror_plan.plan(a_plan, "tok", qpath, m)
    check(f"① plan({label}): 되묻기 없음 · 수신자에 @planner", "ask" not in p and "@planner" in p["recips"], p)
mq.add(qpath, 13, {"key": "#9", "seat": "byz-cfo-master-claude#53", "what": "z", "options": [], "thread_ts": "200.1"})
p = mirror_plan.plan(a_plan, "tok", qpath, {"text": "1번", "thread_ts": "200.1"})
check("① plan(질문 1건): 수신자 = [질문 좌석, @planner]", p["recips"] == ["byz-cfo-master-claude#53", "@planner"], p)

# ── ① GitHub 사건 4종 + ⑥ 머리표
g = gm.GithubMirror.__new__(gm.GithubMirror)
g.a = argparse.Namespace(repo="o/r", mention="U0AC2JF0M7D", summarizer_cmd=f"{sys.executable} {fake_sum}", summary_timeout=20.0, planner_seats=str(seats))
os.environ["FAKE_SUMMARY"] = json.dumps({"what": "이슈가 달라졌어요", "todo": None}, ensure_ascii=False)
issue = {"number": 9, "title": "reply 관련 제목 Q3", "html_url": "https://github.com/o/r/issues/9"}
heads = {}
for kind, want in (("opened", "[이슈보고] "), ("hil", "[이슈보고] "), ("closed", "[변경내용] "), ("merged", "[변경내용] ")):
    t = g._item(issue, kind)["text"]
    heads[kind] = t
    check(f"⑥ GitHub {kind} 첫 줄 머리표", t.startswith(want), t.split("\n")[0])
    clean(f"GitHub {kind}", t.replace(issue["title"], ""))
check("① GitHub hil: 결정 자리 줄 + 멘션", "결정 자리: byz-planner-master-claude#12" in heads["hil"] and "<@U0AC2JF0M7D>" in heads["hil"])
check("⑤ GitHub 비 hil: 멘션 0", "<@" not in heads["opened"])
os.environ["FAKE_SUMMARY"] = "not json"
t = g._item(issue, "closed")["text"]
check("① GitHub 요약 실패: 제목(사실)은 그대로", "reply 관련 제목 Q3" in t and "(원문 그대로)" in t and t.startswith("[변경내용] "), t)

# ── ⑥ 나머지 종류의 첫 줄 머리표
def head_ok(name, text):
    check(f"⑥ 첫 줄 머리표: {name}", text.startswith(HEADS), text.split("\n")[0])
head_ok("mbox 보고", lib.format_row(row, "보고", "", None, "본문", block="B", seats=str(seats)))
head_ok("mbox BLOCK", lib.format_row(row, "BLOCK", "", None, "본문", block="B", seats=str(seats)))
check("⑥ BLOCK = 이슈보고 · 보고 = 작업상황", lib.format_row(row, "BLOCK", "", None, "x", block="B").startswith("[이슈보고] ") and lib.format_row(row, "보고", "", None, "x", block="B").startswith("[작업상황] "))
head_ok("스레드 루트", lib.root_text("#7", "배포 이야기", "https://github.com/o/r/issues/7"))
head_ok("기록 공백", format_gap(5, 8))
head_ok("질문 보드", board)
head_ok("매거진 뿌리", ms_.root_text("2026-10-08", ["가", "나", "다"], None, 2, "U1", None, None, str(seats)))
head_ok("매거진 실패", ms_.failure_text("ValueError: x"))
head_ok("매거진 재첨부 답글", mre.reply_text("2026-10-08", "r1", None))
prop = {"key": "ops/x", "결론": "한 줄이다", "오빠가 결정할 것": "A 로 갈까요", "되돌림": "revert"}
head_ok("제안서 r0", pp.text_of(prop, "r0", seats=str(seats)))
head_ok("제안서 r1", pp.text_of(prop, "r1", seats=str(seats)))
magtxt = ms_.root_text("2026-10-08", ["가", "나", "다"], None, 2, "U1", None, None, str(seats))
check("⑤ 매거진: 결정 대기 N건 줄에 멘션 + 결정 자리", "<@U1> 결정 대기 2건 — 결정 자리: byz-planner-master-claude#12" in magtxt, magtxt)
check("⑤ 매거진: 결정 대기 0건이면 멘션·결정 자리 줄 0", "<@" not in ms_.root_text("2026-10-08", ["가", "나", "다"], None, 0, "U1", None, None, str(seats)))
ptxt = pp.text_of(prop, "r0", seats=str(seats))
check("① 제안서: 결정할 것 + 결정 자리 줄, 「오빠가 결정할 것」 라벨 0", "결정할 것: A 로 갈까요" in ptxt and "결정 자리: byz-planner-master-claude#12" in ptxt and "오빠가 결정할 것" not in ptxt, ptxt)
ptxt = pp.text_of({**prop, "결론": "이 스레드에 답해 주세요", "오빠가 결정할 것": "회신해 주세요"}, "r0", seats=str(seats))
check("② 제안서 값이 답장 요구 → 교정 표시", ptxt.count("(요약 문구 교정)") == 2 and "회신해" not in ptxt, ptxt)
clean("제안서", ptxt)
# 단위 스레드 글 3종 (start · progress · result) — 슬랙 호출은 가짜
posted = []
tp.post = lambda base, tok, ch, text, thread_ts=None: (posted.append(text) or "9.9")
tp.target = lambda a: ms_.Target("http://invalid.example", "tok", a.channel, "")
tp.find_reply_first_line = lambda *a, **k: None
cardf = tmp / "design" / "harness" / "indices" / "UNIT-1.md"; cardf.parent.mkdir(parents=True)
cardf.write_text("# 인덱스\n## 상태\n- 생성\n", encoding="utf-8")
verdict = tmp / "VERDICT.md"; verdict.write_text("# 판정\n## §1 닫힘 — 슬랙 공유판\n", encoding="utf-8")
ledger = tmp / "ledger.json"
common = ["--card", str(cardf), "--team", "harness", "--ledger", str(ledger), "--issue", "없음", "--seat", "없음", "--canon", "없음", "--next", "없음", "--resume-script", str(resume)]
tp.main(["--init", "--ledger", str(ledger)])
rcs = [tp.main(["start", *common, "--text", "착수해요"]), tp.main(["progress", *common, "--text", "진행해요"]),
       tp.main(["result", *common, "--verdict", f"{verdict}#§1", "--landed", "abc1234"])]
check("⑥ 단위 start/progress/result 실행(가짜 슬랙) rc=0", rcs == [0, 0, 0] and len(posted) == 3, (rcs, posted))
if len(posted) == 3:
    check("⑥ 단위 시작 [작업상황] · 진행 [작업상황] · 결과 [변경내용]", posted[0].startswith("[작업상황] ") and posted[1].startswith("[작업상황] ") and posted[2].startswith("[변경내용] [결과] "), [p.split("\n")[0] for p in posted])

# ── ⑦ 머리표 없는 옛 첫 줄과 새 첫 줄이 같은 글로 찾아짐 (가짜 history)
T = ms_.Target("http://invalid.example", "tok", "C", "U1")
hist = [{"ts": "10.1", "bot_id": "B1", "text": "*아침 매거진 2026-10-08*\n옛 글(머리표 없음)"}, {"ts": "20.1", "bot_id": "B1", "text": "[상태] *아침 매거진 2026-10-09*\n새 글"},
        {"ts": "30.1", "bot_id": "B1", "text": "*제안서 ops/x*\n옛"}, {"ts": "40.1", "bot_id": "B1", "text": "[작업상황] *제안서 ops/y*\n새"},
        {"ts": "50.1", "bot_id": "B1", "text": "*아침 매거진 2026-10-08 재첨부 r1*\n옛"}, {"ts": "60.1", "bot_id": "B1", "text": "[상태] *아침 매거진 2026-10-09 재첨부 r1*\n새"}]
ms_.paged = lambda *a, **k: hist
pp.paged = lambda *a, **k: hist
check("⑦ find_root: 옛(머리표 없음) 첫 줄로 찾기", ms_.find_root(T, "2026-10-08", 0) == "10.1")
check("⑦ find_root: 새(머리표 있음) 첫 줄로 찾기", ms_.find_root(T, "2026-10-09", 0) == "20.1")
check("⑦ 제안서 r0: 옛 글·새 글 모두 같은 글로 찾기", ms_.find_first_line(T, pp.first_line("ops/x", "r0"), 0) == "30.1" and ms_.find_first_line(T, pp.first_line("ops/y", "r0"), 0) == "40.1")
check("⑦ 재첨부 답글: 옛·새 모두 찾기", ms_.find_reply_first_line(T, "1.0", mre.first_line("2026-10-08", "r1")) == "50.1" and ms_.find_reply_first_line(T, "1.0", mre.first_line("2026-10-09", "r1")) == "60.1")
check("⑦ 제안서 rN 답글 찾기(find_reply): 머리표 무시", pp.find_reply(T, "1.0", pp.first_line("ops/x", "r0")) == "30.1")

# ── ⑧ inbound 전달
comm = tmp / "comm"; comm.mkdir()
mailbox = comm / "mailbox.jsonl"
sends, notices = [], []
def fake_send(mbox, to, body, spool):
    seq = 1000 + len(sends)
    sends.append((to, body))
    with open(mailbox, "a", encoding="utf-8") as f:
        f.write(json.dumps({"seq": seq, "from": ib.FROM, "to": to, "body": body}, ensure_ascii=False) + "\n")
    return seq
ib.send = fake_send
lib.post = lambda base, tok, ch, text, thread_ts=None: (notices.append(text) or "1.1")
def mk():
    x = bi.Inbound.__new__(bi.Inbound)
    x.a = argparse.Namespace(api_base="http://invalid.example", channel="C", mbox=str(comm / "mbox.sh"), seats_file=str(tmp / "seats-harness.json"))
    x.state_path = tmp / "st.json"; x.qpath = tmp / "nope-q.json"; x.spool = tmp / "spool"; x.comm = comm
    x.token = "tok"; x.sent = 0; x.planner_seats = str(seats); x.seen_updates = {}
    return x
def entry(recips, text="오빠 새 글 (Slack) — 원문:\nQ3 <@U1> &amp; 줄\n바꿈", **kw):
    return {"thread": "", "recips": list(recips), "done": {}, "attempt": {}, "q": None, "text": text, **kw}
def reset():
    sends.clear(); notices.clear(); mailbox.write_text("")
def run(x, e, ts="111.1"):
    x._save = lambda st: None
    x._deliver({}, ts, e)
CASES = {"명부 없음": lambda: (os.remove(seats) if seats.exists() else None, alive("byz-planner-master-claude#12")),
         "JSON 오류": lambda: (seats.write_text("{ nope"), alive("byz-planner-master-claude#12")),
         "_master 없음": lambda: (seats.write_text(json.dumps({"_hil_route": "x"})), alive("byz-planner-master-claude#12")),
         "tmux 실행 실패": lambda: (write_seats("byz-planner-master-claude#12"), os.environ.__setitem__("MIRROR_TMUX", str(tmp / "no-such-tmux"))),
         "세션 없음": lambda: (write_seats("byz-planner-master-claude#12"), os.environ.__setitem__("MIRROR_TMUX", str(stub)), alive())}
for why, setup in CASES.items():
    reset(); os.environ["MIRROR_TMUX"] = str(stub); setup()
    x, e = mk(), entry(["@planner"])
    run(x, e); run(x, e)
    check(f"⑧ planner 사유 「{why}」 → 전달 0 · unfinished · 알림 정확히 1회(두 패스)", not sends and not e.get("finished") and len(notices) == 1 and why in notices[0] and notices[0].startswith("[상태] "), (sends, notices))
# 같은 항목: 다음 패스에 현역 생김 → 그 이름으로 1회 전달
os.environ["MIRROR_TMUX"] = str(stub); write_seats("byz-planner-master-claude#12"); alive("byz-planner-master-claude#12")
run(x, e)
check("⑧ 다음 패스에 현역 생김 → 1회 전달 + finished", [t for t, _ in sends] == ["byz-planner-master-claude#12"] and e.get("finished") and e["done"]["@planner"] == "byz-planner-master-claude#12", (sends, e))
run(x, e)
check("⑧ 끝난 항목을 다시 돌려도 재발송 0", len(sends) == 1)
body = sends[0][1]
check("⑧ 원문 바이트 보존 + 토큰은 역할 기준(slack:{ts}:@planner)", body == f"[slack-oppa->byz-planner-master-claude#12] {e['text']}\n(slack:111.1:@planner)", body)
# 첫 시도 뒤 승계(이름 변경) → 중복 0
reset(); x, e = mk(), entry(["@planner"])
run(x, e)
e["done"].pop("@planner")  # 보냈는데 done 저장 전에 죽은 경우를 흉내(attempt 만 남음)
write_seats("byz-planner-master-claude#13"); alive("byz-planner-master-claude#13")
run(x, e)
check("⑧ 첫 시도 뒤 승계(#12→#13) → 중복 전달 0 (토큰 기준)", [t for t, _ in sends] == ["byz-planner-master-claude#12"] and e["done"].get("@planner"), sends)
# 빈 recips
reset(); x, e = mk(), entry([])
run(x, e)
check("⑧ 빈 수신자 → finished 0 · 알림 1", not e.get("finished") and len(notices) == 1 and "수신자 0" in notices[0], (e, notices))
# 질문 좌석이 곧 현역 planner → 같은 좌석에 두 번 보내지 않는다
reset(); write_seats("byz-planner-master-claude#12"); alive("byz-planner-master-claude#12")
x, e = mk(), entry(["byz-planner-master-claude#12", "@planner"])
run(x, e)
check("⑧ 질문 좌석 = 현역 planner → 1회만", [t for t, _ in sends] == ["byz-planner-master-claude#12"] and e.get("finished"), sends)

# ── ⑨ B-r3 fixture 4 — 옛 원장 이관
OLD = "byz-planner-master-claude#11"
def fixture(title, e, marker_rows=(), expect_sends=None, extra=None):
    reset(); write_seats("byz-planner-master-claude#12"); alive("byz-planner-master-claude#12")
    for to, tok in marker_rows:
        with open(mailbox, "a", encoding="utf-8") as f:
            f.write(json.dumps({"seq": 1, "from": ib.FROM, "to": to, "body": f"[slack-oppa->{to}] 원문\n({tok})"}, ensure_ascii=False) + "\n")
    x = mk()
    ib.migrate_planner(e)
    run(x, e)
    ib.migrate_planner(e)  # 두 번째 이관은 아무것도 바꾸지 않는다(멱등)
    got = [t for t, _ in sends]
    print(f"FIXTURE {title}: recips={e['recips']} done={e['done']} attempt={e['attempt']} sends={got} finished={e.get('finished')}")
    check(f"⑨ {title}", got == expect_sends and (extra(e) if extra else True), (got, e))
fixture("옛 이름 pending → 현역 1회", entry([OLD]), expect_sends=["byz-planner-master-claude#12"], extra=lambda e: e["recips"] == ["@planner"] and e["done"].get("@planner"))
fixture("옛 이름 첫 시도 뒤 crash(attempt 1 · marker 있음) → 재발송 0", entry([OLD], attempt={OLD: 1}), marker_rows=[(OLD, "slack:111.1:" + OLD)],
        expect_sends=[], extra=lambda e: e["done"].get("@planner") == OLD and e.get("finished"))
fixture("옛 이름 첫 시도 뒤 crash(attempt 1 · marker 없음) → 현역 1회", entry([OLD], attempt={OLD: 1}), expect_sends=["byz-planner-master-claude#12"],
        extra=lambda e: e["attempt"]["@planner"] == [OLD, "byz-planner-master-claude#12"])
fixture("옛 이름 이미 done → 재발송 0", entry([OLD], done={OLD: True}, attempt={OLD: 1}), expect_sends=[], extra=lambda e: e["recips"] == ["@planner"])
CFO = "byz-cfo-master-claude#53"
fixture("다른 팀 질문 좌석 이관 0", entry([CFO, OLD], done={CFO: True}), expect_sends=["byz-planner-master-claude#12"],
        extra=lambda e: e["recips"] == [CFO, "@planner"] and e["done"].get(CFO) is True)

# ── ⑧ 소스에 _hil_route 읽기 0
src = (Path(KIT) / "mirror_inbound.py").read_text(encoding="utf-8") + (Path(KIT) / "mirror_plan.py").read_text(encoding="utf-8") + (Path(KIT) / "byz_slack_mbox_inbound.py").read_text(encoding="utf-8")
check("⑤ inbound 소스에 _hil_route 읽기 0", "_hil_route" not in src.replace("`_hil_route`", "").replace("_hil_route 는", ""), "")
print("FAILS", fails)
sys.exit(1 if fails else 0)
PYEOF
)"
rc=$?
echo "$out" | grep -E '^(PASS|FAIL)' || true
echo "$out" | sed -n '/^HIL_CARD_BEGIN/,/^HIL_CARD_END/p'
echo "$out" | grep '^FIXTURE' || true
if [ "$rc" -ne 0 ]; then echo "$out" | grep -vE '^(PASS|FAIL|FIXTURE|HIL_CARD)' | tail -15; echo "FAILED rc=$rc"; exit 1; fi
echo "ALL PASS"
