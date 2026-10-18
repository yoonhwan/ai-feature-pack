#!/usr/bin/env bash
# test_report_hooks.sh — v423b: report-coverage(Stop) + drain-before-interview(PreToolUse AskUserQuestion)
# 임시 FT_ROOT(가짜 인박스 큐) + 스텁 ft-inbox.sh·mbox.sh + 가짜 훅 JSON/transcript 픽스처만 — 실제 claude·tmux·슬랙·라이브 .fable-team 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$HERE/../../scripts/harness-install/fable-team/templates/hooks"
RC="$H/report-coverage.sh"; DR="$H/drain-before-interview.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { grep -qF -- "$2" <<<"$1"; }
for f in "$RC" "$DR"; do bash -n "$f" || bad "bash -n $f"; done; ok "bash -n 2종"
export FT_SEAT="byz-t-planner#0" FT_INBOX_SH="${REAL_FT_INBOX_SH:-$T/bin/ft-inbox.sh}" FT_MBOX_SH="$T/bin/mbox.sh"
mkdir -p "$T/bin"
printf '#!/bin/sh\nexec python3 "%s" "$@"\n' "$HERE/fixtures/stub-ft-inbox.py" > "$T/bin/ft-inbox.sh"
printf '#!/bin/sh\n# peek 호출마다 pending 이 늘어난다(같은 턴 계속 쌓이는 상황)\nn=$(cat "$0.n" 2>/dev/null || echo 0); n=$((n+3)); echo $n > "$0.n"; echo "pending=$n scanned=1"\n' > "$T/bin/mbox.sh"
chmod +x "$T/bin/"*.sh

newroot() {  # newroot <이름> <첫seq> <개수> <cls> [묶음id] — 큐 N줄(미표시·미보고)
  local r="$T/$1"; mkdir -p "$r/.fable-team/state/inbox"
  python3 - "$r" "$2" "$3" "$4" "${5:-}" <<'EOF'
import json, sys
r, s, n, cls, g = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
rows = [{"seq": s + i, "ts": "t", "from": "byz-t-master#1", "cls": cls, "prio": 1, "group": g or f"g-{s + i}", "body_path": "-", "mark": None, "reported": False, "via": "rule"} for i in range(n)]
open(f"{r}/.fable-team/state/inbox/byz-t-planner.jsonl", "w").writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in rows)
EOF
  echo "$r"
}
tscript() {  # tscript <파일> <uuid> <최종답변> [피드백레코드 y]
  python3 - "$@" <<'EOF'
import json, sys
f, u, txt = sys.argv[1:4]
recs = [{"type": "user", "uuid": u, "message": {"content": "오빠 요청"}},
        {"type": "assistant", "uuid": u + "-a", "message": {"content": [{"type": "text", "text": txt}]}}]
if len(sys.argv) > 4:
    recs.append({"type": "user", "uuid": u + "-fb", "message": {"content": "Stop hook feedback: 보고하라"}})
open(f, "w").writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in recs)
EOF
}
stop()  { FT_ROOT="$1" bash "$RC" <<<"{\"session_id\":\"$2\",\"transcript_path\":\"$3\",\"stop_hook_active\":${4:-false}}"; }
ask()   { FT_ROOT="$1" bash "$DR" <<<"{\"session_id\":\"$2\",\"transcript_path\":\"$3\",\"tool_name\":\"AskUserQuestion\"}"; }
count() { python3 -c "import json,sys;print(sum(1 for l in open('$1/.fable-team/state/inbox/byz-t-planner.jsonl') if json.loads(l)['$2']))"; }
errs()  { { wc -l < "$1/.fable-team/state/hook-errors.log" 2>/dev/null || echo 0; } | tr -d ' '; }

# ── 1. 미보고 30건: 같은 턴 키 block 1회 → 2회째 통과 · 줄 상태 유지
R="$(newroot r1 70001 30 ①)"; tscript "$T/t1.jsonl" U1 "정리했습니다"
o1="$(stop "$R" S1 "$T/t1.jsonl")"; o2="$(stop "$R" S1 "$T/t1.jsonl")"
has "$o1" '"decision": "block"' && has "$o1" "30건" && [ -z "$o2" ] && [ "$(count "$R" reported)" = 0 ] && [ "$(count "$R" mark)" = 0 ] \
  && { ok "미보고 30건 block 1회 → 2회째 통과 · 줄 상태 유지"; echo "미보고 30건 block 1회 → rc=0 decision=block 30건 · 같은 턴 키 2회째 출력 없음(통과)"; echo "2회째 통과 · 줄 상태 유지 → reported=true $(count "$R" reported)줄 · mark 있음 $(count "$R" mark)줄 · 전체 30줄"; } || bad "30건 block1회/2회째 통과: o1=$o1 o2=$o2"
