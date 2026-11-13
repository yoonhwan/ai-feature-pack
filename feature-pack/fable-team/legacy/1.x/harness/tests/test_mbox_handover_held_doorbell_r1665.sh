#!/usr/bin/env bash
# test_mbox_handover_held_doorbell_r1665.sh — r1665 [fix]: 증류 게이트로 recv 가 막힌 옛 좌석도 승계가 끝까지 간다.
#  ⓐ 억제 doorbell seq 2개(옛 좌석 큐에 남음) → [인계] 항목 2개 · QUEUED 뒤 기록 = doorbell-held/done/<좌석>-<ts> · ⓑ 그 뒤 후계 recv·ready → close-check CLOSE-OK rc0(= ft-seat-retire 첫 관문)
#  ⓒ 송신 실패 = 기록 그대로 · close-check REJECT 그대로 · ⓓ 기록이 남은 close-check 둘째 줄 = 후계 pane 3명령 · ⓔ 억제 기록 없는 승계 출력 불변 · ⓕ 억제분 아닌 안 받은 seq = mark REJECT 유지
#  ⓖ DA 재현: 본문에 «[억제 doorbell]» 이 든 일반 쪽지도 표시 유지 · 변이 M1 _held_seqs=[] → ⓐ FAIL · M2 이동을 송신 «전» 으로 → ⓒ FAIL · 격리: 정본 사본 + 가짜 명부 + 임시 우편함 · sleep 0 · 자기 재호출 0
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/bin/sh\n[ "$1 $2" = "--pending --each" ] && { echo "h62 3"; exit 0; }\nexit 2\n' > "$T/stub/ft-hil.sh"
O=byz-held-old-pi#1; N=byz-held-new-pi#2

roster() {   # roster <후계 role> [live] — 기본 = 옛 좌석 «이미 은퇴»(_replaced_by) = 증류 게이트 승계의 실측 상태
  python3 - "$ENVROOT/seats/seats-held.json" "${1:-master}" "${2:-}" "$O" "$N" <<'PY'
import json, sys
p, nrole, mode, o, n = sys.argv[1:6]
live = mode == "live"
json.dump({"_master": o if live else n, o: {"role": "master"} if live else {"role": "stop-ready", "_replaced_by": n}, n: {"role": nrole}}, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수]
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; SD="$ENVROOT/.fable-team/state"
  mkdir -p "$C" "$SD/doorbell-held" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; printf '{}\n' > "$ENVROOT/seats/seats.json"; roster master; : > "$C/mailbox.jsonl"
  [ -z "${1:-}" ] || "$1"
}
held() { printf 'held ts=1790000000 reason=held window=1 seat=%s\nseq=1\nseq=2\n' "$O" > "$SD/doorbell-held/$O"; }
queued() {   # 억제된 doorbell 의 본체는 옛 좌석 앞 큐에 남아 있다
  printf '{"seq": 1, "ts": "2026-11-11T00:00:00", "to": "%s", "from": "slack-oppa", "body": "[HIL] q1"}\n' "$O" >> "$C/mailbox.jsonl"
  printf '{"seq": 2, "ts": "2026-11-11T00:00:00", "to": "%s", "from": "slack-oppa", "body": "[HIL] q2"}\n' "$O" >> "$C/mailbox.jsonl"
}
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats-held.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$SD"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" FT_HIL_BIN="$T/stub/ft-hil.sh"
  "$@" ); }
sh_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
lastbody() { python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()][-1]["body"])' "$C/mailbox.log.jsonl" 2>/dev/null; }
mut_m1() { printf '\ndef _held_seqs(seat):\n    return []\n' >> "$C/mbox_handover.py"; grep -q '^\s*return \[\]$' "$C/mbox_handover.py"; }
mut_m2() {   # 이동 2줄을 send «앞» 으로 옮긴다
  python3 - "$C/mbox.sh" <<'PY'
import sys
p = sys.argv[1]; L = open(p, encoding="utf-8").read().splitlines(True)
i = next(k for k, l in enumerate(L) if 'send "$new" "$old" "$b"' in l); j = next(k for k, l in enumerate(L) if '_hf="$(_wg_state)/doorbell-held/' in l)
blk = L[j:j + 2]; del L[j:j + 2]; L[i:i] = blk; open(p, "w", encoding="utf-8").writelines(L)
PY
}

# ⓐ 넘기기 — 억제 doorbell 2건이 [인계] 항목이 되고, QUEUED 뒤 기록은 보관 폴더로
chk_a() {
  new_env "${1:-}" || return 2; held; queued
  sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1
  B="$(lastbody)"; for i in '· 항목 3 ' $'\n항목: #1! #2! '; do case "$B" in *"$i"*) ;; *) return 1;; esac; done
  [ ! -f "$SD/doorbell-held/$O" ] && [ "$(ls "$SD/doorbell-held/done/" 2>/dev/null | grep -c "^$O-")" = 1 ] || return 1
  grep -qx 'seq=2' "$SD"/doorbell-held/done/"$O"-* 2>/dev/null || return 1
}
chk_a mut_m1 && bad "M1 변이(억제 항목 싣기 삭제)가 ⓐ 에 안 잡힘" || ok "M1 변이 → ⓐ FAIL 확인"
chk_a && ok "ⓐ 억제 doorbell 2건 → [인계] 항목 2개 · done/<좌석>-<ts> 이동" || bad "ⓐ rc=$RC :: $OUT :: $B"

