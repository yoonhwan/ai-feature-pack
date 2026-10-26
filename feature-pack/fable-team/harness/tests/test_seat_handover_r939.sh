#!/usr/bin/env bash
# test_seat_handover_r939.sh — r939: 승계는 «곧 끝나는 일»(DA·설치·격리 사본)을 죽이지 않고 후계에게 넘긴다 · 감시 루프만 지금처럼 reap.
#   ⓐ retire A→B: ft-da-codex.sh 꼴·install.sh 꼴 생존 + `reap-handover pid=… cmd=… to=B` · 감시 루프만 reap · 끝 줄 `reap A stopped=1 handed=2 left=0 rc=0`
#   ⓑ 넘김 목록 = resume 파일(`ZC_RESUME_DIR/<A>.json`) "handed" 칸(pid·cmd·시작 시각) · 기존 칸 보존 · 기록 없으면 곁파일 · retire 가 `--handover <후계>` 를 넘김
#   ⓒ 닫기(후계 없음) = 지금 그대로 전부 reap — 회귀 0 · 닫기 3종은 `--handover` 를 쓰지 않는다(정적)
#   ⓓ «곧 끝나는 일» 판정 = 허용 목록(ft-da-codex.sh·install.sh·ft-scratch-repo.sh) · `timeout <n>` · FT_BG_FINITE=1 — 글자 흉내·루프·그 밖은 reap
#   ⓔ ft-leak-reap: 넘긴 pid 가 retire 뒤 70분 초과로 살아 있으면 보고(죽이지 않음 · 줄 1) · 신선한 넘김은 보고 0
#   변이 3종(사본에서만): 넘김 끔 → ⓐ 빨강 · 허용 목록 «글자» 넓힘 → ⓓ 빨강 · 닫기에 넘김 → ⓒ 빨강
# 실프로세스 픽스처 = 표식 r939fx-<pid> 를 argv 에 단 ppid 1 고아만(좌석 이름은 가짜 · tmux 세션 없음 → env FT_SEAT 경로만) — trap 이 정리. 상태 폴더는 전부 임시.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R939_BIN:-$HERE/../../harness/bin}"
REAP="$BIN/ft-seat-reap.sh"; RETIRE="$BIN/ft-seat-retire.sh"; LEAK="$BIN/ft-leak-reap.sh"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; MK="r939fx-$$"
OLD="r939t-$$#0"; NEW="r939t-$$#1"
cleanup() { local p; for p in $(pgrep -f "$MK" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done; }
trap 'cleanup; rm -rf "$T0"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있음: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo dead; }
killtag() { local p; for p in $(pgrep -f -- "$1" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done; sleep 0.2; }

mkdir -p "$TMP/da" "$TMP/inst" "$TMP/gu" "$TMP/resume" "$TMP/permits" "$TMP/defer"
cat > "$TMP/da/ft-da-codex.sh" <<'EOF'
sleep 60
EOF
cat > "$TMP/inst/install.sh" <<'EOF'
sleep 60
EOF
cat > "$TMP/gu/guard.sh" <<'EOF'
while true; do sleep 1; done
EOF
cp "$TMP/gu/guard.sh" "$TMP/gu/watcher.sh"
cat > "$TMP/gu/mimic.sh" <<'EOF'
sleep 60
EOF
cp "$TMP/gu/mimic.sh" "$TMP/gu/sleeper.sh"
TMO="$(command -v timeout 2>/dev/null || true)"   # 실 timeout(coreutils) — «timeout <n> <명령…>» 꼴은 부모 프로세스에 그대로 남는다
chmod +x "$TMP/da/"*.sh "$TMP/inst/"*.sh "$TMP/gu/"*.sh
export ZC_RESUME_DIR="$TMP/resume" FT_SUCCESSOR_DIR="$TMP/succ" FT_PERMIT_DIR="$TMP/permits" FT_REAP_DEFER_DIR="$TMP/defer"
export FT_PRESS_RUNNER_RE="r939-never-$$"   # 이 머신의 실 press 가 픽스처 판정에 섞이지 않게
seats() { printf '{"%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$OLD" > "$TMP/seats.json"; }

spawn() {  # spawn <표식> <env…|""> <명령…> — ppid 1 고아 1개 · pid 출력
  local tag="$1" envs="$2"; shift 2
  ( cd "$TMP" || exit; env FT_SEAT="$OLD" $envs nohup "$@" >/dev/null 2>&1 & )
  sleep 0.6
  pgrep -f -- "$tag" | while read -r p; do [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && echo "$p"; done | tail -1
}
tmox() {   # tmox <표식> — 설치 꼴 고아 1개(timeout 이 있으면 «timeout 60 …» 꼴로)
  if [ -n "$TMO" ]; then spawn "$1" "" "$TMO" 60 "$BASH_X" "$TMP/inst/install.sh" --tag "$1"
  else spawn "$1" "" "$BASH_X" "$TMP/inst/install.sh" --tag "$1"; fi
}
BASH_X="$(command -v bash)"
PROBE="$(spawn "p-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "p-$MK")"
ENVOK=0; [ -n "$PROBE" ] && ps -E -ww -o command= -p "$PROBE" | grep -q "FT_SEAT=$OLD" && ENVOK=1; kill "$PROBE" 2>/dev/null
[ "$ENVOK" = 1 ] || { echo "SKIP 이 머신은 $BASH_X 의 env 를 ps 로 못 읽음 — ② 고아 픽스처 불가"; exit 0; }
for f in "$REAP" "$RETIRE" "$LEAK"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done

echo "== ⓐ retire A→B — DA·설치는 넘김 · 감시 루프만 reap"
seats
DA="$(spawn "da-$MK" ""  "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "da-$MK")"
IN="$(tmox "in-$MK")"
GU="$(spawn "gu-$MK" ""  "$BASH_X" "$TMP/gu/guard.sh" --tag "gu-$MK")"
chk "ⓐ픽스처 3개(ppid 1)" "$([ -n "$DA" ] && [ -n "$IN" ] && [ -n "$GU" ] && echo 3)" 3
out="$(bash "$RETIRE" "$OLD" "$NEW" --seats "$TMP/seats.json" 2>&1)"; rc=$?
chk "ⓐretire rc 0" "$rc" 0
has "$out" "reap-handover pid=$DA cmd=" "ⓐDA 넘김 줄"
has "$out" "reap-handover pid=$IN cmd=" "ⓐ설치 넘김 줄"
hasnt "$out" "reap-handover pid=$GU" "ⓐ감시 루프는 넘기지 않음"
has "$out" " to=$NEW" "ⓐ넘김 대상 = 후계"
chk "ⓐDA·설치 생존 · 감시 루프 정지" "$(alive "$DA") $(alive "$IN") $(alive "$GU")" "alive alive dead"
chk "ⓐ끝 줄 = stopped=1 handed=2 left=0" "$(grep -oE 'stopped=[0-9]+ handed=[0-9]+ left=[0-9]+' <<< "$out" | tail -1)" "stopped=1 handed=2 left=0"
chk "ⓐCLOSE-FAIL 0 · reap left=0 rc=0" "$(grep -c CLOSE-FAIL <<< "$out") $(tail -1 <<< "$out")" "0 reap left=0 rc=0"
kill "$DA" "$IN" 2>/dev/null

echo "== ⓑ 넘김 목록 — resume 「handed」 칸(pid·cmd·시작 시각) · retire 가 --handover 를 넘김"
printf '#!/bin/sh\necho "ARGV $*" > "%s"\necho "reap $1 stopped=0 handed=0 left=0 rc=0"\n' "$TMP/argv.txt" > "$TMP/reap-stub.sh"
seats; FT_SEAT_REAP_BIN="$TMP/reap-stub.sh" bash "$RETIRE" "$OLD" "$NEW" --seats "$TMP/seats.json" >/dev/null 2>&1
chk "ⓑretire → reap 인자" "$(cat "$TMP/argv.txt" 2>/dev/null)" "ARGV $OLD --orphans-only --defer-press --handover $NEW"
printf '{"name": "%s", "uuid": "u-1", "model": "m"}\n' "$OLD" > "$TMP/resume/$OLD.json"
DA2="$(spawn "da2-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "da2-$MK")"
IN2="$(tmox "in2-$MK")"
out="$(bash "$REAP" "$OLD" --orphans-only --handover "$NEW" 2>&1)"
has "$out" "reap-handover-record $TMP/resume/$OLD.json handed=2" "ⓑresume handed 기록 줄"
chk "ⓑhanded 2건 · 기존 칸 보존" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get("handed") or []), d.get("uuid"), d.get("model"))' "$TMP/resume/$OLD.json")" "2 u-1 m"
chk "ⓑ항목 칸 = pid·cmd·started·at" "$(python3 -c 'import json,sys; e=(json.load(open(sys.argv[1])).get("handed") or [])[0]; print(" ".join(sorted(e)))' "$TMP/resume/$OLD.json")" "at cmd pid started"
chk "ⓑ기록된 pid = 살아 있는 넘김 pid" "$(python3 -c 'import json,sys; print(" ".join(str(e["pid"]) for e in json.load(open(sys.argv[1]))["handed"]))' "$TMP/resume/$OLD.json")" "$DA2 $IN2"
chk "ⓑ넘긴 pid 생존 · stopped 0" "$(alive "$DA2") $(alive "$IN2") $(grep -oE 'stopped=[0-9]+ handed=[0-9]+' <<< "$out" | tail -1)" "alive alive stopped=0 handed=2"
kill "$DA2" "$IN2" 2>/dev/null
rm -f "$TMP/resume/$OLD.json"
DA3="$(spawn "da3-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "da3-$MK")"
out="$(bash "$REAP" "$OLD" --orphans-only --handover "$NEW" 2>&1)"
has "$out" "reap-handover-record $TMP/resume/$OLD.handed.json handed=1 (resume 기록 없음" "ⓑ기록 없으면 곁파일"
chk "ⓑ곁파일 handed 1건" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("handed") or []))' "$TMP/resume/$OLD.handed.json" 2>/dev/null)" 1
kill "$DA3" 2>/dev/null; rm -f "$TMP/resume/"*

