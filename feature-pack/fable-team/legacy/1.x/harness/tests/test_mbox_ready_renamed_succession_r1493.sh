#!/usr/bin/env bash
# test_mbox_ready_renamed_succession_r1493.sh — r1493 · 개명 승계(-claude#N → -pi#N+1)에서 옛 좌석이 닫히는 «두 지점».
#  가드 수신자 판정 = T1 개명 후계 [레디] WARN 통과 · T2 비후계 [레디] REJECT · T3 다른 머리 REJECT 불변 · T8 현역 수신자 경로 그대로.
#  close-check = T4 개명 후계 [레디] CLOSE-OK · T5 번호 승계 회귀 CLOSE-OK · T6 «받음» 누락 REJECT · T7 같은 역할 키 비후계 [레디] REJECT.
#  격리: 정본 comm 사본 + 가짜 명부(seats-zz.json) + 임시 우편함 · 실 명부·실 큐·실 tmux 0 · 고정 sleep 0 · 자기 재호출 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
M=byz-zz-master-pi#3; OLD=byz-zz-arch-claude#1; SUCC=byz-zz-arch-pi#2   # 개명 승계 = 역할 키가 다르다
N7=byz-zz-arch-pi#7; N8=byz-zz-arch-pi#8; N9=byz-zz-arch-pi#9          # 번호 승계(역할 키 같음) + 같은 역할 키 비후계
OTHER=byz-zz-da-codex#9; SIB=byz-zz-arch-claude#9   # SIB = OLD 와 같은 역할 키 현역(DA R1 반례 재료)

roster() {   # 개명 사슬 OLD→SUCC · 번호 사슬 N7→N8 · 같은 역할 키 비후계 N9 · 무관 좌석 OTHER
  python3 - "$ENVROOT/seats/seats-zz.json" "$M" "$OLD" "$SUCC" "$N7" "$N8" "$N9" "$OTHER" <<'PY'
import json, sys
p, m, o, s, n7, n8, n9, other = sys.argv[1:9]
json.dump({"_master": m, m: {"role": "master"}, o: {"role": "stop-ready", "_replaced_by": s},
           s: {"role": "arch", "_replaces": [o]}, n7: {"role": "arch", "_replaced_by": n8},
           n8: {"role": "arch", "_replaces": [n7]}, n9: {"role": "arch", "_replaces": []},
           other: {"role": "da"}}, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수] — 격리 루트 하나(정본 사본 + 가짜 명부 + 빈 큐)
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"
  printf '{}\n' > "$ENVROOT/seats/seats.json"; roster; : > "$Q"
  [ -z "${1:-}" ] || "$1"
}
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$ENVROOT/.fable-team/state"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py"
  "$@" ); }
sh_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$ENVROOT" && xenv timeout 20 python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
queued() { local n; n="$(grep -c "\"to\": *\"$1\"" "$Q" 2>/dev/null)"; echo "${n:-0}"; }
hbody() { printf '[인계] %s -> %s · 항목 2 · [레디] 는 항목마다 «<id> 받음»(bash mbox.sh ready %s %s)\n답 안 한 오빠 질문: 0\n남은 회신·쪽지: 2\n- #1 [%s] q1 (전문: mailbox.log.jsonl seq 1)\n- #2 [%s] q2 (전문: mailbox.log.jsonl seq 2)' "$1" "$2" "$2" "$1" "$M" "$M"; }
rbdy() { printf '[레디] %s <- %s · [인계] #%s 받음 · 항목 2\n#1 받음\n%s' "$1" "$2" "$3" "$4"; }
roster_closed() {   # DA #275493 R1 반례 — 후계 SUCC 가 role=closed · 같은 역할 키(OLD 팀) 현역 SIB 1석
  python3 - "$ENVROOT/seats/seats-zz.json" "$M" "$OLD" "$SUCC" "$SIB" <<'PY'
import json, sys
p, m, o, s, sib = sys.argv[1:6]
json.dump({"_master": m, m: {"role": "master"}, o: {"role": "stop-ready", "_replaced_by": s},
           s: {"role": "closed", "_replaces": [o]}, sib: {"role": "arch", "_replaces": []}}, open(p, "w", encoding="utf-8"))
PY
}
mut_reuse_closed() { python3 - "$C/mbox_guard.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace('crow.get("role") not in ("closed", "stopped")', 'not closed')
open(p, "w", encoding="utf-8").write(s)
PY
  grep -q 'frm == cur and not closed and isinstance' "$C/mbox_guard.sh"; }
