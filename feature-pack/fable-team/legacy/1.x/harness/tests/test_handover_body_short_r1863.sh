#!/usr/bin/env bash
# test_handover_body_short_r1863.sh — r1863: 승계 [인계] 본문 = «머리 3줄 + 항목 id 묶음 1줄»(전문 = mailbox.log) · 개설 본문 지침 줄 중복 0.
#  ① 항목 96(오빠 질문 34) → 본문 ≤4줄 · ≤2000자  ② 후계 ready «받음» 96줄 · 옛 close 통과  ③ 옛 꼴+새 꼴 묶음 합집합 · ready 전 재인계 = 억제 «!» 유지
#  ④ 억제 doorbell 2건만 표시 제외  ⑤ 머리 N ≠ id 수 = None · 안내 줄 질문 id 는 안 센다  ⑥ 개설 본문 «목적 0»·«승계 이월 0» 각 1번 · 첫 3줄 보존
#  변이 M1 items 새 꼴 못 읽음 → ② FAIL · M2 억제 «!» 빼기 → ④ FAIL · M3 개설 줄 빼기 제거 → ⑥ FAIL · 격리: 정본 사본 + 가짜 명부 + 임시 우편함 · sleep 0
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; SO="$REPO/harness/bin/ft-successor-open.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/bin/sh\nexit 0\n' > "$T/stub/ft-hil.sh"
O=byz-short-old-pi#1; N=byz-short-new-pi#2

roster() {   # roster live|retired
  python3 - "$ENVROOT/seats/seats-short.json" "$1" "$O" "$N" <<'PY'
import json, sys
p, mode, o, n = sys.argv[1:5]; live = mode == "live"
json.dump({"_master": o if live else n, o: {"role": "master"} if live else {"role": "stop-ready", "_replaced_by": n}, n: {"role": "master"}}, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수]
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; SD="$ENVROOT/.fable-team/state"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$SD/doorbell-held" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; printf '{}\n' > "$ENVROOT/seats/seats.json"; roster live; : > "$Q"
  [ -z "${1:-}" ] || "$1"
}
row() { printf '{"seq": %s, "ts": "2026-11-13T00:00:00", "to": "%s", "from": "%s", "body": "%s"}\n' "$1" "$O" "$2" "$3" >> "$Q"; }
held() { printf 'held ts=1790000000 reason=held window=1 seat=%s\nseq=901\nseq=902\n' "$O" > "$SD/doorbell-held/$O"; row 901 slack-oppa "[HIL] h1"; row 902 slack-oppa "[HIL] h2"; }
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats-short.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$SD"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" FT_HIL_BIN="$T/stub/ft-hil.sh"
  "$@" ); }
sh_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
lastbody() { python3 -c 'import json,sys;print([json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()][-1]["body"])' "$C/mailbox.log.jsonl" 2>/dev/null; }
items_of() { (cd "$ENVROOT" && xenv python3 -c 'import sys;sys.path.insert(0,sys.argv[1]);import mbox;import mbox_handover as m;print(m.items({"body":sys.argv[2]}))' "$C" "$1" 2>&1); }
mut_m1() { printf '\ndef items(h):\n    b = h.get("body", ""); m, ids = HEAD_N.match(b), re.findall(r"^- (#\\d+|h\\d+|bg:[\\w.-]+) ", b, re.M)\n    return ids if m and int(m.group(1)) == len(ids) else None\n' >> "$C/mbox_handover.py"; }
mut_m2() { python3 - "$C/mbox_handover.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p, encoding="utf-8").read(); assert '"#%s!" % s' in s; open(p, "w", encoding="utf-8").write(s.replace('"#%s!" % s', '"#%s" % s'))
PY
}