# 훅 피드백 user 레코드가 끼어도 같은 턴 키(2회째 통과)
tscript "$T/t1b.jsonl" U1 "정리했습니다" y; [ -z "$(stop "$R" S1 "$T/t1b.jsonl")" ] && ok "훅 피드백 user 레코드 = 새 턴 아님" || bad "피드백 레코드가 턴 키를 바꿈"
# stop_hook_active=true 통과
tscript "$T/t1c.jsonl" U9 "정리했습니다"; [ -z "$(stop "$R" S1 "$T/t1c.jsonl" true)" ] && ok "stop_hook_active=true 통과" || bad "stop_hook_active"

# ── 2. 인용 블록 안 #seq·판정 숫자는 report 안 됨 (새 턴 키)
tscript "$T/t2.jsonl" U2 $'> #70001 원문 인용\n판정 514 와 PR #1015 는 숫자일 뿐'
o="$(stop "$R" S1 "$T/t2.jsonl")"; has "$o" '"decision": "block"' && [ "$(count "$R" reported)" = 0 ] && ok "인용 블록·판정 숫자 = report 0" || bad "인용 오보고: $(count "$R" reported)"

# ── 3. 30건 중 일부만 mark + #seq → 나머지만 다음 턴 대상
FT_ROOT="$R" "$FT_INBOX_SH" mark 70001 처리 a; FT_ROOT="$R" "$FT_INBOX_SH" mark 70002 처리 b
tscript "$T/t3.jsonl" U3 "쪽지 #70001·#70002 처리했습니다"
o="$(stop "$R" S1 "$T/t3.jsonl")"; has "$o" "28건" && ! has "$o" "#70001" && ! has "$o" "#70002" && has "$o" "#70003" && [ "$(count "$R" reported)" = 2 ] \
  && ok "일부 mark+#seq → 나머지 28건만 대상" || bad "일부 처리: $o"
# 인터뷰 대기 뒤 새 턴(새 uuid)에 의무 잔존 → 다시 block
tscript "$T/t3b.jsonl" U4 "인터뷰 답을 받았습니다"; has "$(stop "$R" S1 "$T/t3b.jsonl")" "28건" && ok "새 턴(새 uuid) 에 의무 잔존 → block" || bad "새 턴 잔존"

# ── 4. 묶음 G={S1,S2}: S1 만 mark+report → G 대상 유지
R4="$(newroot r4 70101 2 ① g-G)"; FT_ROOT="$R4" "$FT_INBOX_SH" mark 70101 처리 a; FT_ROOT="$R4" "$FT_INBOX_SH" mark 70102 처리 b
tscript "$T/t4.jsonl" U5 "쪽지 #70101 보고"; o="$(stop "$R4" S4 "$T/t4.jsonl")"
has "$o" "1건" && has "$o" "#70102" && ! has "$o" "#70101" && ok "묶음 G: S1 만 → G 대상 유지(#70102)" || bad "묶음: $o"

# ── 5. drain-before-interview: 같은 턴 pending 이 계속 늘어도 deny 1회
R5="$(newroot r5 70201 3 ②)"; tscript "$T/t5.jsonl" U6 "인터뷰 직전"
d1="$(ask "$R5" S5 "$T/t5.jsonl")"; d2="$(ask "$R5" S5 "$T/t5.jsonl")"
has "$d1" '"permissionDecision": "deny"' && has "$d1" "pending=3" && has "$d1" "#70201" && [ -z "$d2" ] && ok "같은 턴 pending 증가에도 deny 1회" || bad "drain deny: d1=$d1 d2=$d2"
tscript "$T/t5b.jsonl" U7 "새 턴"; has "$(ask "$R5" S5 "$T/t5b.jsonl")" "deny" && ok "새 턴 키 → deny 다시 1회" || bad "drain 새 턴"
R5b="$(newroot r5b 70301 1 ③)"; FT_ROOT="$R5b" "$FT_INBOX_SH" mark 70301 처리 a; FT_ROOT="$R5b" "$FT_INBOX_SH" report 70301; rm -f "$T/bin/mbox.sh.n"
printf '#!/bin/sh\necho "pending=0 scanned=1"\n' > "$T/bin/mbox0.sh"; chmod +x "$T/bin/mbox0.sh"
[ -z "$(FT_MBOX_SH="$T/bin/mbox0.sh" ask "$R5b" S5b "$T/t5.jsonl")" ] && ok "pending 0 · 미닫힘 0 → 통과(인터뷰 허용)" || bad "함이 비었는데 deny"

# ── 6. 조회·기록 실패 = 통과 + hook-errors.log 1줄 (줄 상태 그대로)
R6="$(newroot r6 70401 3 ①)"; tscript "$T/t6.jsonl" U8 "x"
o="$(STUB_FAIL=1 stop "$R6" S6 "$T/t6.jsonl")"; [ -z "$o" ] && [ "$(errs "$R6")" = 1 ] && ok "조회 실패 = 통과 + 로그 1줄" || bad "조회 실패: o=$o errs=$(errs "$R6")"
mkdir -p "$R6/.fable-team/state/inbox/stop-S6b.json"
o="$(stop "$R6" S6b "$T/t6.jsonl")"; [ -z "$o" ] && [ "$(errs "$R6")" = 2 ] && [ "$(count "$R6" reported)" = 0 ] && ok "기록 실패 = 통과 + 로그 1줄 · 줄 상태 유지" || bad "기록 실패: o=$o errs=$(errs "$R6")"
o="$(STUB_FAIL=1 ask "$R6" S6c "$T/t6.jsonl")"; [ -z "$o" ] && [ "$(errs "$R6")" = 3 ] && ok "drain 조회 실패 = 통과 + 로그 1줄" || bad "drain 조회 실패: $o"

