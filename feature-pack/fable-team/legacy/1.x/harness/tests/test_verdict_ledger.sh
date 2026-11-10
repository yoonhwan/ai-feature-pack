#!/usr/bin/env bash
# test_verdict_ledger.sh — 판정 번호 원장(ft-verdict.sh) 시험.
# r1267: 번호 권위 = md 원장 하나 → seed·new 는 은퇴(거절 1줄 rc 1 · 원장 쓰기 0). done·todo·list 는 옛 verdicts.jsonl 행을 그대로 읽고 갱신한다(시험은 옛 행을 직접 써 둔다).
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
RETIRED='REJECT 번호 권위 = md 원장(VERDICTS-planner-*.md · ft-proxy-decide.sh 발급) — ft-verdict new·seed 은퇴(r1267)'

export FT_VERDICT_HOSTNAME=host-a
v()  { FT_ROOT="$ROOT" bash "$V" "$@"; }

bash -n "$V" && ok "bash -n" || bad "bash -n"

# 1 new·seed 은퇴 — 호스트·루트·seed 유무와 무관하게 같은 1줄 rc 1 · 원장 파일 생성 0
err="$(v new --title t --teams a 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] && [ "$err" = "$RETIRED" ] && ok "new → 거절 1줄 rc 1(seed 없음)" || bad "new rc=$rc err=$err"
err="$(v seed 425 --by test-seat 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] && [ "$err" = "$RETIRED" ] && ok "seed → 거절 1줄 rc 1" || bad "seed rc=$rc err=$err"
err="$(FT_VERDICT_HOSTNAME=host-b FT_ROOT="$ROOT" bash "$V" new --title t --teams a 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] && [ "$err" = "$RETIRED" ] && ok "호스트 불일치여도 같은 거절 1줄" || bad "호스트 불일치 rc=$rc err=$err"
err="$(FT_ROOT="$WT" bash "$V" new --title t --teams a 2>&1 >/dev/null)"; rc=$?
[ $rc -eq 1 ] && [ "$err" = "$RETIRED" ] && ok "워크트리 루트여도 같은 거절 1줄" || bad "워크트리 rc=$rc err=$err"
[ ! -e "$LEDGER" ] && [ ! -e "$WT/.fable-team/state/verdicts.jsonl" ] && ok "거절한 뒤 원장 파일 생성 0" || bad "거절했는데 원장이 생겼다"

# 2 옛 행 직접 작성 — seed 425 · new 426·427 (r1267 이전에 발급된 행과 같은 모양)
mkdir -p "$ROOT/.fable-team/state"; TODAY="$(date +%Y-%m-%dT%H:%M:%S)"
{ printf '{"ev":"seed","n":425,"ts":"2026-10-01T09:00:00","by":"test-seat"}\n'
  printf '{"ev":"new","n":426,"ts":"%s","title":"첫 판정","teams":["planner","harness"],"seq_out":[62745,62749],"oppa_todo":"컨펌 필요"}\n' "$TODAY"
  printf '{"ev":"new","n":427,"ts":"%s","title":"둘째","teams":["loom"],"seq_out":[],"oppa_todo":""}\n' "$TODAY"; } > "$LEDGER"
cp "$LEDGER" "$T/ledger.before"

# 3 done/todo 는 새 번호를 안 만든다 · 옛 행 갱신은 그대로
v done 426 --note "끝" >/dev/null 2>&1 && ok "done 426 rc=0" || bad "done 실패"
v todo 426 --clear >/dev/null 2>&1 && ok "todo --clear rc=0" || bad "todo clear 실패"
[ "$(wc -l < "$LEDGER" | tr -d ' ')" = 5 ] && ok "done·todo 가 줄 2개만 더함(새 번호 0)" || bad "원장 줄 수 $(wc -l < "$LEDGER")"
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

# 6 동시 new 20회(두 프로세스 × 10) → 전부 rc 1 · 번호 0개 · 원장 그대로 · 잠금 잔류 0
before="$(wc -c < "$LEDGER" | tr -d ' ')"
( for _ in 1 2 3 4 5 6 7 8 9 10; do v new --title p1 --teams a >> "$T/p1.out" 2>>"$T/p1.err"; echo $? >> "$T/p1.rc"; done ) &
( for _ in 1 2 3 4 5 6 7 8 9 10; do v new --title p2 --teams b >> "$T/p2.out" 2>>"$T/p2.err"; echo $? >> "$T/p2.rc"; done ) &
wait
rcs="$(cat "$T/p1.rc" "$T/p2.rc" | sort | uniq -c | tr -s ' ')"
[ "$rcs" = " 20 1" ] && [ ! -s "$T/p1.out" ] && [ ! -s "$T/p2.out" ] && ok "동시 new 20회 전부 rc 1 · 번호 출력 0" || bad "동시 new: $rcs"
[ "$(wc -c < "$LEDGER" | tr -d ' ')" = "$before" ] && ok "동시 new 뒤 원장 크기 그대로" || bad "원장이 변했다"
[ ! -d "$ROOT/.fable-team/state/verdicts.lock" ] && ok "잠금 잔류 0" || bad "잠금 디렉터리가 남았다"

# 6-b 죽은 pid 잠금 → stderr 1줄 + 해제 후 획득 · 산 pid 잠금 → rc 1 + 보유 pid 표시 (잠금을 쓰는 갈래 = done)
LOCKD="$ROOT/.fable-team/state/verdicts.lock"
sleep 0 & dead=$!; wait "$dead" 2>/dev/null
mkdir "$LOCKD"; echo "$dead" > "$LOCKD/pid"
got="$(v done 427 --note stale 2>"$T/stale.err")"; rc=$?
[ $rc -eq 0 ] && [ "$got" = "DONE n=427" ] && grep -q "죽은 잠금 해제: 보유 pid $dead" "$T/stale.err" && ok "죽은 pid 잠금 → WARN 1줄 + 해제 후 done($got)" || bad "죽은 잠금 rc=$rc got=$got err=$(cat "$T/stale.err")"
[ ! -d "$LOCKD" ] && ok "죽은 잠금 처리 뒤 잠금 잔류 0" || bad "잠금이 남았다"
sleep 30 & alive=$!
mkdir "$LOCKD"; echo "$alive" > "$LOCKD/pid"
FT_VERDICT_LOCK_TRIES=5 v done 426 >/dev/null 2>"$T/live.err"; rc=$?
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
v done 426 >/dev/null 2>&1 && bad "손상 원장에 done 허용됨" || ok "손상 원장 done rc≠0"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
