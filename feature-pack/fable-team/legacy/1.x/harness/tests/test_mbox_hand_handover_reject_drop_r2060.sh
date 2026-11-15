#!/usr/bin/env bash
# test_mbox_hand_handover_reject_drop_r2060.sh — r2060: 옛 좌석이 후계에게 손으로 쓴 «[인계]» 는 보내기 전에 거절(handover 길 안내 1줄) ·
#   이미 큐에 들어간 손 «[인계]» 1통은 `mbox.sh handover-drop <구> <후계> <seq> --verdict <번호>` 로 묶음에서 뺀다(판정 원장 실재 확인 + 표식 1줄).
#  ① 같은 계보 손 [인계] send·--force·relay = rc3 · 큐 0 · doorbell 0  ② 접두 다른 승계(_replaced_by) · 명부 못 읽음  ③ 기계 handover·기계 꼴 send·일 넘김·[레디] 통과
#  ④ drop 성공 → 기계 handover → ready·close-check 통과 / drop 만 → [인계] 없음  ⑤ drop 거절(기계 통·없는 seq·다른 쌍) · 두 번째 = NOOP
#  ⑥ 판정 번호(--verdict 없음 rc2 · 원장에 없음 rc1 · ref 없음 rc1)  ⑦ 표식 깨짐 = 형식 불명 그대로 + stderr 1줄 · 표식에 기계 seq = 묶음에 그대로
#  변이 M1 send 판정 지움 → ① FAIL · M2 drop 의 items=None 조건 지움 → ⑤ FAIL · M3 `_handovers` 가 표식을 안 읽음 → ④ FAIL (변이마다 원본 대조)
# 격리: 정본 comm 사본 + 가짜 명부 + 임시 우편함 + 임시 git 원장(FT_TEAMS_REF=main · fetch 0) · tmux·ft-hil 스텁 · 실 우편함·명부·표식 0 · sleep 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; BIN="$REPO/harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3]) :: ${OUT:0:300}"; fi; }
has() { case "$OUT" in *"$1"*) echo y;; *) echo n;; esac; }
mkdir -p "$T/stub"
printf '#!/bin/sh\necho "$*" >> "$TMUX_LOG"\ncase "$1" in list-panes) exit 0;; *) exit 1;; esac\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/bin/sh\n[ "$1 $2" = "--pending --each" ] && { echo "h62 3"; exit 0; }\nexit 2\n' > "$T/stub/ft-hil.sh"
O="byz-hrd-planner-arch-pi#14"; N="byz-hrd-planner-arch-pi#15"   # 같은 계보
P="byz-hrd-arch-claude#5"; S="byz-hrd-arch-pi#6"                 # 접두가 다른 승계(P._replaced_by = S)
X="byz-hrd-checker-claude#3"                                      # 다른 계보(일 넘김 받는 이)
V=4176   # 원장에 있는 판정 번호

