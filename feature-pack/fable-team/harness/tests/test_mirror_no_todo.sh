#!/usr/bin/env bash
# test_mirror_no_todo.sh — 슬랙 미러 요약기가 «할 일»을 지어내지 못한다 + planner 처리 1줄 (판정 423 ②)
#  ① DEFAULT_CMD 모델 = claude-haiku-5-5 (구 4-5 0) · 프롬프트에 todo «생성» 지시·HIL 강제 todo 줄 0
#  ② 요약 스텁이 todo 를 지어내도 원문에 그 문장이 없으면 null · 원문에 있는 문장은 그대로 남는다
#  ③ planner 회신 행(받은 쪽지 #seq 인용) → 그 쪽지의 스레드에 요약 한 문장 「planner 처리」 1줄 · 새 글(루트) 0 · 음성 대조 다수
#  (요약기 시간 초과·HTTP 전송 시험은 test_mirror_summary_http.sh)
# 실제 슬랙·claude 호출 0 — 스텁 명령 · 스텁 deliver · 임시 스레드 맵.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${SLACK_MIRROR_KIT:-$HERE/../../harness/kit/slack-mirror}"
[ -d "$KIT" ] || { echo "FAIL kit dir missing: $KIT"; exit 1; }
out="$(python3 -I - "$KIT" <<'PYEOF' 2>&1
import contextlib, io, json, re, stat, sys, tempfile
from pathlib import Path

KIT = sys.argv[1]
sys.path.insert(0, KIT)
import mirror_board as mb
import mirror_summary as summ

fails = 0
def check(name, cond, detail=""):
    global fails
    if cond:
        print(f"PASS {name}")
    else:
        fails += 1
        print(f"FAIL {name} {detail}")

tmp = Path(tempfile.mkdtemp())

# ① 모델 · 프롬프트
check("DEFAULT_CMD 모델 claude-haiku-5-5", "--model claude-haiku-5-5 " in summ.DEFAULT_CMD, summ.DEFAULT_CMD)
check("구 모델 haiku-4-5 0", "haiku-4-5" not in summ.DEFAULT_CMD)
check("프롬프트: todo «글자 그대로 복사»", "글자 그대로 복사" in summ.PROMPT)
check("프롬프트: HIL 강제 todo 줄 삭제", "라벨이 HIL 이면" not in summ.PROMPT)

# ② 요약 스텁 — todo 를 지어낸다
def stub(name, what, todo):
    p = tmp / name
    p.write_text("#!/bin/sh\ncat >/dev/null\nprintf '%s' '" + json.dumps({"what": what, "todo": todo}, ensure_ascii=False) + "'\n")
    p.chmod(p.stat().st_mode | stat.S_IXUSR)
    return str(p)

INVENT = stub("invent.sh", "빌드가 끝났어요", "배포 일정을 정해 주세요")
r = summ.summarize(INVENT, "보고", "빌드 완료. 시험 통과.")
check("지어낸 todo + 원문에 할 일 문장 없음 → null", r["todo"] is None, str(r))
check("what 은 그대로", r["what"] == "빌드가 끝났어요", str(r))
r = summ.summarize(INVENT, "HIL", "행 3 질문. 선택지 A 또는 B.")
check("HIL 도 지어낸 todo 는 null (HIL 문구는 게시 쪽 「정할 것: 전문 참고」)", r["todo"] is None, str(r))

COPY = stub("copy.sh", "배포가 남았어요", "배포 일정을 정해 주세요")
r = summ.summarize(COPY, "HIL", "빌드 완료.   배포 일정을  정해 주세요. 내일까지.")
check("⑧ 라벨 HIL + 원문 한 문장 전체 일치 → 남는다(공백 정규화)", r["todo"] == "배포 일정을 정해 주세요", str(r))
r = summ.parse_summary('{"what": "가", "todo": "지어낸 일"}')  # source=None = 옛 호출
check("source 없는 parse_summary 는 이전 동작(호환)", r["todo"] == "지어낸 일", str(r))
r = summ.summarize(stub("none.sh", "끝났어요", None), "보고", "끝.")
check("모델이 null → null", r["todo"] is None, str(r))

