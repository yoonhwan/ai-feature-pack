#!/usr/bin/env bash
# test_press_queue_tail_r2387.sh — r2387 ⑪⑫⑬: 착지 꼬리 단계가 «음성 경로를 바꾼 착지» 뒤에만 queue 1회를 돌리고 STALE 줄·NEXT 줄만 1~2줄 남긴다 (K3)
#   ⑪ 착지 뒤 꼬리 · 남은 초 넉넉(≥ 11) · 음성 경로 PR 착지 → STALE 줄 + NEXT 줄 · 착지 rc 0 · LAND-TAIL 에 pressq 없음
#   ⑫ 착지 뒤 꼬리 · 남은 초 < 8 → queue 0회 · LAND-TAIL skip=pressq
#   ⑬ 음성 경로 0 PR 착지 → queue 0회(gh pr list 0) · PR·NEXT 줄 0
#   틀 = _reserve_r2355_fixture.sh(임시 origin · 가짜 gh · 느린 push) + 이 파일의 PR·묶음 도우미 · 실 gh·실 원격·실 mbox 0
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_pushahead_r2368_fixture.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el:-0}s out=${out:0:1400}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S0=$SECONDS
# ① 하네스 코드 루트 스텁이「뒤 단계 남은 0」을 만들지 않게 FT_LAND_DEADLINE 은 land() 가 DL_OFF 로만 준다 ·
#    목록 = gh «pr list» 대역(이 카드 몫) · press 도구는 queue 만 진짜(착지 판정은 스텁 0 = 이 시험은 queue 몫이 아니다)
pa_init "$T"; pa_fix
TLIST="$T/tlist.json"; : > "$TLIST"; export TLIST
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
  "pr view") cat "$STUB_JSON"; exit 0;;
  "pr list") cat "$TLIST"; exit 0;;
esac
exit 0
EOF
chmod +x "$T/gh-stub"; export FT_GH="$T/gh-stub"
cat > "$FIX/ft-press-evidence.sh" <<EOF
#!/bin/bash
[ -z "\${PRESS_EAT:-}" ] || [ -z "\${FT_LAND_DEADLINE:-}" ] || sleep "\$(python3 "$T/eat.py" "\$FT_LAND_DEADLINE" "\$PRESS_EAT" cap 99)"   # ⑫: press 검사 자리에서 «남은 N초» 까지 시계를 먹인다
case "\$1" in queue) exec bash "$BIN/ft-press-evidence.sh" "\$@";; esac
exit 0
EOF
chmod +x "$FIX/ft-press-evidence.sh"
plist() {  # plist <번호> <head> — 목록 1줄(gh 칸 = 번호·head 만) + 승인 표식 파일(이름 = head · r2387 DA#54 H3)
  python3 - "$TLIST" "$2" "$1" <<'PY'
import json, sys
json.dump([{"number": int(sys.argv[3]), "headRefOid": sys.argv[2]}], open(sys.argv[1], "w"))
PY
  mkdir -p "$T/state/autonomy-merge-approved"; : > "$T/state/autonomy-merge-approved/$2"
}
mkpr() {  # mkpr <번호> — PR 1개(바뀌는 파일 = PRF, 기본 음성 경로)
  local n="$1" f="${PRF:-worker/pr$1.py}"
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$n" origin/main >/dev/null 2>&1
  mkdir -p "$(dirname "$W/$f")"; printf 'pr%s %s-%s\n' "$n" "$$" "$SECONDS" > "$W/$f"
  local i; for i in $(seq 2 "${PROBJS:-1}"); do printf '%s %s\n' "$i" "$SECONDS" > "$W/obj-$n-$i.txt"; done   # push 객체 수(⑫ = push 상한을 키워 시계를 먹인다)
  git -C "$W" add -A && git -C "$W" commit -q -m "pr $n work"; git -C "$W" push -q -f origin "pr$n:refs/pull/$n/head" >/dev/null 2>&1; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys
print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"isCrossRepository":False,"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$n" > "$STUB_JSON"
}
bundle() {  # bundle <head> <run> — 지금 main + 그 PR 의 세트에 유효 묶음 1개를 origin 에 심는다
  local h="$1" run="$2" m t set d rows c
  m="$(sha "$W" origin/main)"; t="$(git -C "$W" merge-tree --write-tree "$m" "$h" | head -n1)"; set="$(git -C "$W" commit-tree "$t" -p "$m" -m "set $h")"
  d="$T/bun"; mkdir -p "$d"
  printf 'set=%s\nrun_id=%s\nseat=t\nts=0\n' "$set" "$run" > "$d/meta.txt"
  printf '{"axis":"conn","epoch_ms":1,"run_id":"%s"}\n' "$run" > "$d/poller_dom.jsonl"
  printf 'run_id: %s\n\n| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 | x | 12:00 |\n| 코드 | y | 12:00 |\n| 로그 | z | 12:01 |\n| 화면 | w | 12:02 |\n| turbopack | build 0 · runtime 1 · config 0 · 원문 turbopack.txt | 12:03 |\n' "$run" > "$d/table.md"
  printf '%s\n' 'data: {"result":{"content":[{"type":"text","text":"{\"configErrors\":[],\"sessionErrors\":[{\"url\":\"/realtime\",\"buildError\":null,\"runtimeErrors\":[{\"m\":1}]}]}"}]},"jsonrpc":"2.0","id":1}' > "$d/turbopack.txt"
  rows="$(for f in meta.txt poller_dom.jsonl table.md turbopack.txt; do printf '100644 blob %s\t%s\n' "$(git -C "$W" hash-object -w "$d/$f")" "$f"; done)"
  c="$(git -C "$W" commit-tree "$(printf '%s\n' "$rows" | git -C "$W" mktree)" -p "$set" -m bundle)"
  git -C "$W" push -q origin "$c:refs/press/$set-$run"
  git -C "$W" fetch -q origin '+refs/press/*:refs/press/*'   # r2387 H1: 묶음 ref 받기 = 부르는 쪽 몫(실 착지는 press check 가 먼저 fetch 한다 · queue 는 fetch 0)
}
listn() { grep -c '^pr list' "$STUB_LOG" 2>/dev/null || true; }
qtail() { grep -E '^(PR #.* STALE|NEXT )' <<<"$out"; }