roster() {   # roster <O 은퇴 0|1> [broken]
  if [ "${2:-}" = broken ]; then printf '{ broken' > "$E/seats/seats-hrd.json"; return; fi
  python3 - "$E/seats/seats-hrd.json" "$1" "$O" "$N" "$P" "$S" "$X" <<'PY'
import json, sys
p, r, o, n, pp, s, x = sys.argv[1], sys.argv[2] == "1", *sys.argv[3:]
d = {"_master": n if r else o, o: {"role": "stop-ready", "_replaced_by": n} if r else {"role": "master"},
     n: {"role": "master"}, pp: {"role": "stop-ready", "_replaced_by": s}, s: {"role": "arch"}, x: {"role": "checker"}}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수] — 격리 우편함 + 임시 git 원장(main)
  E="$(mktemp -d "$T/e.XXXXXX")"; C="$E/.fable-team/comm"; Q="$C/mailbox.jsonl"; L="$C/mailbox.log.jsonl"
  MK="$E/.fable-team/state/handover-drop/$O.json"; export TMUX_LOG="$E/tmux.log"
  mkdir -p "$C" "$E/.fable-team/state" "$E/seats" "$E/design/teams/planner"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; printf '{}\n' > "$E/seats/seats.json"; roster 0; : > "$Q"; : > "$TMUX_LOG"
  printf '| 팀 | 폴더 |\n|---|---|\n| planner | design/teams/planner/ | x | 현역 |\n' > "$E/design/TEAMS.md"
  printf '| %s | 11-15 21:00 | 손 [인계] 빼기 허용 |\n' "$V" > "$E/design/teams/planner/VERDICTS-planner-1.md"
  git -C "$E" init -q -b main; git -C "$E" add design; git -C "$E" -c user.name=t -c user.email=t@t commit -qm base
  [ -z "${1:-}" ] || "$1"
}
xsh() { env -u FT_PLANNER_HEAD_MODE -u FT_MBOX_STATE_DIR -u FT_BIN PATH="$T/stub:$PATH" FT_SEATS_JSON="$E/seats/seats.json" FT_MBOX_DIR="$C" \
  FT_HIL_BIN="$T/stub/ft-hil.sh" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_MBOX_RESEND_COOLDOWN=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" \
  FT_MBOX_PY="$C/mbox.py" FT_BIN="$BIN" FT_TEAMS_REF="${TREF:-main}" bash "$C/mbox.sh" "$@"; }
xpy() { env -u FT_PLANNER_HEAD_MODE -u FT_MBOX_STATE_DIR -u FT_BIN PATH="$T/stub:$PATH" FT_SEATS_JSON="$E/seats/seats.json" FT_MBOX_DIR="$C" \
  FT_HIL_BIN="$T/stub/ft-hil.sh" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_MBOX_RESEND_COOLDOWN=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" \
  FT_MBOX_PY="$C/mbox.py" FT_BIN="$BIN" FT_TEAMS_REF="${TREF:-main}" python3 "$C/mbox.py" "$@"; }
sh_() { OUT="$(cd "$E" && xsh "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$E" && xpy "$@" 2>&1)"; RC=$?; }
row() { printf '{"seq": %s, "ts": "2026-11-15T00:00:00", "to": "%s", "from": "slack-oppa", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
sq() { printf '%s\n' "$OUT" | grep -oE 'QUEUED seq=[0-9]+' | head -1 | cut -d= -f2; }
lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
mkn() { [ -f "$MK" ] && python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["drops"]))' "$MK" || echo 0; }
hand_q() { py send "$2" "$1" "[인계] 인계서 = /tmp/handover-arch14.md · 남은 일 3건"; HS="$(sq)"; }   # 기준판 방식(py send = 판정 전)으로 큐에 넣은 손 [인계]
HAND="[인계] 인계서 = /tmp/handover-arch14.md · 남은 일 3건"

# ① 같은 계보 #14 → #15 손 [인계] = 보내기 전 거절
chk_1() {
  new_env "${1:-}"; local q0 l0; q0="$(lines "$Q")"; l0="$(lines "$L")"
  sh_ send "$N" "$O" "$HAND"
  [ "$RC" = 3 ] && [ "$(lines "$Q")" = "$q0" ] && [ "$(lines "$L")" = "$l0" ] && ! grep -q send-keys "$TMUX_LOG" \
    && [ "$(has "REJECT 손 [인계] 거절 — bash mbox.sh handover $O $N")" = y ]
}
chk_1 && ok "① 같은 계보 손 [인계] send → rc3 · 큐 0 · doorbell 0 · handover 안내" || bad "① 손 [인계] send rc=$RC :: ${OUT:0:300}"
sh_ send "$N" "$O" "$HAND" --force; chk "① --force 로도 rc3" "$RC $(has '손 [인계] 거절')" "3 y"
sh_ send "$N" "$O" "$HAND" --urgent; chk "① --urgent 로도 rc3" "$RC $(has '손 [인계] 거절')" "3 y"
printf 'long body\n' > "$T/relay.txt"; sh_ relay "$N" "$O" "$T/relay.txt" "[인계] 인계서 요약 · 전문 경로"
chk "① relay 요약 머리 [인계] 같은 쌍 → rc3 · 큐 0" "$RC $(has '손 [인계] 거절') $(lines "$Q")" "3 y 0"
sh_ send "$N" "$O" "
  [인계] 앞에 빈 줄"; chk "① 첫 비어 있지 않은 줄 머리 [인계] → rc3" "$RC" "3"

# ② 접두가 다른 승계 · 명부 못 읽음
new_env; sh_ send "$S" "$P" "[인계] 인계서 = x"; chk "② 접두 다른 승계(_replaced_by) 손 [인계] → rc3" "$RC $(has '손 [인계] 거절')" "3 y"
roster 0 broken; sh_ send "$N" "$O" "$HAND"; chk "② 명부 못 읽음 + 같은 계보 → rc3" "$RC $(has '손 [인계] 거절')" "3 y"
sh_ send "$S" "$P" "[인계] 인계서 = x"   # «지금과 같음» = 기준판도 이 명부면 가드가 «명부 읽기 실패» rc3(손 판정 줄 0)
chk "② 명부 못 읽음 + 접두 다른 쌍 → 지금과 같음(가드 판정 · 손 판정 0)" "$RC $(has '손 [인계]') $(has '명부 읽기 실패')" "3 n y"

# ③ 통과하는 것(불변)
new_env; row 1 "$O" "[HIL] q"; sh_ recv "$O"; sh_ handover "$O" "$N"
B="$(python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]["body"])' "$L")"
WANT="[인계] $O -> $N · 항목 2 · [레디] 는 항목마다 «<id> 받음»(bash mbox.sh ready $N $O)
수: 답 안 한 오빠 질문 1 · 남은 회신·쪽지 0 · 억제 doorbell 0 · 실행 중 h 1 · 백그라운드 0
전문: mailbox.log.jsonl seq 로 · 오빠 질문 먼저 = #1
항목: #1 h62"
chk "③ 기계 handover → QUEUED · 인계 표시 · 본문 바이트 그대로" "$RC $(has QUEUED) $(has "MARKED $O 인계 1") $([ "$B" = "$WANT" ] && echo same)" "0 y y same"
sh_ send "$N" "$O" "[인계] $O -> $N · 항목 2 · 손 아님
항목: #7 h3"; chk "③ 기계 꼴 본문(항목 2 + id 2개) send 직접 → QUEUED" "$RC $(has QUEUED)" "0 y"
sh_ send "$X" "$O" "[인계] 일 넘김 — 시험 3건 맡김"; chk "③ 다른 계보 앞 손 [인계](일 넘김) → QUEUED" "$RC $(has QUEUED)" "0 y"
sh_ send "$O" "$N" "[레디] 손으로 씀"; chk "③ [레디] send → QUEUED" "$RC $(has QUEUED)" "0 y"
sh_ send "$N" "$O" "[완료] 인계 끝"; chk "③ 그 밖 머리 → QUEUED" "$RC $(has QUEUED)" "0 y"

# ④ drop 성공 → 기계 handover → ready·close-check 통과
chk_4() {
  new_env "${1:-}"; row 1 "$O" "[HIL] q"; sh_ recv "$O"; hand_q "$O" "$N"; [ -n "$HS" ] || return 1
  sh_ handover-drop "$O" "$N" "$HS" --verdict "$V"; [ "$RC" = 0 ] && [ "$(has "DROPPED $O -> $N #$HS verdict=$V")" = y ] && [ "$(mkn)" = 1 ] || return 1
  sh_ handover "$O" "$N"; local H2; H2="$(sq)"; roster 1; sh_ recv "$N"
  sh_ ready "$N" "$O"; [ "$RC" = 0 ] && [ "$(has QUEUED)" = y ] || return 1
  local R; R="$(python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]["body"])' "$L")"
  case "$R" in "[레디] $N <- $O · [인계] #$H2 받음 · 항목 2"*) ;; *) return 1;; esac
  py close-check "$O"; [ "$RC" = 0 ] && [ "$(has CLOSE-OK)" = y ] && [ "$(has '형식 불명')" = n ]
}
chk_4 && ok "④ 손 [인계] drop → 기계 handover → ready QUEUED(기계 통 항목만) · close-check CLOSE-OK" || bad "④ drop 뒤 ready·close rc=$RC :: ${OUT:0:300}"
new_env; hand_q "$O" "$N"; sh_ handover-drop "$O" "$N" "$HS" --verdict "$V"; roster 1; sh_ recv "$N"; sh_ ready "$N" "$O"
chk "④ 기계 통 없이 drop 만 → ready REJECT «[인계] 없음»" "$RC $(has '[인계] 없음')" "3 y"

# ⑤ drop 거절
chk_5() {
  new_env "${1:-}"; row 1 "$O" "[HIL] q"; sh_ recv "$O"; sh_ handover "$O" "$N"; local H2; H2="$(sq)"
  sh_ handover-drop "$O" "$N" "$H2" --verdict "$V"; [ "$RC" = 3 ] && [ "$(has '기계 [인계] 는 뺄 수 없음')" = y ] && [ ! -e "$MK" ]
}
chk_5 && ok "⑤ 기계 [인계] seq drop → rc3 · 표식 0" || bad "⑤ 기계 통 drop rc=$RC :: ${OUT:0:300}"
sh_ handover-drop "$O" "$N" 99999 --verdict "$V"; chk "⑤ 없는 seq → rc3 · 표식 0" "$RC $([ -e "$MK" ] && echo mk || echo none)" "3 none"
hand_q "$O" "$X"; sh_ handover-drop "$O" "$N" "$HS" --verdict "$V"; chk "⑤ from·to 다른 쌍의 seq → rc3 · 표식 0" "$RC $([ -e "$MK" ] && echo mk || echo none)" "3 none"
hand_q "$O" "$N"; sh_ handover-drop "$O" "$N" "$HS" --verdict "$V"; chk "⑤ 손 통 drop 1회 → DROPPED · 표식 1줄" "$RC $(has DROPPED) $(mkn)" "0 y 1"
sh_ handover-drop "$O" "$N" "$HS" --verdict "$V"; chk "⑤ 같은 seq 두 번째 → NOOP rc0 · 표식 1줄 그대로" "$RC $(has NOOP) $(mkn)" "0 y 1"

# ⑥ 판정 번호
new_env; hand_q "$O" "$N"
sh_ handover-drop "$O" "$N" "$HS"; chk "⑥ --verdict 없음 → rc2" "$RC" "2"
sh_ handover-drop "$O" "$N" "$HS" --verdict 41x; chk "⑥ --verdict 숫자 아님 → rc2" "$RC" "2"
sh_ handover-drop "$O" "$N" "$HS" --verdict 417; chk "⑥ 원장에 없는 번호(경계 417 ≠ 4176) → rc1 · 표식 0" "$RC $(mkn)" "1 0"
TREF=no-such-ref sh_ handover-drop "$O" "$N" "$HS" --verdict "$V"; chk "⑥ FT_TEAMS_REF 없는 ref → rc1 · 표식 0" "$RC $(mkn)" "1 0"

# ⑦ 표식 깨짐 · 표식에 기계 seq
new_env; hand_q "$O" "$N"; roster 1; sh_ recv "$N"; mkdir -p "$(dirname "$MK")"; printf '{ broken' > "$MK"; sh_ ready "$N" "$O"
chk "⑦ 깨진 표식 → ready REJECT 형식 불명 그대로 · «판정 불가 handover-drop 표식» 1줄" "$RC $(has '형식 불명') $(printf '%s\n' "$OUT" | grep -c '판정 불가 handover-drop 표식')" "3 y 1"
new_env; row 1 "$O" "[HIL] q"; sh_ recv "$O"; hand_q "$O" "$N"; sh_ handover "$O" "$N"; mkdir -p "$(dirname "$MK")"   # DA R1 — verdict·at 없는 표식 = 꼴 틀림
printf '{"drops": [{"seq": %s, "to": "%s"}]}\n' "$HS" "$N" > "$MK"; roster 1; sh_ recv "$N"; sh_ ready "$N" "$O"
chk "⑦ verdict·at 없는 표식 → ready REJECT 형식 불명 · «판정 불가 handover-drop 표식» 1줄" "$RC $(has '형식 불명') $(printf '%s\n' "$OUT" | grep -c '판정 불가 handover-drop 표식')" "3 y 1"
py close-check "$O"; chk "⑦ verdict·at 없는 표식 → close-check CLOSE-OK 아님" "$RC $(has CLOSE-OK)" "3 n"
new_env; row 1 "$O" "[HIL] q"; sh_ recv "$O"; sh_ handover "$O" "$N"; H2="$(sq)"; mkdir -p "$(dirname "$MK")"
printf '{"drops": [{"seq": %s, "to": "%s", "verdict": %s, "at": 1}]}\n' "$H2" "$N" "$V" > "$MK"; roster 1; sh_ recv "$N"; sh_ ready "$N" "$O"
chk "⑦ 표식에 기계 [인계] seq → 묶음에 그대로(ready 가 그 통 «받음»)" "$RC $(has QUEUED)" "0 y"
R="$(python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]["body"])' "$L")"
case "$R" in "[레디] $N <- $O · [인계] #$H2 받음 · 항목 2"*) ok "⑦ [레디] 머리 = 기계 통 #$H2 항목 2";; *) bad "⑦ [레디] 머리 :: ${R:0:200}";; esac

