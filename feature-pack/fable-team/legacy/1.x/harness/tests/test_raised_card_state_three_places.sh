#!/usr/bin/env bash
# test_raised_card_state_three_places.sh — r518: ft_raised.py card_state 가 카드 상태를 «데이터 루트(LIVE_ROOT) · 공용 루트 · ref origin/main» 세 자리에서 보고 가장 앞선 상태(완성 > 진행 > 대기)를 쓴다.
#   ⓐ 카드가 데이터 루트 진행/ 에만 → 출력 0(고치기 전 = «(카드 없음)» 오탐)  ⓑ 데이터 루트 진행/ + origin/main 완성/ → «(카드 완성)» 1줄
#   ⓒ 세 자리 모두 없음 → «(카드 없음)» 1줄  ⓓ LIVE_ROOT 파일 없음 → 공용 루트·ref 만 보고 판정 + «못 본 자리» 표기(조용한 통과 0)
#   ⓔ ref 못 읽음(origin 없음 · 리포 아님) → rc2 + 사유 · 목록 0   ⓕ 틱 raised_watch 실경로: 데이터 루트 진행/ 카드 → 쪽지 0 · ERROR 0
# 격리: 임시 공용 루트 C(체크아웃에 카드 폴더 없음) + C/.fable-team/LIVE_ROOT = 임시 데이터 루트 D + 임시 bare origin O — 외부 호출 0 · GIT_* env 0 · 실 명부·mbox 0.
# 변이·전후 비교는 R518_BIN=<다른 bin 폴더> 로 같은 시험을 돌린다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R518_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}» ← ${1:0:300}";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
G() { git -c user.email=t@t -c user.name=t "$@"; }

if [ -z "${R518_BIN:-}" ]; then for f in ft_raised.py ft_team_lib.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done; fi
RAISED="$BIN/ft_raised.py"
python3 -m py_compile "$RAISED" && ok "py_compile ft_raised.py" || bad "py_compile ft_raised.py"

CARD="design/teams/v65/indices/진행/m5-x.md"; DONE="${CARD/\/진행\//\/완성\/}"; WAIT="${CARD/\/진행\//\/대기\/}"
O="$T/origin.git"; C="$T/common"; D="$T/data"; W="$T/author"
G init -q --bare -b main "$O"
G init -q -b main "$C" && G -C "$C" commit -q --allow-empty -m old && G -C "$C" remote add origin "$O" && G -C "$C" push -q origin main
G clone -q "$O" "$W" 2>/dev/null
mkdir -p "$C/.fable-team" "$D"; printf '%s\n' "$D" > "$C/.fable-team/LIVE_ROOT"
# ref origin/main 트리를 «주어진 카드 경로들만» 있는 꼴로 바꾸고 C 에서 fetch
setref() { (cd "$W" && git rm -rq --ignore-unmatch design >/dev/null; for p in "$@"; do mkdir -p "$(dirname "$p")"; : > "$p"; git add "$p"; done; G commit -q --allow-empty -m ref && git push -q origin main) && G -C "$C" fetch -q origin; }
put() { mkdir -p "$(dirname "$1/$2")"; : > "$1/$2"; }
clean() { rm -rf "$C/design" "$D/design"; }
python3 - "$T/seats.json" "$CARD" <<'PY'
import json, sys
json.dump({"_master": "m#1", "m#1": {"role": "master", "agent": "claude", "tick": None},
           "ft-v65-temp-m5-x": {"role": "nano", "model": "claude-fable-5-1", "index": sys.argv[2],
                                "raised": {"reason": "ghost verdict", "card": sys.argv[2]}}}, open(sys.argv[1], "w"), ensure_ascii=False)
PY
CHK() { out="$(python3 "$RAISED" check "$T/seats.json" --root "$C" 2>"$T/err")"; rc=$?; err="$(cat "$T/err")"; }
lines() { printf '%s\n' "$out" | grep -c '▶내릴 것'; }

# ⓐ 데이터 루트 진행/ 에만(공용 루트 0 · ref 0) → 출력 0
clean; setref; put "$D" "$CARD"; CHK
rc_is "$rc" 0 "ⓐ rc"; eq "$out" "" "ⓐ 데이터 루트 진행/ 에만 → ▶내릴 것 0 (고치기 전: «(카드 없음)» 오탐)"; eq "$err" "" "ⓐ stderr 0"
# ⓐ2 공용 루트 진행/ 에만 → 출력 0(공용 루트도 여전히 본다)
clean; put "$C" "$CARD"; CHK; rc_is "$rc" 0 "ⓐ2 rc"; eq "$out" "" "ⓐ2 공용 루트 진행/ → 0"
# ⓐ3 ref 진행/ 에만 → 출력 0
clean; setref "$CARD"; CHK; rc_is "$rc" 0 "ⓐ3 rc"; eq "$out" "" "ⓐ3 ref origin/main 진행/ → 0"

