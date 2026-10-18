#!/usr/bin/env bash
# test_inbox_watch.sh — ft-inbox-watch.sh(세션 안 쪽지 감시) 시험. 임시 FT_ROOT 큐 픽스처 · tmux·claude·실 planner pane 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
WATCH="$REPO/harness/bin/ft-inbox-watch.sh"
T="$(mktemp -d)"; trap 'kill "${WP:-0}" 2>/dev/null; rm -rf "$T"' EXIT
export FT_ROOT="$T/root" FT_INBOX_WATCH_POLL=0.1
mkdir -p "$FT_ROOT/.fable-team/state/inbox" "$FT_ROOT/.fable-team/comm/bodies"
Q="$FT_ROOT/.fable-team/state/inbox/planner-x.jsonl"
OUT="$T/out.txt"; ERR="$T/err.txt"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

row() {  # <seq> <cls> <from> [본문 — 비우면 body_path 없는 행]
  python3 - "$Q" "$FT_ROOT/.fable-team/comm/bodies" "$@" <<'PY'
import json, sys
q, bd, seq, cls, frm = sys.argv[1:6]
x = {"seq": int(seq), "cls": cls, "from": frm, "via": "rule"}
if len(sys.argv) > 6:
    p = f"{bd}/{seq}.txt"
    open(p, "w", encoding="utf-8").write(sys.argv[6] + "\n둘째 줄\n")
    x["body_path"] = p
open(q, "a", encoding="utf-8").write(json.dumps(x, ensure_ascii=False) + "\n")
PY
}
rewrite_all() {  # 분류기처럼 큐를 통째로 다시 쓴다(cls 갱신)
  python3 - "$Q" <<'PY'
import json, os, sys
q = sys.argv[1]
rows = [json.loads(l) for l in open(q, encoding="utf-8") if l.strip()]
for x in rows:
    x["cls"], x["via"] = "⑤", "haiku"
open(q + ".tmp", "w", encoding="utf-8").writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in rows)
os.replace(q + ".tmp", q)
PY
}
lines() { grep -c '^\[쪽지\]' "$OUT" 2>/dev/null || true; }
waitfor() {  # <줄 수>
  for _ in $(seq 1 50); do [ "$(lines)" -ge "$1" ] && return 0; sleep 0.1; done; return 1
}
start() { : > "$OUT"; : > "$ERR"; bash "$WATCH" planner-x#3 >"$OUT" 2>"$ERR" & WP=$!; sleep 0.6; }
stop() { kill -TERM "$WP" 2>/dev/null; wait "$WP" 2>/dev/null; STOP_RC=$?; }  # 서브셸로 부르면 wait 가 127 — 변수로 받는다

# ② 시작 전 행 → 출력 0
row 1 ② a#1 "[a#1->planner-x#3] 시작 전 쪽지"
start
sleep 0.5; eq "② 시작 전 행은 출력 0" "$(lines)" "0"
# ① 시작 뒤 새 행 1 → 1줄(형식 일치)
row 2 ② byz-x#4 "[HIL] 행#3 질문입니다 — 이 본문은 사십 자를 넘기게 길게 적어서 잘리는지 본다"
waitfor 1 && ok "① 새 행 1 → 출력 1줄" || bad "① 새 행 출력 없음"
L1="$(grep '^\[쪽지\]' "$OUT" | head -1)"
printf '%s' "$L1" | grep -Eq '^\[쪽지\] #2 ② byz-x#4 .+' && ok "① 형식 [쪽지] #<seq> <분류> <from> <첫 줄>" || bad "① 형식 불일치: $L1"
BODY40="${L1#\[쪽지\] #2 ② byz-x#4 }"
[ "${#BODY40}" -le 40 ] && ok "① 본문 40자 이내(${#BODY40}자) · 첫 줄만" || bad "① 본문 40자 초과 ${#BODY40}"
printf '%s' "$L1" | grep -q '둘째 줄' && bad "① 둘째 줄 노출" || ok "① 둘째 줄 미노출"
# ③ 큐 통째 다시 쓰기(cls 갱신) → 추가 출력 0
rewrite_all; sleep 0.6
eq "③ 통째 다시 쓰기 뒤 줄 수 불변" "$(lines)" "1"
# ④ 새 행 2개 연속 → 2줄 추가
row 3 ③ b#1 "[b#1->planner-x#3] 판정 요청 하나"; row 4 ⑥ c#1 "[c#1->planner-x#3] 참고 둘"
waitfor 3 && ok "④ 새 행 2개 연속 → 2줄 추가" || bad "④ 줄 수 $(lines) (기대 3)"
eq "④ 순서(#3 다음 #4)" "$(grep '^\[쪽지\]' "$OUT" | sed -n '2,3p' | cut -d' ' -f2 | tr '\n' ' ')" "#3 #4 "
# ⑥ body_path 없음 → (본문 없음)
row 5 미상 d#1
waitfor 4 && ok "⑥ body_path 없는 행도 출력" || bad "⑥ 출력 없음"
grep '^\[쪽지\] #5 ' "$OUT" | grep -q '(본문 없음)$' && ok "⑥ (본문 없음)" || bad "⑥ (본문 없음) 아님"
stop; eq "SIGTERM 종료 코드 0" "$STOP_RC" "0"

# ⑤ 큐 파일 없음 → 경고·계속, 생기면 그 뒤 새 행 출력
rm -f "$Q"; start
sleep 0.5; kill -0 "$WP" 2>/dev/null && ok "⑤ 큐 없음에도 감시 계속" || bad "⑤ 감시가 죽음"
grep -q 'WARN ft-inbox-watch' "$ERR" && ok "⑤ stderr 경고" || bad "⑤ 경고 없음"
row 6 ① e#1 "[e#1->planner-x#3] 큐 생긴 뒤 쪽지"
waitfor 1 && ok "⑤ 큐 생긴 뒤 새 행 출력" || bad "⑤ 출력 없음"
printf 'not-json\n' >> "$Q"; row 7 ④ f#1 "[f#1->planner-x#3] 깨진 줄 뒤"
waitfor 2 && ok "⑤ 깨진 줄 무시하고 계속" || bad "⑤ 깨진 줄 뒤 출력 없음"
stop

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
