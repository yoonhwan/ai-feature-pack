#!/usr/bin/env bash
# test_mbox_handover_r1116.sh — 승계 마무리(r1116 ②③④ · 오빠 «메세지 유실없고 구세션 마지막 작업을 정상 이관»).
# 시나리오(발주 보탬 #191532): 증류 중 좌석에 [HIL] 1통 → 후계 [레디] 에 그 seq «받음» 이면 PASS.
# 정본 mbox* 를 임시 폴더에 복사해 격리 큐로만 돈다 — 실 좌석 kill 0(가짜 명부만) · tmux·ft-hil 스텁 · 자기 재호출 0 · 고정 sleep 0.
# 백그라운드 명령 칸 재료 = 이 시험이 띄운 «tail -f /dev/null» 1개(끝에 정리).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; BIN="$REPO/harness/bin"
T="$(mktemp -d)"; BGP=""
cleanup() { [ -z "$BGP" ] || { pkill -P "$BGP" 2>/dev/null; kill "$BGP" 2>/dev/null; }; rm -rf "$T"; }; trap cleanup EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
O=byz-feature-master-claude#78; N=byz-feature-master-claude#79
bash -c 'tail -f /dev/null; :' & BGP=$!
mkdir -p "$T/stub"
printf '#!/bin/sh\ncase "$1" in list-panes) echo %s;; *) exit 1;; esac\n' "$BGP" > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/bin/sh\n[ "$1 $2" = "pending --each" ] && echo "h62 3"\nexit 0\n' > "$T/stub/ft-hil.sh"

roster() {   # roster <retired 0|1> — 옛 #78 · 후계 #79(spawn 이 이미 등록) · retired=1 = ft-seat-retire 뒤 꼴
  python3 - "$ENVROOT/seats/seats-feature.json" "$1" "$O" "$N" <<'PY'
import json, sys
p, r, o, n = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
d = {"_master": n if r else o, o: {"role": "master"}, n: {"role": "master"}}
if r: d[o] = {"role": "stop-ready", "_replaced_by": n}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수]
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; printf '{}\n' > "$ENVROOT/seats/seats.json"; roster 0; : > "$Q"
  if [ -n "${1:-}" ]; then "$1"; fi
}
row() { printf '{"seq": %s, "ts": "2026-10-29T00:00:00", "to": "%s", "from": "slack-oppa", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
xenv() { env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_HIL_BIN="$T/stub/ft-hil.sh" \
  FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" "$@"; }
sh_() { OUT="$(cd "$ENVROOT" && xenv bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$ENVROOT" && xenv python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
nread() { printf '%s\n' "$OUT" | grep -c '^READ \['; }
mut_norecord() { printf '\nrecord = lambda me, rows: None\n' >> "$C/mbox_handover.py"; }

# ① 증류 중: [HIL] 1통을 옛 #78 이 recv(영수 미표시) + 또 1통이 큐에 남음 → retire 관문(--no-ready) 거절
chk_1() {
  new_env "${1:-}"; row 1 "$O" "[HIL] TTS 결정 질문"; sh_ recv "$O"; [ "$(nread)" = 1 ] || return 1
  row 2 "$O" "[HIL] 두 번째 질문"; py close-check "$O" --no-ready; [ "$RC" = 3 ] && case "$OUT" in *'미표시 쪽지 1 (#1)'*) true;; *) false;; esac
}
chk_1 mut_norecord && bad "변이(영수 기록 끔)가 ① 에 안 잡힘" || ok "변이(영수 기록 끔) → ① FAIL 확인"
chk_1 && ok "① recv 한 [HIL] 미표시 1 → close-check --no-ready REJECT rc3" || bad "① 미표시 거절 :: $OUT"   # 이 환경을 ②~④ 가 잇는다(변이 환경 아님)
OUT="$(cd "$ENVROOT" && xenv bash "$BIN/ft-seat-retire.sh" "$O" "$N" --seats "$ENVROOT/seats/seats-feature.json" 2>&1)"; RC=$?
[ "$RC" = 4 ] && case "$OUT" in *'REJECT 승계 전 쪽지 마무리'*'#1'*) true;; *) false;; esac && grep -q "\"$O\": {\"role\": \"master\"}" "$ENVROOT/seats/seats-feature.json" \
  && ok "① ft-seat-retire 관문 rc4 · 명부 쓰기 0" || bad "① retire 관문 rc=$RC :: $OUT"