echo "== ⓒ 닫기(후계 없음) = 지금 그대로 전부 reap · 닫기 3종은 --handover 0"
DA4="$(spawn "da4-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "da4-$MK")"
IN4="$(tmox "in4-$MK")"
GU4="$(spawn "gu4-$MK" "" "$BASH_X" "$TMP/gu/guard.sh" --tag "gu4-$MK")"
out="$(bash "$REAP" "$OLD" --orphans-only 2>&1)"; rc=$?
chk "ⓒ닫기 = 셋 다 정지 · rc 0" "$rc $(alive "$DA4") $(alive "$IN4") $(alive "$GU4")" "0 dead dead dead"
hasnt "$out" "reap-handover" "ⓒ닫기엔 넘김 줄 0"
chk "ⓒ끝 줄 = 회귀 0(stopped=3 left=0 rc=0 · handed 칸 없음)" "$(tail -1 <<< "$out") $(grep -c 'handed=' <<< "$out")" "reap $OLD stopped=3 left=0 rc=0 0"
chk "ⓒ닫기 3종 •재ap• 에 --handover 0" "$(grep -c -- '--handover' "$BIN/ft-seat-close.sh" "$BIN/ft-nano-close.sh" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')" 0

echo "== ⓓ «곧 끝나는 일» 판정 — 허용 목록 · timeout · FT_BG_FINITE (글자 흉내·루프·그 밖은 reap)"
cls() {   # cls <라벨> <env…|""> <명령…> — 넘김/정지 판정 1건
  local lbl="$1" envs="$2" p o; shift 2
  p="$(spawn "$lbl" "$envs" "$@")"
  o="$(bash "$REAP" "$OLD" --orphans-only --handover "$NEW" 2>&1)"
  if [ -n "$p" ] && grep -q "reap-handover pid=$p " <<< "$o"; then echo "handover"
  elif [ -n "$p" ] && grep -q "reap-kill pid=$p " <<< "$o"; then echo "kill"
  else echo "unknown(${p:-nopid}:$(tail -1 <<< "$o"))"; fi
  killtag "$lbl"
}
chk "ⓓ①허용 목록 ft-da-codex.sh → 넘김" "$(cls "d1-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "d1-$MK")" handover
chk "ⓓ②허용 목록 install.sh → 넘김" "$(cls "d2-$MK" "" "$BASH_X" "$TMP/inst/install.sh" --tag "d2-$MK")" handover
if [ -n "$TMO" ]; then
  chk "ⓓ③timeout <n> 으로 묶임 → 넘김" "$(cls "d3-$MK" "" "$TMO" 60 "$BASH_X" "$TMP/gu/mimic.sh" --tag "d3-$MK")" handover