# ⓑ 데이터 루트 진행/ + origin/main 완성/ → 가장 앞선 «완성» 1줄
clean; setref "$DONE"; put "$D" "$CARD"; CHK
rc_is "$rc" 0 "ⓑ rc"; eq "$(lines)" 1 "ⓑ 1줄"; has "$out" "▶내릴 것 ft-v65-temp-m5-x 모델=claude-fable-5-1 사유=ghost verdict (카드 완성)" "ⓑ ref 완성 > 데이터 루트 진행"
# ⓑ2 데이터 루트 대기/ + 공용 루트 진행/ → 진행(0줄) · ⓑ3 공용 루트 완성/ + 데이터 루트 진행/ → 완성
clean; setref; put "$D" "$WAIT"; put "$C" "$CARD"; CHK; eq "$out" "" "ⓑ2 대기 < 진행 → 진행 = 0줄"
clean; put "$D" "$CARD"; put "$C" "$DONE"; CHK; has "$out" "(카드 완성)" "ⓑ3 공용 루트 완성 > 데이터 루트 진행"

# ⓒ 세 자리 모두 없음 → «(카드 없음)» 1줄 · 못 본 자리 표기 0(셋 다 봤다)
clean; setref; CHK
rc_is "$rc" 0 "ⓒ rc"; eq "$(lines)" 1 "ⓒ 1줄"; has "$out" "(카드 없음)" "ⓒ 세 자리 없음 → 카드 없음"; hasnt "$out" "못 본 자리" "ⓒ 세 자리 다 봄 → 표기 0"

# ⓓ LIVE_ROOT 파일 없음 → 공용 루트·ref 만 보고 판정 · «못 본 자리» 표기
mv "$C/.fable-team/LIVE_ROOT" "$T/LIVE_ROOT.off"
clean; setref; put "$D" "$CARD"; CHK
rc_is "$rc" 0 "ⓓ rc"; eq "$(lines)" 1 "ⓓ 데이터 루트를 못 봄 → 공용 루트·ref 판정 1줄"
has "$out" "(카드 없음) · 못 본 자리: 데이터 루트(LIVE_ROOT 없음" "ⓓ 못 본 자리 표기(조용한 통과 0)"
clean; setref "$CARD"; CHK; rc_is "$rc" 0 "ⓓ2 rc"; eq "$out" "" "ⓓ2 LIVE_ROOT 없음 + ref 진행/ → 0"
mv "$T/LIVE_ROOT.off" "$C/.fable-team/LIVE_ROOT"
printf '%s\n' "$T/없는폴더" > "$C/.fable-team/LIVE_ROOT"; clean; setref "$CARD"; CHK
rc_is "$rc" 2 "ⓓ3 LIVE_ROOT 가 없는 폴더 → rc2"; has "$err" "ft_raised: ERROR" "ⓓ3 사유 줄"; eq "$out" "" "ⓓ3 목록 0"
printf '%s\n' "$D" > "$C/.fable-team/LIVE_ROOT"

# ⓔ ref 못 읽음 → rc2 + 사유 · 목록 0
G -C "$C" remote remove origin; G -C "$C" update-ref -d refs/remotes/origin/main; clean; CHK
rc_is "$rc" 2 "ⓔ origin 없음 → rc2"; has "$err" "ft_raised: ERROR" "ⓔ stderr 사유"; has "$err" "origin/main" "ⓔ 사유에 ref 이름"; eq "$out" "" "ⓔ 목록 0(조용한 «없음» 0)"
NG="$T/notgit"; mkdir -p "$NG/.fable-team"; out="$(python3 "$RAISED" check "$T/seats.json" --root "$NG" 2>"$T/err")"; rc=$?
rc_is "$rc" 2 "ⓔ2 리포 아님 → rc2"; has "$(cat "$T/err")" "origin/main" "ⓔ2 사유"; eq "$out" "" "ⓔ2 목록 0"
G -C "$C" remote add origin "$O"; G -C "$C" fetch -q origin

# ⓕ 틱 raised_watch 실경로(cwd = 공용 루트 · FT_ROOT 없음 · --root 인자 그대로) → 쪽지 0 · ERROR 0
printf '#!/bin/bash\necho "$*" >> "%s/mbox.log"\n' "$T" > "$T/fakembox.sh"; chmod +x "$T/fakembox.sh"
TICK() { (cd "$C" && env FT_TICK_RAISED_BIN="$RAISED" FT_TICK_SEATS="$T/seats.json" FT_TICK_STATE_DIR="$T/state" FT_TICK_MBOX="$T/fakembox.sh" FT_TICK_PIDFILE="$T/tick.pid" FT_TICK_STAMP_PREFIX="$T/stamp-" \
  FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_API_OUTAGE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_RESUME=0 FT_TICK_STALL_INTERVAL=99999999999 FT_TICK_GOAL_INTERVAL=99999999999 bash "$BIN/ft-tick.sh" --once 2>&1); }
clean; setref; put "$D" "$CARD"; t="$(TICK)"
n="$(grep -c '▶내릴 것' "$T/mbox.log" 2>/dev/null || true)"; eq "${n:-0}" 0 "ⓕ 틱: 데이터 루트 진행/ 카드 → ▶내릴 것 쪽지 0"; hasnt "$t" "raised_watch: ERROR" "ⓕ 틱 raised_watch ERROR 0"
clean; setref "$DONE"; put "$D" "$CARD"; t="$(TICK)"
has "$(cat "$T/mbox.log" 2>/dev/null)" "[▶내릴 것] 상향 좌석 1건" "ⓕ2 틱: ref 완성 → 쪽지 1(진짜 경보는 그대로)"; hasnt "$t" "raised_watch: ERROR" "ⓕ2 틱 ERROR 0"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