# ① 항목 96(오빠 질문 34 · 100자 넘는 본문) → [인계] 본문 ≤4줄 · ≤2000자 (기준판 = 줄마다 100자 요약)
setup1() {
  local pad; pad="$(printf '긴본문%.0s' $(seq 1 40))"
  for i in $(seq 1 96); do if [ "$i" -le 34 ]; then row "$i" slack-oppa "[HIL] 질문 $i $pad"; else row "$i" byz-x-pi#1 "[회신] 쪽지 $i $pad"; fi; done
  sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1; B="$(lastbody)"
}
chk_1() {
  new_env || return 2; setup1 || return 1
  [ "$(printf '%s\n' "$B" | wc -l | tr -d ' ')" -le 4 ] && [ "$(python3 -c 'import sys;print(len(sys.argv[1]))' "$B")" -le 2000 ] || return 1
  case "$(printf '%s\n' "$B" | sed -n 1p)" in "[인계] $O -> $N · 항목 96 "*) ;; *) return 1;; esac
  [ "$(printf '%s\n' "$B" | sed -n 's/^항목://p' | wc -w | tr -d ' ')" = 96 ] && [ "$(printf '%s\n' "$B" | sed -n 's/^전문: .*= //p' | wc -w | tr -d ' ')" = 34 ] || return 1
  py_ close-check "$O" --no-ready; [ "$RC" = 0 ]
}
chk_1 && ok "① 항목 96(질문 34) → 본문 ≤4줄 · ≤2000자 · 96건 인계 표시" || bad "① rc=$RC :: $(printf '%s' "$B" | head -c 300)"

# ② 후계 ready → «<id> 받음» 96줄 · 옛 세션 close 통과
chk_2() {
  new_env "${1:-}" || return 2; setup1 || return 2; roster retired
  sh_ recv "$N"; sh_ ready "$N" "$O"; [ "$RC" = 0 ] || return 1
  [ "$(lastbody | grep -c ' 받음$')" = 96 ] || return 1; py_ close-check "$O"; [ "$RC" = 0 ]
}
chk_2 mut_m1 && bad "M1 변이(items 새 꼴 못 읽음)가 ② 에 안 잡힘" || ok "M1 변이 → ② FAIL 확인"
chk_2 && ok "② 후계 ready «받음» 96줄 · 옛 close-check CLOSE-OK" || bad "② rc=$RC :: $OUT"

# ③ 옛 꼴 [인계](앞 통) + 새 꼴(뒤 통) · ready 전 한 번 더 handover = 재적재 id 그대로 · 억제 «!» 유지 · 합집합 ready · close 통과
chk_3() {
  new_env || return 2; row 500 slack-oppa "[HIL] q5"; sh_ recv "$O"
  sh_ send "$N" "$O" "[인계] $O -> $N · 항목 1 · 옛 꼴"$'\n'"- #500 [slack-oppa] q5 (전문: mailbox.log.jsonl seq 500)"; [ "$RC" = 0 ] || return 1
  roster retired; held; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1
  sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1; B="$(lastbody)"
  [ "$(printf '%s\n' "$B" | sed -n 's/^항목: *//p')" = "#500 #901! #902!" ] || return 1
  sh_ recv "$N"; sh_ ready "$N" "$O"; [ "$RC" = 0 ] || return 1; R="$(lastbody)"
  case "$R" in *"· 항목 3"*) ;; *) return 1;; esac; for i in '#500 받음' '#901 받음' '#902 받음'; do case "$R" in *"$i"*) ;; *) return 1;; esac; done
  py_ close-check "$O"; [ "$RC" = 0 ]
}
chk_3 && ok "③ 옛 꼴+새 꼴 합집합 · ready 전 재인계 = #500 #901! #902! · ready 항목 3 · close 통과" || bad "③ rc=$RC :: $OUT :: $B"

# ④ 억제 doorbell 2건 → 그 둘만 표시 제외 · 일반 쪽지는 표시
chk_4() {
  new_env "${1:-}" || return 2; row 700 slack-oppa "[HIL] q7"; sh_ recv "$O"; roster retired; held
  sh_ handover "$O" "$N"; [ "$RC" = 0 ] || return 1
  case "$OUT" in *"MARKED $O 인계 700"*) ;; *) return 1;; esac
  [ "$(lastbody | sed -n 's/^항목: *//p')" = "#700 #901! #902!" ] || return 1
  [ "$(lastbody | sed -n 2p)" = "수: 답 안 한 오빠 질문 1 · 남은 회신·쪽지 0 · 억제 doorbell 2 · 실행 중 h 0 · 백그라운드 0" ]
}
chk_4 mut_m2 && bad "M2 변이(억제 «!» 빼기)가 ④ 에 안 잡힘" || ok "M2 변이 → ④ FAIL 확인"
chk_4 && ok "④ 억제 2건만 표시 제외 · #700 인계 표시" || bad "④ rc=$RC :: $OUT"