else echo "SKIP ⓓ③ 이 머신에 timeout 없음"; fi
chk "ⓓ④FT_BG_FINITE=1 → 넘김" "$(cls "d4-$MK" "FT_BG_FINITE=1" "$BASH_X" "$TMP/gu/watcher.sh" --tag "d4-$MK")" handover
chk "ⓓ⑤글자 흉내(인자로만 이름) → reap" "$(cls "d5-$MK" "" "$BASH_X" "$TMP/gu/mimic.sh" ft-da-codex.sh --tag "d5-$MK")" kill
chk "ⓓ⑥명령줄에 루프(while) → reap" "$(cls "d6-$MK" "" "$BASH_X" -c "while true; do sleep 1; done" --tag "d6-$MK")" kill
chk "ⓓ⑦FT_BG_FINITE=1 + 루프 → reap(루프 우선)" "$(cls "d7-$MK" "FT_BG_FINITE=1" "$BASH_X" -c "while true; do sleep 1; done" --tag "d7-$MK")" kill
chk "ⓓ⑧목록 밖 장기 작업(python) → reap" "$(cls "d8-$MK" "" python3 -c 'import time; time.sleep(60)' --tag "d8-$MK")" kill
chk "ⓓ⑨목록 밖 스크립트(sleep 60) → reap" "$(cls "d9-$MK" "" "$BASH_X" "$TMP/gu/sleeper.sh" --tag "d9-$MK")" kill