# ② handover: 남은 쪽지 끝까지 recv(#2) + 미표시 #1 + h62 + bg(tail) + 손 항목 → [인계] 1통 · #1·#2 «인계» 표시
sh_ handover "$O" "$N" "백그라운드 pytest 1개"
H="$(grep -o '"seq": [0-9]*, "ts": "[^"]*", "to": "'"$N"'", "from": "'"$O"'"' "$Q" | grep -o '"seq": [0-9]*' | grep -o '[0-9]*$')"
B="$(python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]["body"])' "$Q")"
[ "$RC" = 0 ] && [ -n "$H" ] && case "$B" in *"- #1 [slack-oppa]"*"- #2 [slack-oppa]"*"- h62 "*"- bg:"*"tail -f /dev/null"*"- bg:x1 백그라운드 pytest 1개"*) true;; *) false;; esac \
  && case "$OUT" in *"MARKED $O 인계 1,2"*) true;; *) false;; esac && ok "② [인계] #$H 항목(오빠 질문 2·h62·bg·손) + #1·#2 인계 표시" || bad "② handover rc=$RC :: $OUT :: $B"
py close-check "$O" --no-ready; [ "$RC" = 0 ] && ok "② 표시 뒤 retire 관문 통과(CLOSE-OK)" || bad "② 표시 뒤 관문 :: $OUT"

# ③ retire 뒤: 레디 0 = 옛 세션 닫기 거절 · 후계가 [인계] 를 recv 하기 전 ready 거절
roster 1
py close-check "$O"; [ "$RC" = 3 ] && case "$OUT" in *'[레디] 없음'*) true;; *) false;; esac && ok "③ [레디] 회신 0 → 닫기 REJECT" || bad "③ 레디 0 :: $OUT"
OUT="$(cd "$ENVROOT" && xenv bash "$BIN/ft-seat-close.sh" "$O" --reason "시험" --seats "$ENVROOT/seats/seats-feature.json" 2>&1)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'승계 마무리 전 닫기 거절'*) true;; *) false;; esac && ok "③ ft-seat-close 관문 rc1 · kill 0" || bad "③ seat-close 관문 rc=$RC :: $OUT"
sh_ ready "$N" "$O"; [ "$RC" = 3 ] && case "$OUT" in *'아직 recv 안 함'*) true;; *) false;; esac && ok "③ recv 전 ready REJECT" || bad "③ recv 전 ready :: $OUT"

# ④ 후계 첫 recv 에 [인계] READ → ready = 항목마다 «받음» → 옛 세션 닫기 통과 · 옛 세션은 [레디] 만 받는다
sh_ recv "$N"; case "$OUT" in *"READ [$O->$N] #$H"*'[인계]'*) ok "④ 후계 첫 recv 에 [인계] #$H READ";; *) bad "④ 후계 recv :: $OUT";; esac
sh_ ready "$N" "$O"; R="$(python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]["body"])' "$Q")"
[ "$RC" = 0 ] && case "$R" in "[레디]"*"#$H 받음"*"#1 받음"*"#2 받음"*"h62 받음"*"bg:x1 받음"*) true;; *) false;; esac && ok "④ [레디] 에 #1(증류 중 [HIL]) 받음 포함" || bad "④ ready rc=$RC :: $OUT :: $R"
py close-check "$O"; [ "$RC" = 0 ] && case "$OUT" in *'전부 받음'*) true;; *) false;; esac && ok "④ 옛 세션 닫기 관문 통과" || bad "④ 닫기 관문 :: $OUT"
sh_ recv "$O"; [ "$(nread)" = 1 ] && case "$OUT" in *'[레디]'*) true;; *) false;; esac && ok "④ 은퇴한 옛 세션 recv = [레디] 1통만" || bad "④ 옛 세션 레디 recv :: $OUT"

# ⑤ [레디] 에 항목 하나 빠짐(h62) → 닫기 REJECT 그 항목 이름
new_env; row 1 "$O" "[HIL] q"; sh_ recv "$O"; sh_ handover "$O" "$N"; roster 1; sh_ recv "$N"
H="$(python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]["seq"])' "$C/mailbox.log.jsonl")"
sh_ send "$O" "$N" "[레디] 손으로 · #$H 받음
#1 받음"
py close-check "$O"; [ "$RC" = 3 ] && case "$OUT" in *'«받음» 없는 항목 h62'*) true;; *) false;; esac && ok "⑤ 항목 빠진 [레디] → REJECT h62" || bad "⑤ 빠진 항목 :: $OUT"

# ⑥ 후계 없는 닫기(나노·판정 닫기)는 검사 대상 아님 · 회귀: 자기가 보낸 쪽지는 안 받는다
new_env; py close-check "$N"; [ "$RC" = 0 ] && ok "⑥ 후계 없는 좌석 close-check = 대상 아님 rc0" || bad "⑥ :: $OUT"
sh_ send "$N" "$O" "[부팅 보고] x"; sh_ recv "$O"; [ "$(nread)" = 0 ] && ok "⑥ 같은 역할 자기 발신 행은 자기 recv 에 안 옴" || bad "⑥ 자기 발신 :: $OUT"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
