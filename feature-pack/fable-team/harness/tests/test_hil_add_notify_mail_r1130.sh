#!/usr/bin/env bash
# test_hil_add_notify_mail_r1130.sh — r1130: ft-hil.sh --add --notify <좌석> 등록 직후 그 좌석 쪽지함에 «[HIL] h<N> 발급» 1통 (카드 반례 R1~R6 · 변이 2)
# 격리: 임시 HIL_DIR · 팩 harness/comm 실 mbox 사본(쪽지함 파일 실물 · 속도 가드 실물) · 실패 칸 = rc1 가짜 mbox.sh · tmux = PATH 앞 가짜(기록만)
#   실 /tmp/h* · 실 쪽지함 · 실 desk·Slack 0 · 자기 재호출 0(변이는 bin 사본을 같은 함수로 돌린다) · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }

MB="$T/mb/.fable-team/comm"; BADC="$T/badcomm"; ELSE="$T/elsewhere"; FBIN="$T/fakebin"
mkdir -p "$(dirname "$MB")" "$BADC" "$ELSE" "$FBIN" "$T/home"
cp -R "$HERE/../comm" "$MB"                                   # 실 mbox 사본 — 쪽지함 파일 실물로 센다
printf '#!/bin/bash\nexit 1\n' > "$BADC/mbox.sh"              # R3: 쪽지함 send 실패 대역
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/tmux.log"\nexit 1\n' "$T" > "$FBIN/tmux"; chmod +x "$FBIN/tmux"
DESK='byz-planner-desk-claude#81'
# desk 경로 판정기(ft_desk_route_gate.py)는 실물 · 명부 = planner _master·_desk — 실환경처럼 «desk 에는 planner 만» 규칙 아래서 도구 발신자가 통과하는지 본다
printf '{"_master": "byz-planner-master-claude#170", "_desk": "%s"}\n' "$DESK" > "$T/mb/.fable-team/seats-planner.json"
# FT_MBOX_DIR 는 일부러 다른 폴더 — 쪽지가 --notify-comm 쪽지함으로 가는지(부른 곳 env 로 새지 않는지) 본다
hil() { local b="$1" d="$2"; shift 2; env -i HOME="$T/home" PATH="$FBIN:/usr/bin:/bin" HIL_DIR="$d" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$ELSE" FT_DESK_GATE="$BIN/ft_desk_route_gate.py" bash "$b/ft-hil.sh" "$@"; }
nwarn() { grep -c '쪽지 실패' "$1" 2>/dev/null; }   # 요청 좌석 표식·판정기 WARN 은 이 카드 밖 — 쪽지 실패 줄만 센다
rows() { python3 -c 'import sys
try: print(sum(1 for l in open(sys.argv[1], encoding="utf-8") if l.strip()))
except FileNotFoundError: print(0)' "$1"; }
msgs() { python3 -c 'import json,sys
try: [print("%s|%s|%s" % (r.get("to",""), r.get("from",""), r.get("body",""))) for r in map(json.loads, filter(str.strip, open(sys.argv[1], encoding="utf-8")))]
except FileNotFoundError: pass' "$1"; }
clr() { rm -f "$MB/mailbox.jsonl" "$MB/mailbox.log.jsonl"; }
plan() { printf '#!/usr/bin/env bash\necho "ran-%s"\n' "$1" > "$T/$1.sh.hil"; }
plan P1; plan P2; plan P3; plan P4; plan P5; for i in 1 2 3 4; do plan "Q$i"; done

r1() {  # $1=bin $2=HIL_DIR — R1 --notify → 1통 · stdout 1줄 · rc0 (판정 줄을 stdout 으로 · 실패면 rc1)
  local out rc m; clr; out="$(hil "$1" "$2" --add "$T/P1.sh.hil" --notify "$DESK" --notify-comm "$MB" 2>"$T/r1.err")"; rc=$?
  m="$(msgs "$MB/mailbox.jsonl")"
  [ "$rc" = 0 ] && [ "$out" = "! bash $2/h1" ] && [ "$(rows "$MB/mailbox.jsonl")" = 1 ] \
    && [ "$m" = "$DESK|ft-hil-h1|[HIL] h1 발급 — 실행 줄 = ! bash $2/h1 (자율 ON = desk 가 PR head 확인 뒤 실행 · OFF = 오빠께) · 계획 $T/P1.sh.hil" ] \
    && [[ "$m" != *"오빠가 칠 줄"* ]] \
    || { echo "rc=$rc out=$out rows=$(rows "$MB/mailbox.jsonl") msg=$m err=$(cat "$T/r1.err")"; return 1; }
}
r3() {  # $1=bin $2=HIL_DIR — R3 쪽지함 send 실패 → 등록·표식 그대로 · WARN 1줄 · rc0
  local out rc; out="$(hil "$1" "$2" --add "$T/P3.sh.hil" --notify "$DESK" --notify-comm "$BADC" 2>"$T/r3.err")"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = "! bash $2/h1" ] && [ -f "$2/h1" ] && [ "$(sed -n 's/^comm=//p' "$2/h1.notify" 2>/dev/null)" = "$BADC" ] \
    && [ "$(nwarn "$T/r3.err")" = 1 ] && grep -qF "WARN [HIL] 쪽지 실패 — h1 은 등록됨 · 틱 30분 알림이 남는다(to=$DESK comm=$BADC)" "$T/r3.err" \
    || { echo "rc=$rc out=$out h1=$([ -f "$2/h1" ] && echo O || echo X) notify=$(cat "$2/h1.notify" 2>&1) err=$(cat "$T/r3.err")"; return 1; }
}

echo "== ⓐ R1 --add --notify <좌석> → 그 쪽지함 1통(발신자 ft-hil-h1 · 실행 줄 · 계획 경로) · stdout 1줄 · rc0"
o="$(r1 "$BIN" "$T/h-a")" && ok "R1 1통 · 본문·발신자·stdout·rc0" || bad "R1 — $o"
[ "$(rows "$ELSE/mailbox.jsonl")" = 0 ] && ok "  └ 부른 곳 FT_MBOX_DIR 쪽지함 0행(새지 않음)" || bad "FT_MBOX_DIR 로 샜다: $(msgs "$ELSE/mailbox.jsonl")"
[ "$(sed -n 's/^seat=//p' "$T/h-a/h1.notify")" = "$DESK" ] && ok "  └ .notify 표식 그대로(틱 30분 그물)" || bad "표식: $(cat "$T/h-a/h1.notify" 2>&1)"

echo "== ⓑ R2 --notify 없음 → 쪽지 0 · stdout 그대로 · 표식 0"
clr; out="$(hil "$BIN" "$T/h-b" --add "$T/P2.sh.hil" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "! bash $T/h-b/h1" ] && ok "R2 stdout 1줄 · rc0" || bad "R2 rc=$rc out=$out"
[ "$(rows "$MB/mailbox.jsonl")" = 0 ] && [ "$(rows "$ELSE/mailbox.jsonl")" = 0 ] && [ ! -e "$T/h-b/h1.notify" ] && ok "  └ 쪽지 0 · 표식 0" || bad "쪽지·표식이 생겼다"

echo "== ⓒ R3 쪽지함 send 실패 → h 등록·.notify 그대로 · stderr WARN 1줄 · rc0"
o="$(r3 "$BIN" "$T/h-c")" && ok "R3 등록·표식·WARN 1줄·rc0" || bad "R3 — $o"

echo "== ⓓ R4 --supersedes h1 --notify → 새 h2 로 1통 · 옛 h1 은 0"
hil "$BIN" "$T/h-d" --add "$T/P4.sh.hil" >/dev/null 2>&1; clr
out="$(hil "$BIN" "$T/h-d" --add "$T/P5.sh.hil" --supersedes h1 --notify "$DESK" --notify-comm "$MB" 2>/dev/null)"
[ "$out" = "! bash $T/h-d/h2" ] && [ "$(cat "$T/h-d/h1.superseded" 2>/dev/null)" = h2 ] && ok "R4 새 장 h2 · 대체 표시" || bad "R4 out=$out"
[ "$(rows "$MB/mailbox.jsonl")" = 1 ] && has "$(msgs "$MB/mailbox.jsonl")" "$DESK|ft-hil-h2|[HIL] h2 발급" "  └ h2 로 1통(h1 0)" || bad "R4 쪽지: $(msgs "$MB/mailbox.jsonl")"

echo "== ⓔ R5 같은 계획 두 번 --add --notify → 같은 h1 재사용 · 쪽지 1통뿐"
clr; a="$(hil "$BIN" "$T/h-e" --add "$T/P1.sh.hil" --notify "$DESK" --notify-comm "$MB" 2>/dev/null)"
b="$(hil "$BIN" "$T/h-e" --add "$T/P1.sh.hil" --notify "$DESK" --notify-comm "$MB" 2>/dev/null)"
[ "$a" = "! bash $T/h-e/h1" ] && [ "$b" = "$a" ] && ok "R5 두 번째도 h1" || bad "R5 a=$a b=$b"
[ "$(rows "$MB/mailbox.jsonl")" = 1 ] && ok "  └ 쪽지 1통" || bad "R5 쪽지 $(rows "$MB/mailbox.jsonl")통: $(msgs "$MB/mailbox.jsonl")"

echo "== ⓕ R6 연달아 4장(h230~h233 꼴) → 4통 모두 도착(도구 발신자 = 실 속도 가드 면제)"
clr; for i in 1 2 3 4; do hil "$BIN" "$T/h-f" --add "$T/Q$i.sh.hil" --notify "$DESK" --notify-comm "$MB" >/dev/null 2>>"$T/r6.err"; done
[ "$(rows "$MB/mailbox.jsonl")" = 4 ] && ok "R6 4통" || bad "R6 $(rows "$MB/mailbox.jsonl")통 · err=$(cat "$T/r6.err")"
for i in 1 2 3 4; do has "$(msgs "$MB/mailbox.jsonl")" "$DESK|ft-hil-h$i|[HIL] h$i 발급" "  └ h$i"; done
[ "$(nwarn "$T/r6.err")" = 0 ] && ok "  └ 쪽지 실패 WARN 0" || bad "R6 stderr: $(cat "$T/r6.err")"
[ "$(cat "$T/tmux.log" 2>/dev/null | grep -c 'send-keys')" = 0 ] && ok "도어벨 = 가짜 tmux 기록만 · send-keys 0" || bad "send-keys 가 나갔다"

echo "== ⓖ 줄 상한 · bin·kit 같은 내용"
[ "$(wc -l < "$BIN/ft-hil.sh")" -le 200 ] && ok "ft-hil.sh ≤200줄($(wc -l < "$BIN/ft-hil.sh" | tr -d ' '))" || bad "ft-hil.sh 줄 초과"
K="$HERE/../kit/fable-team/bin"
for f in ft-hil.sh ft-hil-notify.sh; do cmp -s "$BIN/$f" "$K/$f" && ok "cmp0 $f" || bad "키트 사본 다름: $f"; done

echo "== 변이 1: 등록 뒤 송신 줄 삭제 → R1 0통 = FAIL(검출)"
M1="$T/mut1"; cp -R "$BIN" "$M1"; grep -v 'ft-hil-notify.sh" issue' "$BIN/ft-hil.sh" > "$M1/ft-hil.sh"
! cmp -s "$BIN/ft-hil.sh" "$M1/ft-hil.sh" && ok "변이 1 사본 ≠ 원본" || bad "변이 1 사본 = 원본"
o="$(r1 "$M1" "$T/h-m1")" && bad "변이 1 이 R1 을 못 깬다" || ok "변이 1: R1 FAIL — $o"

echo "== 변이 2: 실패 때 WARN 대신 die → R3 rc≠0 = FAIL(검출)"
M2="$T/mut2"; cp -R "$BIN" "$M2"; sed 's/|| echo "WARN \[HIL\] 쪽지 실패/|| die "WARN [HIL] 쪽지 실패/' "$BIN/ft-hil.sh" > "$M2/ft-hil.sh"
! cmp -s "$BIN/ft-hil.sh" "$M2/ft-hil.sh" && ok "변이 2 사본 ≠ 원본" || bad "변이 2 사본 = 원본"
o="$(r3 "$M2" "$T/h-m2")" && bad "변이 2 가 R3 을 못 깬다" || ok "변이 2: R3 FAIL — $o"

echo "== 변이 3 (r1142): 옛 문구 «오빠가 칠 줄» 되돌림 → R1 FAIL(검출)"
M3="$T/mut3"; cp -R "$BIN" "$M3"; sed 's/실행 줄 = ! bash \$1 (자율 ON = desk 가 PR head 확인 뒤 실행 · OFF = 오빠께)/오빠가 칠 줄 = ! bash $1/' "$BIN/ft-hil-notify.sh" > "$M3/ft-hil-notify.sh"
! cmp -s "$BIN/ft-hil-notify.sh" "$M3/ft-hil-notify.sh" && ok "변이 3 사본 ≠ 원본" || bad "변이 3 사본 = 원본"
o="$(r1 "$M3" "$T/h-m3")" && bad "변이 3 이 R1 을 못 깬다" || ok "변이 3: R1 FAIL — $o"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