# 반송 r1 Q3 — 라벨·문장 전체 일치·절단 금지
STATE = "배포는 이미 완료됐습니다"
r = summ.summarize(stub("state.sh", "끝났어요", STATE), "보고", f"{STATE}. 나머지 설명.")
check("⑦ 라벨 보고 + 원문 상태 문장을 그대로 todo 로 → null", r["todo"] is None, str(r))
r = summ.summarize(stub("state2.sh", "끝났어요", STATE), "BLOCK", f"{STATE}. 막힘 없음.")
check("⑦ 라벨 BLOCK 도 null", r["todo"] is None, str(r))
HEAD110 = ("가" * 55 + "나" * 55)  # 110자
src = HEAD110 + " 끝."
r = summ.summarize(stub("prefix.sh", "정해요", HEAD110 + " 새 작업을 시작하세요"), "HIL", src)
check("⑨ HIL + 원문 110자 접두 뒤에 모델이 새 작업을 붙임 → null(절단 뒤 부분문자열 통과 0)", r["todo"] is None, str(r))
r = summ.summarize(stub("frag.sh", "정해요", "일정을 정해"), "HIL", "빌드 완료. 배포 일정을 정해 주세요. 끝.")
check("⑩ HIL + 원문 문장의 «부분» 조각 → null", r["todo"] is None, str(r))
LONG = "가" * 111
r = summ.summarize(stub("long.sh", "정해요", LONG), "HIL", f"시작. {LONG}. 끝.")
check("⑪ todo 원래 길이 >110 → null(절단 0)", r["todo"] is None, str(r))

# 변이 대조 — 조건을 빼면 위 시험이 «잡는다»(변이 사본은 메모리에서만)
def mutant_parse(old, new):
    src = (Path(KIT) / "mirror_summary.py").read_text(encoding="utf-8")
    assert old in src, old
    ns = {"__name__": "mutant_summary"}
    exec(compile(src.replace(old, new, 1), "mutant", "exec"), ns)
    return ns["parse_summary"]
mp = mutant_parse('label == "HIL" and ', "")
check("변이: 라벨 조건을 빼면 ⑦ 이 FAIL(상태 문장이 todo 로 남음)", mp(json.dumps({"what": "가", "todo": STATE}), f"{STATE}. 나머지.", "보고")["todo"] == STATE)

# ③ planner 처리 1줄
PL = re.compile(r"^byz-planner-master-claude#\d+$")
threads = tmp / "threads.json"
threads.write_text(json.dumps({"threads": {"#77": "111.1", "byz-harness-nano-x": "222.2"}}), encoding="utf-8")
rows = [
    {"seq": 5000, "ts": "2026-10-09T01:00:00", "from": "n#0", "to": "byz-planner-master-claude#12", "body": "[n#0->byz-planner-master-claude#12] Issue #77 진행 보고"},
    {"seq": 5001, "ts": "2026-10-09T01:01:00", "from": "n#0", "to": "other-seat#1", "body": "[n#0->other-seat#1] 남의 쪽지"},
    {"seq": 5002, "ts": "2026-10-09T01:02:00", "from": "x#0", "to": "byz-planner-master-claude#12", "body": "[x#0->byz-planner-master-claude#12] 스레드 없는 키 보고"},
]
got = []
deliver = lambda st, item: got.append(item)
calls = []  # 가짜 요약기 호출 기록 (seq, label, text)
def summ_ok(what="판정이 반영됐어요"):
    def f(seq, label, text):
        calls.append((seq, label, text))
        return {"what": what, "todo": None}
    return f
def reply(seq, body, frm="byz-planner-master-claude#12", ts="2026-10-09T01:30:00", summarize=None):
    got.clear()
    r = {"seq": seq, "ts": ts, "from": frm, "to": "n#0", "body": body}
    mb.post_handled(deliver, {}, r, rows + [r], PL, threads, summarize or summ_ok())
    return list(got)
g = reply(5100, "[byz-planner-master-claude#12->n#0] #5000 판정 반영 완료. 다음은 시험.")
check("회신 → 항목 1개", len(g) == 1, str(g))
if g:
    t = g[0]["text"]
    check("항목 key = 인용한 쪽지의 스레드 키(#77)", g[0]["key"] == "#77", str(g[0]))
    check("본문: 「planner 처리: 요약 한 문장 (시각)」", "planner 처리: 판정이 반영됐어요 (01:30)" in t and "판정 반영 완료." not in t, t)
    check("머리표 [작업상황]", t.startswith("[작업상황] "), t)
    check("resume 마커 id 가 본문에 실재", g[0]["id"] in t and g[0]["id"] == "planner 처리 #5100", t)
    check("새 글 0 — 스레드 맵 그대로", json.loads(threads.read_text())["threads"] == {"#77": "111.1", "byz-harness-nano-x": "222.2"})
