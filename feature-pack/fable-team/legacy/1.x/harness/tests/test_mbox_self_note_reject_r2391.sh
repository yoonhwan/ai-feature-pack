#!/usr/bin/env bash
# test_mbox_self_note_reject_r2391.sh — r2391 K4: mbox send 는 받는이 = 보낸이(글자 그대로)인데 머리가 «[깨움]» 이
#  아닌 쪽지를 REJECT 한다. 그래서 recv 가 못 읽는 자기 앞 쪽지가 큐에 조용히 쌓이지 않는다.
#  사례 ⑧⑨⑩ + 변이 M4~M6(사본 mbox_ops.py · 변이마다 원본으로 같은 사례 1회 더).
#  실 우편함·실 tmux·실 좌석 0 · sleep 0 · 시험 1개 70초 안.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
ME="zz#1"; PEER="zz#2"

new_env() {  # 격리 루트 · 빈 큐 · 명부(zz#1·zz#2) · 변이(MUT 이 있으면 사본을 고친다)
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; S="$ENVROOT/seats"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$S"; cp "$SRC"/mbox*.py "$C/"; : > "$Q"
  printf '{"_master": "%s"}\n' "$ME" > "$S/seats.json"
  printf '{"%s": {"role": "master"}, "%s": {"role": "desk"}}\n' "$ME" "$PEER" > "$S/seats-zz.json"
  if [ -n "${MUT:-}" ]; then "$MUT" || { bad "변이 적용 실패 $MUT"; return 1; }; fi
}
py() { FT_SEATS_JSON="$S/seats.json" FT_MBOX_DIR="$C" python3 "$C/mbox.py" "$@"; }
send() { py send "$1" "$2" "$3" --force >"$ENVROOT/out" 2>"$ENVROOT/err"; RC=$?; OUT="$(cat "$ENVROOT/out")"; ERR="$(cat "$ENVROOT/err")"; }
rows() { grep -c . "$Q" 2>/dev/null | tr -d ' '; }
desc() { echo "rc=$RC out=[$OUT] err=[$ERR] rows=$(rows)"; }

# 사례 ⑧ — 받는이 = 보낸이 ∧ 머리 «[깨움]» 아님 = REJECT rc 2 · 1줄 · 큐 쓰기 0
case_self() {
  new_env || return 1; send "$ME" "$ME" "[Slack 직접 확인] desk 임시 감시"
  [ "$RC" = 2 ] && [ -z "$OUT" ] && [ "$(grep -c '^REJECT 자기 앞 쪽지' <<<"$ERR")" = 1 ] \
    && [ "$(grep -c . <<<"$ERR")" = 1 ] && [ "$(grep -c '^REJECT 자기 앞 쪽지' <<<"$ERR")" = 1 ] \
    && grep -q '큐 쓰기 0' <<<"$ERR" && [ "$(rows)" = 0 ]
}

# 사례 ⑨ — 받는이 = 보낸이 ∧ 머리 «[깨움]» = 통과(지금 꼴 그대로) · 앞 공백도 같은 규칙
case_wake() {
  new_env || return 1; send "$ME" "$ME" "[깨움] 내 앞 일감 확인"
  local q1; q1="$(rows)"
  [ "$RC" = 0 ] && grep -q "^QUEUED seq=[0-9]* to=$ME" <<<"$OUT" && [ "$q1" = 1 ] || { return 1; }
  send "$ME" "$ME" "   [깨움] 앞 공백 있는 깨움"
  [ "$RC" = 0 ] && [ "$(rows)" = 2 ]
}

# 사례 ⑩ — 같은 역할 다른 번호(zz#1 → zz#2) = 글자 그대로 다르므로 통과 · 그 쪽지는 실제로 읽힌다
case_peer() {
  new_env || return 1; send "$PEER" "$ME" "[보고] 같은 역할 다른 번호"
  [ "$RC" = 0 ] && grep -q "^QUEUED seq=[0-9]* to=$PEER" <<<"$OUT" && [ "$(rows)" = 1 ] || { return 1; }
  py recv "$PEER" >"$ENVROOT/recv" 2>&1
  grep -q "같은 역할 다른 번호" "$ENVROOT/recv"
}

case_self c8 && ok "⑧ 자기 앞 쪽지(«[깨움]» 아님) → rc 2 REJECT 1줄 · 큐 0" || bad "⑧ 자기 앞 쪽지" "$(desc)"
case_wake c9 && ok "⑨ 자기 앞 쪽지 «[깨움]»(앞 공백 포함) → QUEUED rc 0 · 큐 2" || bad "⑨ [깨움] 통과" "$(desc)"
case_peer c10 && ok "⑩ 같은 역할 다른 번호 → QUEUED rc 0 · recv 가 읽는다" || bad "⑩ 다른 번호 통과" "$(desc)"

# 변이 M4~M6 — 사본 mbox_ops.py 만 고친다 · 변이 = FAIL · 원본 = PASS
mut() {  # mut <이름> <사례 함수> <변이 함수> <설명>
  local name="$1" fn="$2" fix="$3" why="$4"
  MUT="$fix"; if "$fn" "$name-m"; then bad "$name 변이가 안 잡힘($why)" "$(desc)"; else ok "$name 변이 → FAIL($why)"; fi
  MUT=""; "$fn" "$name-o" && ok "$name 원본 같은 사례 PASS" || bad "$name 원본 같은 사례" "$(desc)"
}
mut_m4() { sed -i '' 's/^    if to == frm and not self_wake/    if False and not self_wake/' "$C/mbox_ops.py" && grep -q '^    if False and not self_wake' "$C/mbox_ops.py"; }
mut_m5() { sed -i '' 's/^    if to == frm and not self_wake({"to": to, "body": body}, frm):$/    if to == frm:/' "$C/mbox_ops.py" && grep -q '^    if to == frm:$' "$C/mbox_ops.py"; }
mut_m6() { sed -i '' 's/^    if to == frm and not self_wake(/    if role_key(to) == role_key(frm) and not self_wake(/' "$C/mbox_ops.py" && grep -q '^    if role_key(to) == role_key(frm)' "$C/mbox_ops.py"; }

mut M4 case_self mut_m4 "검사 지움"
mut M5 case_wake mut_m5 "«[깨움]» 예외 지움"
mut M6 case_peer mut_m6 "역할 키까지 막음"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