# 변이(사본에서만) — 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조)
m1() { sed -i.bak '/r2060 A1/d' "$C/mbox.sh"; ! grep -q 'r2060 A1' "$C/mbox.sh"; }
m2() { sed -i.bak 's/H.items(r) is not None/False/' "$C/mbox_handover_hand.py"; grep -q 'False:' "$C/mbox_handover_hand.py"; }
m3() { printf '\ndef _handovers(old, new):\n    skip = _successor_open_seq(old)\n    return [r for r in _sent() if r.get("from") == old and r.get("to") == new and _head(r.get("body")) == "[인계]" and r.get("seq") != skip]\n' >> "$C/mbox_handover.py"; }
if [ -f "$SRC/mbox_handover_hand.py" ]; then
  chk_1 m1 && bad "M1 send 판정 지움이 ① 에 안 잡힘" || ok "M1 send 판정 지움 → ① FAIL"; chk_1 && ok "M1 원본 대조 → ① PASS" || bad "M1 원본 대조 :: ${OUT:0:200}"
  chk_5 m2 && bad "M2 drop items=None 조건 지움이 ⑤ 에 안 잡힘" || ok "M2 drop items=None 조건 지움 → ⑤ FAIL"; chk_5 && ok "M2 원본 대조 → ⑤ PASS" || bad "M2 원본 대조 :: ${OUT:0:200}"
  chk_4 m3 && bad "M3 _handovers 표식 안 읽음이 ④ 에 안 잡힘" || ok "M3 _handovers 표식 안 읽음 → ④ FAIL"; chk_4 && ok "M3 원본 대조 → ④ PASS" || bad "M3 원본 대조 :: ${OUT:0:200}"
else bad "변이 M1~M3 — mbox_handover_hand.py 없음(기준판)"; fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