calls.clear()  # ⓒ 아래 음성 대조(대상 아닌 행) 전부에서 요약기 호출 0
for sq, b, nm in ((5101, "처리했어요", "#seq 없음"), (5102, "master#19 에게 전달", "좌석명 #N 만(master#19)"), (5103, "가" * 85 + " #5000", "앞 80자 밖 인용")):
    check(f"음성: {nm} → 0", reply(sq, "[byz-planner-master-claude#12->n#0] " + b) == [])
check("음성: 스레드 없는 쪽지(5002) 인용 → 0 (루트를 새로 만들지 않는다)", reply(5104, "[byz-planner-master-claude#12->n#0] #5002 처리") == [])
check("음성: planner 앞이 아닌 쪽지(5001) 인용 → 0", reply(5105, "[byz-planner-master-claude#12->n#0] #5001 처리") == [])
check("음성: 없는 seq 인용 → 0", reply(5106, "[byz-planner-master-claude#12->n#0] #9999 처리") == [])
check("음성: planner 가 보낸 행이 아님 → 0", reply(5107, "[n#0->byz-planner-master-claude#12] #5000 처리", frm="n#0") == [])
check("ⓒ 음성 대조 전부(발신 아님 · 인용 없음 · 스레드 없음 · 없는 seq) → 요약기 호출 0", calls == [], str(calls))
g = reply(5108, "[byz-planner-master-claude#12->n#0] #5000 이 답장을 확인해 주세요. 끝.", summarize=summ_ok("이 답장을 확인해 주세요"))
check("답장 요구 문구는 게시 전에 중화(share_guard → 생략 문구)", len(g) == 1 and "확인해 주" not in g[0]["text"], str(g))
# ⓐ 대괄호 머리 답장 → 요약기를 거친 «사람 말 한 문장» · 머리 조각(「[판정」) 0
calls.clear()
g = reply(5110, "[byz-planner-master-claude#12->n#0] #5000 [판정 1237 · 오빠 승인 #79707] 훅 오탐 수정 반영", summarize=summ_ok("훅 오탐 수정이 반영됐어요"))
check("ⓐ 요약 성공 → 항목 1개 · 「planner 처리: 훅 오탐 수정이 반영됐어요」 ∧ 「[판정」 0", len(g) == 1 and "planner 처리: 훅 오탐 수정이 반영됐어요" in g[0]["text"] and "[판정" not in g[0]["text"], str(g))
check("ⓐ 요약기에는 답장 전문(머리 포함) · 라벨 보고", len(calls) == 1 and calls[0][1] == "보고" and "훅 오탐 수정 반영" in calls[0][2], str(calls))
# ⓑ 요약 실패(None) → 줄 0 + stderr 1줄(조용한 폴백 0)
calls.clear()
with contextlib.redirect_stderr(io.StringIO()) as err:
    g = reply(5111, "[byz-planner-master-claude#12->n#0] #5000 [판정 1237 · 오빠 승인 #79707] 훅 오탐 수정 반영", summarize=lambda s, l, t: calls.append(s))
check("ⓑ 요약 실패 → item 0", g == [], str(g))
check("ⓑ stderr 「planner 처리 줄 생략」 정확히 1줄", err.getvalue().count("planner 처리 줄 생략") == 1 and err.getvalue().count("\n") == 1, err.getvalue())

# 반송 r1 Q4 — 새 글 0 을 deliver 쪽이 보장(reply_only)
import types
import mirror_deliver as md
import mirror_lib as lib
posts = []
lib.post = lambda base, tok, ch, text, thread_ts=None: (posts.append((text, thread_ts)), "9.9")[1]
lib.thread_texts = lambda *a, **k: []
lib.channel_roots = lambda *a, **k: []
real_md = mb.md
mb.md = types.SimpleNamespace(load_threads=lambda p: {"#77": "111.1"})  # post_handled 의 사전 검사는 «있다» 로 본다
items = []
mb.post_handled(lambda st, item: items.append(item), {}, {"seq": 5200, "ts": "2026-10-09T02:00:00", "from": "byz-planner-master-claude#12", "to": "n#0",
                "body": "[byz-planner-master-claude#12->n#0] 쪽지 #5000 처리 끝."}, rows, PL, threads, summ_ok())
