#!/usr/bin/env bash
# test_verdict_ledger.sh — 판정 번호 원장(ft-verdict.sh) 시험: 동시 발급 중복 0 · 권위 거부 · seed · fold · 손상 줄
# 임시 디렉터리 FT_ROOT·가짜 hostname(FT_VERDICT_HOSTNAME)만 쓴다 — 실제 루트 .fable-team/state/verdicts.jsonl 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
V="$HERE/../../harness/bin/ft-verdict.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT

fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

ROOT="$T/root"; mkdir -p "$ROOT/.fable-team"
WT="$T/worktree"; mkdir -p "$WT/.fable-team"
roster() { printf '{"_name":"planner","_verdict_host":"host-a","_verdict_root":"%s"}\n' "$ROOT"; }
roster > "$ROOT/.fable-team/seats-planner.json"
cp "$ROOT/.fable-team/seats-planner.json" "$WT/.fable-team/seats-planner.json"   # 워크트리 사본(권위 키는 루트를 가리킴)
LEDGER="$ROOT/.fable-team/state/verdicts.jsonl"

export FT_VERDICT_HOSTNAME=host-a
v()  { FT_ROOT="$ROOT" bash "$V" "$@"; }

bash -n "$V" && ok "bash -n" || bad "bash -n"

# 1 seed 없음 → new 거부
v new --title t --teams a >/dev/null 2>&1 && bad "seed 없이 new 허용됨" || ok "seed 없음 → new rc≠0"
[ ! -s "$LEDGER" ] && ok "거부 뒤 원장 비어 있음" || bad "거부했는데 원장에 쓰였다"

# 1-b seed 도 발급 권위 검사: 호스트 불일치 거부 · 거부 뒤 원장 비어 있음
FT_VERDICT_HOSTNAME=host-b FT_ROOT="$ROOT" bash "$V" seed 425 --by test-seat >/dev/null 2>&1 && bad "호스트 불일치 seed 허용됨" || ok "seed 호스트 불일치 거부"
[ ! -s "$LEDGER" ] && ok "seed 거부 뒤 원장 비어 있음" || bad "거부된 seed 가 원장에 쓰였다"

# 2 seed 425 → 첫 new = 426
v seed 425 --by test-seat >/dev/null 2>&1 && ok "seed 425 rc=0" || bad "seed 실패"
v seed 430 --by test-seat >/dev/null 2>&1 && bad "seed 두 번째 허용됨" || ok "seed 재발급 rc≠0"
first="$(v new --title "첫 판정" --teams planner,harness --seq 62745,62749 --oppa-todo "컨펌 필요")"
[ "$first" = 426 ] && ok "seed 425 뒤 첫 new = 426" || bad "첫 번호 = $first"

# 3 done/todo 는 새 번호를 안 만든다
lines0="$(wc -l < "$LEDGER" | tr -d ' ')"
v done 426 --note "끝" >/dev/null 2>&1 && ok "done 426 rc=0" || bad "done 실패"
v todo 426 --clear >/dev/null 2>&1 && ok "todo --clear rc=0" || bad "todo clear 실패"
next="$(v new --title "둘째" --teams loom)"
[ "$next" = 427 ] && ok "done/todo 뒤 다음 번호 = 427 (새 번호 소비 0)" || bad "다음 번호 = $next"
v done 999 >/dev/null 2>&1 && bad "없는 n done 허용됨" || ok "없는 n done rc≠0"
v todo 999 --oppa-todo x >/dev/null 2>&1 && bad "없는 n todo 허용됨" || ok "없는 n todo rc≠0"
v done 425 >/dev/null 2>&1 && bad "seed 번호 done 허용됨" || ok "seed 번호(new 아님) done rc≠0"

# 4 fold
out="$(v list --json)"
[ "$(printf '%s' "$out" | jq -r 'length')" = 2 ] && ok "fold: 판정 2건" || bad "fold 건수: $out"
[ "$(printf '%s' "$out" | jq -r '.[] | select(.n==426) | .state')" = done ] && ok "fold: 426 done" || bad "426 state"
[ "$(printf '%s' "$out" | jq -r '.[] | select(.n==426) | .oppa_todo')" = "" ] && ok "fold: oppa_todo 최신(clear)" || bad "426 oppa_todo"
[ "$(printf '%s' "$out" | jq -r '.[] | select(.n==427) | .state')" = open ] && ok "fold: 427 open" || bad "427 state"
[ "$(printf '%s' "$out" | jq -c '.[] | select(.n==426) | .seq_out')" = "[62745,62749]" ] && ok "fold: seq_out 보존" || bad "seq_out"
v todo 427 --oppa-todo "오빠 확인" >/dev/null 2>&1
[ "$(v list --json | jq -r '.[] | select(.n==427) | .oppa_todo')" = "오빠 확인" ] && ok "fold: todo 갱신 반영" || bad "427 todo"
[ "$(v list --today | wc -l | tr -d ' ')" = 2 ] && ok "list --today 2줄" || bad "list --today"

