#!/usr/bin/env bash
# test_mbox_handover_union_r1653.sh — r1653 단계 1 [fix]: 승계 핸드셰이크가 «마지막 [인계] 1통» 만 보던 자리를 합집합으로.
#  ① [인계] 2통(항목 3 · 1) → [레디] 합집합 항목 4 · close-check OK  ② 손으로 만든 옛 꼴([레디] 가 둘째 통만 받음) → close-check REJECT(첫 통 항목)
#  ⑤ DA R1-a = 옛 꼴 [레디] 뒤 새 [레디] 가 앞 통을 덮어 미받음 3건 누락(seq cut) → REJECT  ⑥ DA R1-b = 완료된 통 재포함 0(항목 단위 완료)
#  ③ 첫 [인계] 뒤 [레디] 완료 → 둘째 [인계] 만 → [레디] 항목 1(앞 묶음 다시 안 셈)  ④ 재 handover = 미받음 항목만 재적재(받음 끝난 항목 0)
#  변이 M1 last_handover 1통 → ①②⑤ FAIL · M2 재송신 재적재 삭제 → ④ FAIL · M4 항목 단위 완료 확인 끔 → ⑥ FAIL · 격리: 정본 사본 + 가짜 명부(seats-union.json) + 임시 우편함 · 실 명부·큐·tmux 0 · sleep 0 · 자기 재호출 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/bin/sh\n[ "$1 $2" = "--pending --each" ] && { echo "h62 3"; exit 0; }\nexit 2\n' > "$T/stub/ft-hil.sh"
O=byz-union-old-pi#1; N=byz-union-new-pi#2

roster() {   # roster <retired 0|1>
  python3 - "$ENVROOT/seats/seats-union.json" "$1" "$O" "$N" <<'PY'
import json, sys
p, r, o, n = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
o_row = {"role": "stop-ready", "_replaced_by": n} if r else {"role": "master"}
json.dump({"_master": n if r else o, o: o_row, n: {"role": "master"}}, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수]
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; printf '{}\n' > "$ENVROOT/seats/seats.json"; roster 0; : > "$Q"
  [ -z "${1:-}" ] || "$1"
}
row() { printf '{"seq": %s, "ts": "2026-11-11T00:00:00", "to": "%s", "from": "slack-oppa", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats-union.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$ENVROOT/.fable-team/state"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" FT_HIL_BIN="$T/stub/ft-hil.sh"
  "$@" ); }
sh_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$ENVROOT" && xenv timeout 20 python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
seqof() { printf '%s\n' "$OUT" | sed -n 's/^QUEUED seq=\([0-9]*\).*/\1/p' | head -1; }
lastbody() { python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()][-1]["body"])' "$C/mailbox.log.jsonl" 2>/dev/null; }
hsend() {   # hsend <항목 id…> — 옛 좌석이 후계로 기계 [인계] 1통(연달아 내는 꼴)
  local ids=("$@") b="[인계] $O -> $N · 항목 ${#ids[@]} · [레디] 는 항목마다 «<id> 받음»(bash mbox.sh ready $N $O)"$'\n'"답 안 한 오빠 질문: 0"$'\n'"남은 회신·쪽지: ${#ids[@]}"
  for i in "${ids[@]}"; do b+=$'\n'"- $i [slack-oppa] 항목 $i (전문: mailbox.log.jsonl seq 1)"; done; sh_ send "$N" "$O" "$b"; }
mut_m1() { printf '\ndef handover_group(old, new):\n    h = last_handover(old, new)\n    return [h] if h else []\n' >> "$C/mbox_handover.py"; grep -q 'h = last_handover(old, new)' "$C/mbox_handover.py"; }
mut_m4() { printf '\ndef handover_group(old, new):\n    return _handovers(old, new)\n' >> "$C/mbox_handover.py"; grep -q 'return _handovers(old, new)$' "$C/mbox_handover.py"; }
mut_m2() { printf '\ndef _resent(old, new):\n    return []\n' >> "$C/mbox_handover.py"; grep -q 'def _resent(old, new):' "$C/mbox_handover.py"; }
setup2() {   # setup2 — [인계] 2통(항목 3 · 1) + 후계 recv · retire 완료(H1·H2 = 그 seq)
  row 1 "$O" "[HIL] q1"; row 2 "$O" "[HIL] q2"; sh_ recv "$O"
  sh_ handover "$O" "$N"; H1="$(seqof)"; [ -n "$H1" ] || return 1
  hsend "#9"; H2="$(seqof)"; [ -n "$H2" ] || return 1
  roster 1; sh_ recv "$N"
}