mb.md = real_md
check("⑫ 사전 검사 통과 → item 에 reply_only 플래그", len(items) == 1 and items[0].get("reply_only") is True, str(items))
empty_map = tmp / "empty-threads.json"
empty_map.write_text(json.dumps({"threads": {}}), encoding="utf-8")  # 실제 맵엔 key 가 없다(그 사이 eviction)
d = md.Deliverer("http://x", "tok", "C1", empty_map)
posts.clear(); d.send(items[0])
check("⑫ 검사 뒤 맵 소실 → post 0 · 루트 0", posts == [], str(posts))
posts.clear(); d.send(items[0], resume=True)
check("⑬ pending reply_only item 을 resume 으로 재개 · 맵 없음 → post 0 · 루트 0", posts == [], str(posts))
check("⑫⑬ 맵 파일도 그대로(루트 키 생성 0)", json.loads(empty_map.read_text())["threads"] == {})
d2 = md.Deliverer("http://x", "tok", "C1", threads)
posts.clear(); d2.send(items[0])
check("⑭ 맵 있음 → 답글 1 · 루트 0(thread_ts=111.1)", len(posts) == 1 and posts[0][1] == "111.1", str(posts))
ns_src = (Path(KIT) / "mirror_deliver.py").read_text(encoding="utf-8")
ANCHOR = 'if item.get("reply_only"):  # 새 글 0'  # 팀 모드 분기(앞쪽 같은 조건문)가 아니라 이 시험이 쓰는 비팀 분기를 지정
assert ANCHOR in ns_src
ns = {"__name__": "mutant_deliver"}
exec(compile(ns_src.replace(ANCHOR, "if False:  # 새 글 0", 1), "mutant", "exec"), ns)
posts.clear(); ns["Deliverer"]("http://x", "tok", "C1", empty_map).send(items[0])
check("변이: reply_only 분기를 빼면 ⑫ 가 FAIL(새 루트가 올라감)", len(posts) >= 1 and posts[0][1] is None, str(posts))

print(f"RESULT fail={fails}")
sys.exit(1 if fails else 0)
PYEOF
)"
rc=$?
echo "$out"

# ④ 미러 본체 배선(--once --dry-run) — planner 회신 행이 실제 패스에서 같은 스레드의 1줄로 나온다
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/root/.fable-team/comm" "$T/root/.fable-team/bin" "$T/state"
echo 'echo "claude --resume x"' > "$T/root/.fable-team/bin/ft-resume-cmd.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/ib.sh"; chmod +x "$T/ib.sh"
printf '#!/bin/sh\ncat >/dev/null\nprintf %%s "{\\"what\\":\\"요약\\",\\"todo\\":\\"지어낸 일\\"}"\n' > "$T/sum.sh"; chmod +x "$T/sum.sh"
cat > "$T/root/.fable-team/comm/mailbox.log.jsonl" <<'EOF'
{"seq": 5000, "ts": "2026-10-09T01:00:00", "from": "n#0", "to": "byz-planner-master-claude#12", "body": "[n#0->byz-planner-master-claude#12] Issue #77 진행 보고"}
{"seq": 5001, "ts": "2026-10-09T01:30:00", "from": "byz-planner-master-claude#12", "to": "n#0", "body": "[byz-planner-master-claude#12->n#0] #5000 판정 반영 완료. 다음은 시험."}
EOF
echo '{"last_seq": 4999, "pending": null}' > "$T/state/byz_mbox_slack_mirror.p.json"
echo '{"threads": {"#77": "111.1"}}' > "$T/state/byz_slack_threads.C1.json"
run="$(python3 "$KIT/byz_mbox_slack_mirror.py" --project p --mailbox "$T/root/.fable-team/comm/mailbox.log.jsonl" --seat '^byz-planner-master-claude#\d+$' \
  --channel C1 --state-dir "$T/state" --inbox-bin "$T/ib.sh" --summarizer-cmd "$T/sum.sh" --once --dry-run 2>&1)"
wiring=0
echo "$run" | grep -q '^\[작업상황\] planner 처리: 요약 (01:30)$' && echo "PASS 본체: 회신 행 → 「planner 처리」 1줄" || { echo "FAIL 본체: planner 처리 줄 없음: $run"; wiring=1; }
[ "$(echo "$run" | grep -c '^\[thread ')" = 2 ] && echo "PASS 본체: 게시 2건(원 카드 + 처리 1줄) · 같은 스레드 #77" || { echo "FAIL 본체: 게시 수: $run"; wiring=1; }
echo "$run" | grep -q '할 일 없음' && ! echo "$run" | grep -q '지어낸 일' && echo "PASS 본체: 스텁이 지어낸 todo 는 카드에 안 실림(「할 일 없음」)" || { echo "FAIL 본체: 지어낸 todo 가 카드에 실림: $run"; wiring=1; }

if [ "$rc" = 0 ] && [ "$wiring" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILED"; exit 1