# ⓑ 닫기 — 넘긴 뒤 후계 recv·ready → close-check CLOSE-OK (retire 첫 관문이 같은 검사다)
chk_b() {
  new_env || return 2; held; queued
  sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 2
  sh_ recv "$N"; [ "$RC" = 0 ] || return 1; sh_ ready "$N" "$O"; [ "$RC" = 0 ] || return 1
  B="$(lastbody)"; for i in '#1 받음' '#2 받음'; do case "$B" in *"$i"*) ;; *) return 1;; esac; done
  py_ close-check "$O" --no-ready; [ "$RC" = 0 ] || return 1
  py_ close-check "$O"; [ "$RC" = 0 ]
}
chk_b && ok "ⓑ 넘긴 뒤 후계 recv·ready → close-check CLOSE-OK rc0" || bad "ⓑ rc=$RC :: $OUT :: $B"

# ⓒ 송신 실패면 기록 그대로 (변이 M2 = 송신 전 이동이면 여기서 잡힌다)
chk_c() {
  new_env "${1:-}" || return 2; held; queued; roster closed      # 닫힌 좌석 = send REJECT
  sh_ handover "$O" "$N"; [ "$RC" != 0 ] || return 1
  [ -f "$SD/doorbell-held/$O" ] && [ -z "$(ls "$SD/doorbell-held/done/" 2>/dev/null)" ] || return 1
  py_ close-check "$O" --no-ready; [ "$RC" = 3 ] && case "$OUT" in *"억제된 doorbell 2건 미전달"*) true;; *) false;; esac
}
chk_c mut_m2 && bad "M2 변이(송신 전 이동)가 ⓒ 에 안 잡힘" || ok "M2 변이 → ⓒ FAIL 확인"
chk_c && ok "ⓒ 송신 실패 = 기록 그대로 · close-check REJECT 그대로" || bad "ⓒ rc=$RC :: $OUT"

# ⓓ 막힐 때 다음 줄
chk_d() {
  new_env || return 2; held; queued
  py_ close-check "$O" --no-ready; [ "$RC" = 3 ] && case "$OUT" in *"다음(후계 pane): bash mbox.sh recv '$N' → bash mbox.sh handover '$O' '$N' → bash ft-seat-retire.sh '$O' '$N'"*) true;; *) false;; esac
}
chk_d && ok "ⓓ 막힌 close-check 둘째 줄 = 후계 pane 3명령" || bad "ⓓ rc=$RC :: $OUT"

# ⓔ 회귀 — 억제 기록 없는 승계 출력 불변
chk_e() {
  new_env || return 2; queued
  sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1; B="$(lastbody)"; case "$B" in *"억제 doorbell 0 "*) ;; *) return 1;; esac
  [ -d "$SD/doorbell-held/done" ] && return 1; py_ close-check "$O" --no-ready; [ "$RC" = 0 ]
}
chk_e && ok "ⓔ 억제 기록 없는 승계 출력 불변" || bad "ⓔ rc=$RC :: $OUT :: $B"
# ⓕ 반례 — 억제분이 아닌 «안 받은 seq» 는 mark 가 그대로 REJECT(env 완화 0)
chk_f() { new_env || return 2; queued; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 2; py_ mark "$O" 99 인계; [ "$RC" = 3 ] && case "$OUT" in *"REJECT 영수 없는 seq 99"*) true;; *) false;; esac; }
chk_f && ok "ⓕ 억제분 아닌 안 받은 seq = mark REJECT 유지" || bad "ⓕ rc=$RC :: $OUT"

# ⓖ DA 재현 — 본문에 «[억제 doorbell]» 이 들어간 일반 쪽지는 억제분이 아니다(표시 유지 = close-check rc0)
chk_g() { new_env || return 2; roster master live; printf '{"seq": 1, "ts": "2026-11-11T00:00:00", "to": "%s", "from": "slack-oppa", "body": "[HIL] q1 · [억제 doorbell] 문구 안내"}\n' "$O" >> "$C/mailbox.jsonl"; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1
  py_ close-check "$O" --no-ready; [ "$RC" = 0 ]; }
chk_g && ok "ⓖ 본문에 «[억제 doorbell]» 이 든 일반 쪽지도 표시(DA 재현)" || bad "ⓖ rc=$RC :: $OUT"

for f in "$SRC/mbox_handover.py" "$SRC/mbox.sh"; do case "$f" in *.sh) bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")";; *) python3 -c 'import sys,py_compile;py_compile.compile(sys.argv[1],doraise=True)' "$f" >/dev/null 2>&1 && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")";; esac; done
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