# ① [인계] 2통(항목 3 · 항목 1) → [레디] = 합집합 항목 4 → close-check CLOSE-OK
chk_1() {
  new_env "${1:-}" || return 2; setup2 || return 2
  sh_ ready "$N" "$O"; [ "$RC" = 0 ] || return 1
  B="$(lastbody)"; case "$B" in "[레디] $N <- $O · [인계] #$H1,$H2 받음 · 항목 4"*) ;; *) return 1;; esac
  for i in '#1 받음' '#2 받음' 'h62 받음' '#9 받음'; do case "$B" in *"$i"*) ;; *) return 1;; esac; done
  py close-check "$O"; [ "$RC" = 0 ] && case "$OUT" in *"CLOSE-OK*[$H1,$H2]"*) true;; CLOSE-OK*) true;; *) false;; esac
}
chk_1 mut_m1 && bad "M1 변이(last_handover 1통)가 ① 에 안 잡힘" || ok "M1 변이(last_handover 1통) → ① FAIL 확인"
chk_1 && ok "① [인계] 2통 → [레디] 합집합 항목 4 · close-check CLOSE-OK" || bad "① rc=$RC :: $OUT :: $B"

# ② [레디] 가 둘째 통 항목만 받음(손으로 만든 옛 꼴) → close-check REJECT 그 첫 통 항목
chk_2() {
  new_env "${1:-}" || return 2; setup2 || return 2
  sh_ send "$O" "$N" "[레디] $N <- $O · [인계] #$H2 받음 · 항목 1"$'\n'"#9 받음"; [ "$RC" = 0 ] || return 2
  py close-check "$O"; [ "$RC" = 3 ] || return 1; case "$OUT" in *'«받음» 없는 항목'*) ;; *) return 1;; esac
  for i in '#1' '#2' 'h62'; do case "$OUT" in *"$i"*) ;; *) return 1;; esac; done
}
chk_2 mut_m1 && bad "M1 변이(last_handover 1통)가 ② 에 안 잡힘" || ok "M1 변이 → ② FAIL 확인"
chk_2 && ok "② 둘째 통만 받은 [레디] → close-check REJECT(첫 통 항목 #1)" || bad "② rc=$RC :: $OUT"
# ③ 첫 [인계] 뒤 [레디] 완료 → 둘째 [인계] 만 → [레디] 항목 1(앞 묶음 다시 안 셈) · close-check OK
chk_3() {
  new_env; row 1 "$O" "[HIL] q1"; sh_ recv "$O"; sh_ handover "$O" "$N"; H1="$(seqof)"
  roster 1; sh_ recv "$N"; sh_ ready "$N" "$O"; R1="$(seqof)"
  hsend "#9"; H2="$(seqof)"; sh_ recv "$N"; sh_ ready "$N" "$O"; B="$(lastbody)"
  case "$B" in "[레디] $N <- $O · [인계] #$H2 받음 · 항목 1"*) ;; *) return 1;; esac   # 둘째 [인계] 만
  case "$B" in *"#9 받음"*) ;; *) return 1;; esac; case "$B" in *"#1 받음"*) return 1;; esac
  py close-check "$O"; [ "$RC" = 0 ] || return 1
  case "$OUT" in "CLOSE-OK"*"#$H2 → "*"항목 1 전부 받음"*) ;; *) return 1;; esac   # 앞 묶음(H1) 다시 안 셈
}
chk_3 && ok "③ 첫 [인계] 뒤 [레디] 완료 → 둘째 [인계] 만 · [레디] 항목 1($H2 · R1=$R1)" || bad "③ rc=$RC :: $OUT :: $B"
# ⑤ DA R1-a — 옛 꼴 [레디](#9 만) 뒤 새 [레디](#10 만) → 앞 통 미받음 3건이 누락되던 자리(seq 로 자르던 cut 규칙) → REJECT
chk_5() {
  new_env "${1:-}" || return 2; setup2 || return 2
  sh_ send "$O" "$N" "[레디] $N <- $O · [인계] #$H2 받음 · 항목 1"$'\n'"#9 받음"
  hsend "#10"; H3="$(seqof)"; sh_ recv "$N"
  sh_ send "$O" "$N" "[레디] $N <- $O · [인계] #$H3 받음 · 항목 1"$'\n'"#10 받음"
  py close-check "$O"; [ "$RC" = 3 ] || return 1; for i in '#1' '#2' 'h62'; do case "$OUT" in *"$i"*) ;; *) return 1;; esac; done
}
chk_5 mut_m1 && bad "M1 변이(마지막 1통)가 ⑤ 에 안 잡힘" || ok "M1 변이 → ⑤ FAIL 확인"
chk_5 && ok "⑤ DA R1-a — 옛 꼴 [레디] 뒤 새 [레디] → 미받음 #1·#2·h62 REJECT" || bad "⑤ rc=$RC :: $OUT"
# ⑥ DA R1-b — H1·H2 를 합집합 [레디] 로 완료 → H3 → 다음 [레디] 항목 1(기존 4 재포함 0)
chk_6() {
  new_env "${1:-}" || return 2; setup2 || return 2
  sh_ ready "$N" "$O"; [ "$RC" = 0 ] || return 2                  # 항목 4 받음
  hsend "#10"; H3="$(seqof)"; sh_ recv "$N"; sh_ ready "$N" "$O"; B="$(lastbody)"
  case "$B" in "[레디] $N <- $O · [인계] #$H3 받음 · 항목 1"*) case "$B" in *"#9 받음"*) return 1;; *) true;; esac;; *) return 1;; esac
}
chk_6 mut_m4 && bad "M4 변이(항목 단위 완료 확인 끔)가 ⑥ 에 안 잡힘" || ok "M4 변이(완료 확인 끔) → ⑥ FAIL 확인"
chk_6 && ok "⑥ DA R1-b — [인계] H3 만 [레디] 항목 1(기존 4 재포함 0)" || bad "⑥ rc=$RC :: $B"