echo "== ⓔ ft-leak-reap — 넘긴 pid 70분 초과 보고(죽이지 않음) · 신선한 넘김은 0"
mkdir -p "$TMP/resume3"
HO="$(spawn "ho-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "ho-$MK")"
FR="$(spawn "fr-$MK" "" "$BASH_X" "$TMP/inst/install.sh" --tag "fr-$MK")"
sleep 60 & DP=$!
OLDAT="$(python3 -c 'import datetime; print((datetime.datetime.now()-datetime.timedelta(minutes=120)).isoformat(timespec="seconds"))')"
NEWAT="$(python3 -c 'import datetime; print(datetime.datetime.now().isoformat(timespec="seconds"))')"
python3 - "$TMP/resume3/$OLD.json" "$HO" "$FR" "$DP" "$OLDAT" "$NEWAT" <<'PY'
import json, sys
p, ho, fr, dp, old, new = sys.argv[1:7]
json.dump({"name": "x", "handed": [
    {"pid": int(ho), "cmd": "bash ft-da-codex.sh", "started": "Mon Jan 1 00:00:00 2024", "at": old},
    {"pid": int(fr), "cmd": "bash install.sh", "started": "Mon Jan 1 00:00:00 2024", "at": new},
    {"pid": int(dp), "cmd": "bash gone.sh", "started": "Mon Jan 1 00:00:00 2024", "at": old}]},
    open(p, "w", encoding="utf-8"))