mut_guard_off() { sed -i '' 's/if head.startswith("\[레디\]") and frm == cur/if False and frm == cur/' "$C/mbox_guard.sh"; grep -q 'if False and frm == cur' "$C/mbox_guard.sh"; }
mut_role_key() { sed -i '' 's/and r.get("from") == succ and/and role_key(r.get("from")) == role_key(seat) and/' "$C/mbox_handover.py"; grep -q 'role_key(r.get("from")) == role_key(seat)' "$C/mbox_handover.py"; }
setup_handover() {   # setup_handover <old> <succ> — 옛 좌석이 후계에 [인계] 1통(HS = 그 seq)
  sh_ send "$2" "$1" "$(hbody "$1" "$2")" || return 1
  HS="$(printf '%s\n' "$OUT" | sed -n 's/^QUEUED seq=\([0-9]*\).*/\1/p' | head -1)"
  [ -n "$HS" ]
}

# ── T1 개명 후계 [레디] → WARN 1줄 + 옛 좌석 우편함에 적재(닫기 증거가 남는다)
t1() {   # t1 [변이함수]
  new_env "${1:-}" || return 2; setup_handover "$OLD" "$SUCC" || return 2
  sh_ send "$OLD" "$SUCC" "$(rbdy "$SUCC" "$OLD" "$HS" $'#2 받음')"
  [ "$RC" = 0 ] && case "$OUT" in *'개명 승계 [레디]'*'은퇴 좌석 '"$OLD"' 우편함에 기록'*) true;; *) false;; esac \
    && [ "$(queued "$OLD")" = 1 ]
}
t1 && ok "T1 개명 후계 [레디] → rc0 · WARN 1줄 · 옛 좌석 큐 1" || bad "T1 rc=$RC :: $OUT"
t1 mut_guard_off; [ $? = 1 ] && ok "T1 변이(개명 [레디] 예외 끔) = 빨강(REJECT 후계 안내)" || bad "T1 변이가 안 잡힘 rc=$RC :: $OUT"

# ── T2 비후계 [레디] → REJECT rc3 · 큐 0
new_env; sh_ send "$OLD" "$OTHER" "$(rbdy "$OTHER" "$OLD" 1 $'#2 받음')"
[ "$RC" = 3 ] && case "$OUT" in *'후계 이름으로 다시 보내라'*) true;; *) false;; esac && [ "$(queued "$OLD")" = 0 ] \
  && ok "T2 비후계 [레디] → REJECT rc3 · 큐 0" || bad "T2 rc=$RC :: $OUT"

# ── T3 다른 머리(후계 발신) → REJECT 불변
new_env; sh_ send "$OLD" "$SUCC" '[진행] 50% 했다'
[ "$RC" = 3 ] && case "$OUT" in *'후계 이름으로 다시 보내라'*) true;; *) false;; esac && [ "$(queued "$OLD")" = 0 ] \
  && ok "T3 후계 발신 다른 머리 → REJECT rc3(불변)" || bad "T3 rc=$RC :: $OUT"

# ── T8 현역 수신자 경로 불변 = 수신자 판정 WARN 0 · rc0
new_env; sh_ send "$SUCC" "$M" "$(rbdy "$SUCC" "$SUCC" 1 $'#2 받음')"
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '개명 승계\|은퇴한 좌석\|옛 번호')" = 0 ] && [ "$(queued "$SUCC")" = 1 ] \
  && ok "T8 현역 수신자 [레디] → rc0 · 수신자 판정 WARN 0" || bad "T8 rc=$RC :: $OUT"