# 음성 경로 목록을 main 에 넣는다(이 리포가 «음성 경로» 를 갖게) — 그 뒤 #211 이 그 경로를 바꾼다
mkdir -p "$W/docs/rules"; printf '# 목록\n## 목록\n- `worker/**`\n' > "$W/docs/rules/press_voice_paths.md"
git -C "$W" fetch -q origin; git -C "$W" checkout -q main 2>/dev/null || git -C "$W" checkout -q -b main origin/main
git -C "$W" add -A && git -C "$W" commit -q -m "list"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin

# ===== ⑪: 음성 경로 PR 착지 · 꼬리에 queue → STALE 줄 + NEXT 줄 · 착지 rc 0 =====
mkpr 212; H212="$PRSHA"; bundle "$H212" 20261117-131500          # #212 = 옛 main 세트 묶음(착지 뒤 무효가 된다)
plist 212 "$H212" worker/pr212.py
PRF=worker/pr211.py DL_OFF=30 land "$FIX" 211 40
[ "$rc" = 0 ] && grep -q '^LANDED pr=211 ' <<<"$out" && grep -q '^PR #212 STALE · 다르게 만든 착지 ' <<<"$out" && [ "$(qtail | grep -c .)" = 2 ] && [ "$(listn)" = 1 ] \
  && ! grep -q 'skip=.*pressq' <<<"$(ltail)"
ck "⑪ 음성 경로 착지(rc 0) → 꼬리 = STALE 줄 + NEXT 줄 2줄 · gh pr list 1회 · pressq skip 0" $?
echo "단계 초: ⑪ $((SECONDS - S0))s"

# ===== ⑫: 꼬리 남은 초 < 8 → queue 0회 · LAND-TAIL skip=pressq =====
PRF=worker/pr213.py DL_OFF=34 FT_PUSH_FIXED_S=1 land "$FIX" 213 40 PRESS_EAT=10   # press 검사가 «남은 10초» 까지 시계를 먹는다 → 착지는 그대로(1초) · pressq 상한 = min(8, 9−3) = 6 < 8
[ "$rc" = 0 ] && grep -q '^LANDED pr=213 ' <<<"$out" && [ "$(listn)" = 0 ] && [ "$(qtail | grep -c .)" = 0 ] && grep -q 'pressq' <<<"$(ltail)"
ck "⑫ 남은 초 < 8 → queue 0회(gh 0) · LAND-TAIL skip 에 pressq" $?
echo "단계 초: ⑫ $((SECONDS - S0))s"

# ===== ⑬: 음성 경로 0 PR 착지 → queue 0회(gh 0) · 줄 0 =====
PRF=docs/pr214.md DL_OFF=30 land "$FIX" 214 40
[ "$rc" = 0 ] && grep -q '^LANDED pr=214 ' <<<"$out" && [ "$(listn)" = 0 ] && [ "$(qtail | grep -c .)" = 0 ] && ! grep -q 'skip=.*pressq' <<<"$(ltail)"
ck "⑬ 음성 경로 0 착지 → queue 0회(gh 0) · PR·NEXT 줄 0" $?

# ===== ⑪ 기준판 Red: 고치기 전 ft-merge-land.sh(꼬리 pressq 칸 0) 로 같은 사례 → STALE·NEXT 줄 0 =====
PACKDIR="$(git -C "$HERE" rev-parse --show-toplevel)"
BFIX="$T/bfix"; cp -R "$FIX" "$BFIX"
git -C "$PACKDIR" show "origin/main:feature-pack/fable-team/legacy/1.x/harness/bin/ft-merge-land.sh" > "$BFIX/ft-merge-land.sh" 2>/dev/null || { echo "FAIL 기준판 ft-merge-land.sh 못 읽음"; fail=$((fail+1)); }
PRF=worker/pr216.py DL_OFF=30 land "$BFIX" 216 40
[ "$rc" = 0 ] && grep -q '^LANDED pr=216 ' <<<"$out" && [ "$(qtail | grep -c .)" = 0 ] && [ "$(listn)" = 0 ] && [ "$(grep -c '^PRESS queue' "$STUB_LOG" 2>/dev/null || true)" = 0 ]
ck "⑪ 기준판 Red — 꼬리 pressq 칸 0 이면 STALE·NEXT 줄 0 · queue 부름 0(착지 rc 는 0 그대로)" $?
echo "단계 초: ⑪ 기준판 Red $((SECONDS - S0))s"

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 mbox 0)" $?
echo "단계 초: ⑬ $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