# 5 호스트 불일치 / 루트 불일치(워크트리) 거부
FT_VERDICT_HOSTNAME=host-b FT_ROOT="$ROOT" bash "$V" new --title t --teams a >/dev/null 2>&1 && bad "호스트 불일치 허용됨" || ok "호스트 불일치 거부"
FT_ROOT="$WT" bash "$V" new --title t --teams a >/dev/null 2>&1 && bad "워크트리 루트 허용됨" || ok "루트 불일치(워크트리 경로) 거부"
[ ! -e "$WT/.fable-team/state/verdicts.jsonl" ] && ok "거부된 루트에 원장 생성 0" || bad "워크트리에 원장이 생겼다"

# 6 동시 new 20회 (두 프로세스 × 10) → 번호 중복 0 · 연속
base="$(v list --json | jq '[.[].n] | max')"
( for _ in 1 2 3 4 5 6 7 8 9 10; do v new --title p1 --teams a; done > "$T/p1.out" 2>"$T/p1.err" ) &
( for _ in 1 2 3 4 5 6 7 8 9 10; do v new --title p2 --teams b; done > "$T/p2.out" 2>"$T/p2.err" ) &
wait
nums="$(cat "$T/p1.out" "$T/p2.out" | sort -n)"
cnt="$(printf '%s\n' "$nums" | grep -c .)"; uniq_cnt="$(printf '%s\n' "$nums" | sort -u | grep -c .)"
exp="$(seq $((base+1)) $((base+20)))"
echo "동시 new 20회: 발급 ${cnt}건 · 고유 ${uniq_cnt}건 · 중복 $((cnt-uniq_cnt))"
[ "$cnt" = 20 ] && [ "$uniq_cnt" = 20 ] && ok "동시 new 20회 번호 중복 0" || bad "동시 new 중복/누락: $(cat "$T/p1.err" "$T/p2.err" | head -3)"
[ "$nums" = "$exp" ] && ok "동시 new 번호 연속 ($((base+1))..$((base+20)))" || bad "번호 비연속"
[ ! -d "$ROOT/.fable-team/state/verdicts.lock" ] && ok "잠금 잔류 0" || bad "잠금 디렉터리가 남았다"

# 6-b 죽은 pid 잠금 → stderr 1줄 + 해제 후 획득 · 산 pid 잠금 → rc 1 + 보유 pid 표시
LOCKD="$ROOT/.fable-team/state/verdicts.lock"
sleep 0 & dead=$!; wait "$dead" 2>/dev/null
mkdir "$LOCKD"; echo "$dead" > "$LOCKD/pid"
got="$(v new --title stale --teams a 2>"$T/stale.err")"; rc=$?
[ $rc -eq 0 ] && [ -n "$got" ] && grep -q "죽은 잠금 해제: 보유 pid $dead" "$T/stale.err" && ok "죽은 pid 잠금 → WARN 1줄 + 해제 후 발급($got)" || bad "죽은 잠금 rc=$rc got=$got err=$(cat "$T/stale.err")"
[ ! -d "$LOCKD" ] && ok "죽은 잠금 처리 뒤 잠금 잔류 0" || bad "잠금이 남았다"
sleep 30 & alive=$!
mkdir "$LOCKD"; echo "$alive" > "$LOCKD/pid"
FT_VERDICT_LOCK_TRIES=5 v new --title live --teams a >/dev/null 2>"$T/live.err"; rc=$?
kill "$alive" 2>/dev/null; wait "$alive" 2>/dev/null
[ $rc -eq 1 ] && grep -q "보유 pid $alive" "$T/live.err" && ok "산 pid 잠금 → rc 1 + 보유 pid $alive 표시" || bad "산 잠금 rc=$rc err=$(cat "$T/live.err")"
[ -d "$LOCKD" ] && [ "$(cat "$LOCKD/pid")" = "$alive" ] && ok "산 잠금은 건드리지 않음" || bad "산 잠금이 훼손됐다"
rm -rf "$LOCKD"

# 7 손상 줄 → rc 1 + 줄 번호 (건너뛰지 않음)
total="$(wc -l < "$LEDGER" | tr -d ' ')"
echo 'not-json garbage' >> "$LEDGER"
bad_line=$((total+1))
err="$(v list 2>&1 >/dev/null)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$err" | grep -q "줄 $bad_line" && ok "손상 줄 list rc≠0 + 줄 번호 $bad_line" || bad "손상 줄 list rc=$rc err=$err"
v new --title t --teams a >/dev/null 2>&1 && bad "손상 원장에 new 허용됨" || ok "손상 원장 new rc≠0"
v done 426 >/dev/null 2>&1 && bad "손상 원장에 done 허용됨" || ok "손상 원장 done rc≠0"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