# ── T4 개명 승계 close-check = 후계 정확 일치 → CLOSE-OK
new_env; setup_handover "$OLD" "$SUCC" && sh_ send "$OLD" "$SUCC" "$(rbdy "$SUCC" "$OLD" "$HS" $'#2 받음')"
py close-check "$OLD"
[ "$RC" = 0 ] && case "$OUT" in CLOSE-OK*'항목 2 전부 받음'*) true;; *) false;; esac \
  && ok "T4 개명 승계 ready → close-check CLOSE-OK" || bad "T4 rc=$RC :: $OUT"
new_env mut_role_key; setup_handover "$OLD" "$SUCC" && sh_ send "$OLD" "$SUCC" "$(rbdy "$SUCC" "$OLD" "$HS" $'#2 받음')"; py close-check "$OLD"
[ "$RC" = 3 ] && case "$OUT" in *'후계 [레디] 없음'*) true;; *) false;; esac \
  && ok "T4 변이(role_key 조건) = 빨강(개명 승계 REJECT)" || bad "T4 변이가 안 잡힘 rc=$RC :: $OUT"

# ── T5 번호 승계 회귀 = CLOSE-OK
new_env; setup_handover "$N7" "$N8" && sh_ send "$N7" "$N8" "$(rbdy "$N8" "$N7" "$HS" $'#2 받음')"
py close-check "$N7"
[ "$RC" = 0 ] && case "$OUT" in CLOSE-OK*) true;; *) false;; esac && ok "T5 번호 승계(#7→#8) 회귀 CLOSE-OK" || bad "T5 rc=$RC :: $OUT"

# ── T6 [레디] 항목 하나 누락 → REJECT 그 항목
new_env; setup_handover "$OLD" "$SUCC" && sh_ send "$OLD" "$SUCC" "$(rbdy "$SUCC" "$OLD" "$HS" '')"
py close-check "$OLD"
[ "$RC" = 3 ] && case "$OUT" in *'«받음» 없는 항목 #2'*) true;; *) false;; esac \
  && ok "T6 «받음» 누락(#2) → REJECT" || bad "T6 rc=$RC :: $OUT"

# ── T7 같은 역할 키 비후계 #9 의 [레디] → close-check REJECT(가드는 옛 번호 규칙으로 통과시킨다)
new_env; setup_handover "$N7" "$N8" && sh_ send "$N7" "$N9" "$(rbdy "$N9" "$N7" "$HS" $'#2 받음')"
[ "$RC" = 0 ] && ok "T7 비후계 #9 [레디] 자체는 가드 통과(같은 역할 키 옛 번호 규칙)" || bad "T7 send rc=$RC :: $OUT"
py close-check "$N7"
[ "$RC" = 3 ] && case "$OUT" in *'후계 [레디] 없음'*) true;; *) false;; esac \
  && ok "T7 같은 역할 키 비후계 #9 → close-check REJECT" || bad "T7 rc=$RC :: $OUT"

# ── T9 (DA #275493 R1) 닫힌 후계의 [레디] → REJECT · 큐 0 — 사슬 끝 «닫힘» 판정은 closed 덮어쓴 값이 아니라 사슬 끝 행 자체
t9() {   # t9 [변이함수]
  new_env "${1:-}" || return 2; roster_closed
  sh_ send "$OLD" "$SUCC" "$(rbdy "$SUCC" "$OLD" 1 $'#2 받음')"
  [ "$RC" = 3 ] && [ "$(queued "$OLD")" = 0 ]
}
t9 && ok "T9 닫힌 후계 [레디] → REJECT rc3 · 큐 0" || bad "T9 rc=$RC :: $OUT"
t9 mut_reuse_closed; [ $? = 1 ] && ok "T9 변이(closed 덮어쓴 값 재사용) = 빨강" || bad "T9 변이가 안 잡힘 rc=$RC :: $OUT"

# ── 문법
for f in "$SRC/mbox_guard.sh" "$SRC/mbox_handover.py"; do
  case "$f" in *.sh) bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")";;
             *) python3 -c 'import sys,py_compile;py_compile.compile(sys.argv[1],doraise=True)' "$f" >/dev/null 2>&1 && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")";; esac
done

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