PY
LC_ALL=C ps -o pid=,ppid=,lstart=,time=,command= -p "$HO" | sed 's/^ *//' > "$TMP/snap"
out="$(ZC_RESUME_DIR="$TMP/resume3" FT_PS_SNAPSHOT="$TMP/snap" bash "$LEAK" --dry-run 2>&1)"; rc=$?
chk "ⓔhandover-stale = 70분 초과 + 살아 있음 1건" "$(grep -c 'handover-stale' <<< "$out")" 1
has "$out" "handover-stale pid=$HO" "ⓔ넘긴 pid 보고"
has "$out" "죽이지 않음" "ⓔ죽이지 않음 표시"
hasnt "$out" "handover-stale pid=$FR" "ⓔ신선한 넘김은 보고 0"
hasnt "$out" "handover-stale pid=$DP" "ⓔ죽은 pid 는 보고 0"
chk "ⓔ보고는 유출 수에 안 섞임 · 프로세스 생존" "$rc $(alive "$HO") $(grep -c '유출' <<< "$out")" "0 alive 1"
kill "$HO" "$FR" "$DP" 2>/dev/null

echo "== 변이 3종(사본에서만) — 고침이 없으면 빨강이어야 한다"
mut() {  # mut <이름> <파일> <바꿀 줄> <새 줄>
  rm -rf "$TMP/bin-$1"; mkdir -p "$TMP/bin-$1"; cp -R "$BIN"/. "$TMP/bin-$1/"
  python3 - "$TMP/bin-$1/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s:
    print("MUTATE-MISS"); sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
mut handover-off ft-seat-reap.sh 'if HAND:' 'if False and HAND:'
chk "변이①넘김 끔 → ⓐ빨강(reap-handover 0 · 전부 정지)" \
  "$( d="$(spawn "m1-$MK" "" "$BASH_X" "$TMP/da/ft-da-codex.sh" --tag "m1-$MK")"
      o="$(bash "$TMP/bin-handover-off/ft-seat-reap.sh" "$OLD" --orphans-only --handover "$NEW" 2>&1)"
      echo "$(grep -c reap-handover <<< "$o") $(alive "$d")"; killtag "m1-$MK" )" "0 dead"
mut allowlist-wide ft-seat-reap.sh '    if prog in FINITE_EXE: return "exe"' \
  '    if any(os.path.basename(a) in FINITE_EXE for a in tok): return "exe"'
chk "변이②허용 목록 «글자» 넓힘 → ⓓ빨강(글자 흉내가 넘김)" \
  "$( d="$(spawn "m2-$MK" "" "$BASH_X" "$TMP/gu/mimic.sh" ft-da-codex.sh --tag "m2-$MK")"
      o="$(bash "$TMP/bin-allowlist-wide/ft-seat-reap.sh" "$OLD" --orphans-only --handover "$NEW" 2>&1)"
      echo "$(grep -c "reap-handover pid=$d " <<< "$o")"; killtag "m2-$MK" )" 1
mut close-handover ft-seat-close.sh 'o="$(bash "${FT_SEAT_REAP_BIN:-$HERE/ft-seat-reap.sh}" "$SEAT" 2>&1)"' \
  'o="$(bash "${FT_SEAT_REAP_BIN:-$HERE/ft-seat-reap.sh}" "$SEAT" --handover x 2>&1)"'
chk "변이③닫기에도 넘김 → ⓒ빨강(닫기 3종 --handover 0 실패)" \
  "$(grep -c -- '--handover' "$TMP/bin-close-handover/ft-seat-close.sh")" 1

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