# ④ 재 handover = 미받음 항목만 재적재(받음 끝난 항목 0)
chk_4() {
  new_env "${1:-}" || return 2
  row 1 "$O" "[HIL] q1"; row 2 "$O" "[HIL] q2"; sh_ recv "$O"; sh_ handover "$O" "$N"; H1="$(seqof)"; [ -n "$H1" ] || return 2
  roster 1; sh_ recv "$N"; sh_ send "$O" "$N" "[레디] $N <- $O · [인계] #$H1 받음 · 항목 1"$'\n'"#1 받음"   # #1 만 받음
  sh_ recv "$O"; sh_ handover "$O" "$N"; B="$(lastbody)"
  [ "$(printf '%s\n' "$B" | sed -n 's/^항목: *//p')" = "#2 h62" ]   # r1863 새 꼴 = id 묶음 줄
}
chk_4 mut_m2 && bad "M2 변이(재송신 재적재 삭제)가 ④ 에 안 잡힘" || ok "M2 변이(재송신 재적재 삭제) → ④ FAIL 확인"
chk_4 && ok "④ 재 handover = 미받음 #2 만 재적재 · 받음 끝난 #1 0" || bad "④ 재적재 :: $B"

for f in "$SRC/mbox_handover.py" "$SRC/mbox.sh"; do
  case "$f" in *.sh) bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")";;
             *) python3 -c 'import sys,py_compile;py_compile.compile(sys.argv[1],doraise=True)' "$f" >/dev/null 2>&1 && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")";; esac
done
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