# ── 7. 팀 밖·좌석 아님 = 무출력 통과
mkdir -p "$T/r7/.fable-team/state/inbox"; [ -z "$(stop "$T/r7" S7 "$T/t1.jsonl")" ] && [ -z "$(ask "$T/r7" S7 "$T/t1.jsonl")" ] && ok "인박스 큐 없음 = 무출력 통과" || bad "큐 없음"
[ -z "$(env -u FT_SEAT -u TMUX_PANE FT_ROOT="$R" bash "$RC" <<<'{"session_id":"S8"}')" ] && ok "좌석명 없음 = 무출력 통과" || bad "좌석명 없음"

# ── 8. r1 반송: 쪽지 seq 는 「쪽지 #<seq>」 접두만(PR·Issue·맨 #숫자 = 0) · 로그는 state/hook-errors.log 한 곳
R8="$(newroot r8 70001 2 ①)"; rep() { count "$R8" reported; }
tscript "$T/t8a.jsonl" U20 "PR #70001 병합 · Issue #70001 · 이슈 #70001 · 그리고 #70001"; stop "$R8" S8 "$T/t8a.jsonl" >/dev/null
[ "$(rep)" = 0 ] && ok "PR/Issue/맨 #70001 = report 0" || bad "접두 없는 #seq 가 보고됨: $(rep)"
tscript "$T/t8b.jsonl" U21 "쪽지 #70001 처리"; stop "$R8" S8 "$T/t8b.jsonl" >/dev/null
[ "$(rep)" = 1 ] && ok "「쪽지 #70001」 → 70001 보고" || bad "쪽지 #70001: $(rep)"
tscript "$T/t8c.jsonl" U22 "쪽지 #70001·#70002 처리"; stop "$R8" S8 "$T/t8c.jsonl" >/dev/null
[ "$(rep)" = 2 ] && ok "「쪽지 #70001·#70002」 → 둘 다 보고" || bad "쪽지 목록: $(rep)"
R8g="$(newroot r8g 70101 2 ① g-G)"; FT_ROOT="$R8g" "$FT_INBOX_SH" mark 70101 처리 a; FT_ROOT="$R8g" "$FT_INBOX_SH" mark 70102 처리 b
tscript "$T/t8g.jsonl" U23 "쪽지 #70101 보고"; o="$(stop "$R8g" S8g "$T/t8g.jsonl")"
[ "$(count "$R8g" reported)" = 1 ] && has "$o" "#70102" && ! has "$o" "#70101" && ok "묶음 G: 쪽지 #70101 만 → 70101 만 reported · 70102 block 대상" || bad "묶음 접두: $o"
R8e="$(newroot r8e 70201 2 ①)"; FT_ROOT="$R8e" "$FT_INBOX_SH" mark 70201 처리 a; FT_ROOT="$R8e" "$FT_INBOX_SH" mark 70202 처리 b; tscript "$T/t8e.jsonl" U24 "쪽지 #70202 (transcript 쪽)"
o="$(FT_ROOT="$R8e" bash "$RC" <<<"{\"session_id\":\"S8e\",\"transcript_path\":\"$T/t8e.jsonl\",\"last_assistant_message\":\"쪽지 #70201\"}")"
[ "$(count "$R8e" reported)" = 1 ] && has "$o" "#70202" && ! has "$o" "#70201" && ok "last_assistant_message 가 transcript 와 다르면 입력 쪽만(70201)" || bad "입력 우선: $o"
[ -f "$R6/.fable-team/state/hook-errors.log" ] && [ ! -e "$R6/.fable-team/state/inbox/hook-errors.log" ] && has "$(cat "$R6/.fable-team/state/hook-errors.log")" "report-coverage $FT_SEAT:" && ok "오류 줄 = state/hook-errors.log · inbox/ 쪽 생성 0" || bad "로그 위치"
python3 - "$RC" "$T/mut.sh" <<'EOF2'
import sys; s = open(sys.argv[1], encoding="utf-8").read(); assert "쪽지 ?(#" in s; open(sys.argv[2], "w", encoding="utf-8").write(s.replace("쪽지 ?(#", "(#"))
EOF2
R8m="$(newroot r8m 70001 2 ①)"; FT_ROOT="$R8m" bash "$T/mut.sh" <<<"{\"session_id\":\"S8m\",\"transcript_path\":\"$T/t8a.jsonl\"}" >/dev/null
[ "$(count "$R8m" reported)" -gt 0 ] && ok "변이 대조: 접두 조건을 빼면 「PR #70001」 이 보고됨(시험 ①이 잡는다)" || bad "변이가 안 잡힘"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