# ⑤ 머리 N ≠ id 수 → None · 안내 줄(«오빠 질문 먼저 = #1») id 는 두 번 세지 않는다
chk_5() {
  new_env || return 2; local h="[인계] $O -> $N · 항목 %s · [레디] 는 …"$'\n'"수: 답 안 한 오빠 질문 1"$'\n'"전문: mailbox.log.jsonl seq 로 · 오빠 질문 먼저 = #1"$'\n'"항목: #1 #2!"
  [ "$(items_of "$(printf "$h" 3)")" = None ] && [ "$(items_of "$(printf "$h" 2)")" = "['#1', '#2']" ]
}
chk_5 && ok "⑤ 머리 N ≠ id 수 = None · 질문 안내 줄 id 안 셈 · «!» 는 #seq 로" || bad "⑤ $(items_of x)"

# ⑥ 개설 본문 — 4행~ 의 지침 머리 5개 줄만 빼고(첫 3줄·문장 속 같은 낱말 보존) 도구 줄이 정본
chk_6() {   # chk_6 [변이 = m3]
  local so="$T/so.sh"; cp "$SO" "$so"
  [ "${1:-}" = m3 ] && python3 - "$so" <<'PY'
import re, sys; p = sys.argv[1]; s = open(p, encoding="utf-8").read(); t = re.sub(r"4,\$\{/\^\(.*?\)/d;p;\}", "4,${p;}", s); assert t != s; open(p, "w", encoding="utf-8").write(t)
PY
  printf '골 1\n배정표 골줄\n골 3\n목적 0 = 손\n크론 0 손\n배정표 손\n좌석 기억(1회 로드)= 손\n승계 이월 0: 손\n문장 속 목적 0 = 낱말\n끝\n' > "$T/body"
  S="$(BODY="$T/body" BLOCK=$'목적 0 = 정본\n크론 0 정본\n배정표 정본' LESSONS_LINE='좌석 기억(1회 로드)= 정본' NAME=byz-t-harness-master-pi#2 CARRY=0 \
    bash -c "$(awk '/^SEND_TEXT="\$\( \{ sed/{f=1} f{print} f&&/^fi$/{exit}' "$so")"'; printf "%s" "$SEND_TEXT"')"
  [ "$(printf '%s\n' "$S" | sed -n 1,3p)" = $'골 1\n배정표 골줄\n골 3' ] && [ "$(printf '%s\n' "$S" | grep -c '^목적 0 =')" = 1 ] && [ "$(printf '%s\n' "$S" | grep -c '^승계 이월 0')" = 1 ] \
    && [ "$(printf '%s\n' "$S" | grep -c '^크론 0\|^좌석 기억')" = 2 ] && [ "$(printf '%s\n' "$S" | grep -c '손$')" = 0 ] && printf '%s\n' "$S" | grep -qx '문장 속 목적 0 = 낱말' && printf '%s\n' "$S" | grep -qx '끝'
}
chk_6 m3 && bad "M3 변이(개설 줄 빼기 제거)가 ⑥ 에 안 잡힘" || ok "M3 변이 → ⑥ FAIL 확인"
chk_6 && ok "⑥ 개설 본문 «목적 0»·«승계 이월 0» 각 1번 · 첫 3줄·문장 보존" || bad "⑥ :: $S"

cmp -s "$SO" "$REPO/harness/kit/fable-team/bin/ft-successor-open.sh" && ok "bin=kit ft-successor-open.sh" || bad "bin≠kit ft-successor-open.sh"
bash -n "$SRC/mbox.sh" && bash -n "$SO" && python3 -c 'import sys;compile(open(sys.argv[1],encoding="utf-8").read(),sys.argv[1],"exec")' "$SRC/mbox_handover.py" && ok "구문 검사" || bad "구문 검사"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
