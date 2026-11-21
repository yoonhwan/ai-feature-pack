#!/usr/bin/env bash
# test_merge_lines_replace_head_r2374_land.sh — r2374 K1 · ft-merge-land 가 gate 부름에 FT_REPLACE_HEAD = 자동 병합 전 PR head(S0 · 자동 병합 없으면 S) 를 넘긴다
#   이 파일 = 반례 ① + 변이 M1·M2(사본 · 변이마다 원본 대조 1회)   # ②~⑩ · M3~M6 = test_merge_lines_replace_head_r2374.sh(70초 상한으로 쪼갬)
#   gate = 기록 껍데기(env·인자 1줄) → 진짜 ft-merge-gate.sh exec · 임시 origin(bare)+clone · gh 스텁 — 실 gh·실 원격·실 push 0 · sleep 0
#   R2374_BIN = 기준판 대조용 bin 폴더(지정하면 변이·cmp 생략)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset FT_MERGE_LAND_CODE_AUTOMERGE FT_REPLACE_HEAD
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2374_BIN:-$HERE/../bin}"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600} gate=$(cat "$GLOG" 2>/dev/null | cut -c1-300)"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_MERGE_DENY_FILE="$T/deny.txt"
export GLOG="$T/gate.log" REALGATE="$BIN/ft-merge-gate.sh"
printf '# 시험 목록(빈)\n' > "$T/deny.txt"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
echo "$*" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
put() { mkdir -p "$(dirname "$W/$1")"; printf '%s\n' "$2" > "$W/$1"; }
pushpr() {
  git -C "$W" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"feat: PR "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" > "$STUB_JSON"
}
mkpr() { local n="$1" b="$2"; shift 2; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"; pushpr "$n" "$b"; }
adv() { git -C "$W" fetch -q origin; git -C "$W" checkout -q -B main origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "main adv"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; }
kit() {  # kit <이름> [<옛 본문> <새 본문>] → bin 사본 폴더(나머지 = 심링크 · ft-merge-land.sh = 사본(변이) · ft-merge-gate.sh = 기록 껍데기)
  local d="$T/kit-$1"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/ft-merge-land.sh" "$d/ft-merge-gate.sh"
  printf '#!/bin/bash\nprintf "%%s\\t%%s\\n" "${FT_REPLACE_HEAD-<unset>}" "$*" >> "$GLOG"\nexec bash "$REALGATE" "$@"\n' > "$d/ft-merge-gate.sh"
  python3 - "$LAND" "$d/ft-merge-land.sh" "${2:-}" "${3:-}" <<'PY' || { echo "FAIL 변이 $1 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert sys.argv[3] in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1) if sys.argv[3] else s)
PY
  printf '%s' "$d"
}
land() { local b="$1"; shift; apv "$@"; : > "$STUB_LOG"; : > "$GLOG"; out="$(bash "$b/ft-merge-land.sh" "$@" --repo "$W" 2>&1)"; rc=$?; }
g() { sed -n "${1}p" "$GLOG" | cut -f"$2"; }   # g <줄> <1=env|2=인자>

c1() {  # c1 <kit> → 자동 병합 길(PR a) · 없는 길(PR b) 둘 다 착지 · gate env = S0 / S · 다른 인자 같음
  local k="$1" n="$2" A B CA ra rb
  mkpr "$n" "a$n" "bin/a$n.sh=echo a"; A="$PRSHA"; adv "bin/m$n.sh=echo m"
  land "$k" "$n" --approve-sha "$A"; ra="$(cat "$GLOG")"; CA="$(g 2 2)"; CA="${CA%% *}"
  [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=$n "* ]] && [ "$(wc -l < "$GLOG" | tr -d ' ')" = 2 ] && [ "$(g 1 1)" = "$A" ] && [ "$(g 2 1)" = "$A" ] && [ "$CA" != "$A" ] \
    && [ "$(git -C "$W" rev-parse "$CA^1")" = "$A" ] || { echo "  (자동 병합 길) $ra"; return 1; }
  mkpr "$((n + 1))" "b$n" "bin/b$n.sh=echo b"; B="$PRSHA"
  land "$k" "$((n + 1))" --approve-sha "$B"; rb="$(cat "$GLOG")"
  [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=$((n + 1)) "* ]] && [ "$(wc -l < "$GLOG" | tr -d ' ')" = 1 ] && [ "$(g 1 1)" = "$B" ] && [ "$(g 1 2)" = "$B ${ra##*$'\t'"$CA" }" ] || { echo "  (자동 병합 없음) $rb"; return 1; }
}
S1=$SECONDS
c1 "$(kit orig)" 10; ck "① 자동 병합 길 → gate 2차 FT_REPLACE_HEAD = S0(PR head · C 의 첫 부모) · 없는 길 → FT_REPLACE_HEAD = S · 둘 다 다른 인자 같음 · 착지" $?
S2=$SECONDS
if [ -z "${R2374_BIN:-}" ]; then
  c1 "$(kit m1 'FT_REPLACE_HEAD="${S0:-$S}" fm_try' 'fm_try')" 20 >/dev/null; [ $? != 0 ]; ck "M1 ft-merge-land 의 env 넘김 지움 → ① FAIL(잡힘)" $?
  c1 "$(kit orig1)" 30; ck "M1 원본 대조 → ① 통과" $?
  c1 "$(kit m2 'FT_REPLACE_HEAD="${S0:-$S}"' 'FT_REPLACE_HEAD="$S"')" 40 >/dev/null; [ $? != 0 ]; ck "M2 env 값을 늘 \$S 로 → ① FAIL(잡힘)" $?
  c1 "$(kit orig2)" 50; ck "M2 원본 대조 → ① 통과" $?
  cmp -s "$LAND" "$BIN/../kit/fable-team/bin/ft-merge-land.sh"; ck "bin·kit cmp0 ft-merge-land.sh" $?
fi
echo "단계별 초: ① $((S2 - S1)) · 변이 $((SECONDS - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
