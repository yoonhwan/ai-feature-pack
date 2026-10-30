#!/usr/bin/env bash
# test_merge_land_docam_skip_reason_r1176.sh — r1176: «main 이 앞섬» 게이트 거절에서 문서 자동 병합(docam)을 건너뛰면 그 이유를 거절 줄에 붙인다(판정·착지 동작 불변)
#   반례 R1~R4(카드 동결 집합) · 변이 1(비 .md 이유 줄 삭제 → R1 FAIL) · 기준판(r1176 직전 팩 main 고정 sha 판 = 이유 0)
#   임시 origin(bare)+clone · gh 는 스텁 — 실 gh·실 원격·실 push 0 · 자기 재호출은 real_state_guard 의 RSG_ACTIVE 재진입 표지 하나뿐
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T_START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:500}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_MERGE_DENY_FILE="$T/deny.txt"
printf '# 시험 목록(빈)\n' > "$T/deny.txt"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
put() { mkdir -p "$(dirname "$W/$1")"; printf '%s\n' "$2" > "$W/$1"; }   # put <경로> <내용>
mkpr() {  # mkpr <PR번호> <가지> <경로=내용>... — origin/main 에서 가지를 따 파일을 쓰고 PR ref·JSON 작성
  local n="$1" b="$2"; shift 2; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"; pushpr "$n" "$b"
}
pushpr() {
  git -C "$W" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"docs: PR "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" > "$STUB_JSON"
}
adv() {  # adv <경로=내용>... — 승인 «뒤» main 이 앞섬(다른 팀 착지 흉내 · origin 에 직접)
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B main origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "main adv"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
}
land() { local b="$1"; shift; apv "$@"; : > "$STUB_LOG"; out="$(bash "$b" "$@" --repo "$W" 2>&1)"; rc=$?; }
mut() {  # mut <이름> <옛 본문> <새 본문> → 변이 사본 폴더(나머지 bin 은 심링크)
  local d="$T/mut-$1"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/ft-merge-land.sh"
  python3 - "$LAND" "$d/ft-merge-land.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert sys.argv[3] in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
  printf '%s' "$d"
}
AUTO="INFO 문서 PR main 자동 병합 C="; STALE="ft-head-sync.sh 로 최신화 먼저"; SKIP="문서 자동 병합 건너뜀:"
rejw() { [ "$rc" = 1 ] && [[ "$out" == *"REJECT"* ]] && [[ "$out" == *"$STALE"* ]] && [[ "$out" != *"$AUTO"* ]] && [ "$(omain)" = "$1" ]; }   # rejw <앞선 main> — 지금 거절 그대로(rc·문구·main 불변)

# ===== 사전: 문법 · 줄 수 상한 · 짝 사본 =====
bash -n "$LAND"; ck "bash -n ft-merge-land.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 상한 유지)" $?
cmp -s "$LAND" "$KIT/ft-merge-land.sh"; ck "ⓓ 짝 사본 bin·kit cmp0" $?

# ===== R1: 문서 PR(design/x.md + design/x.json) · main 앞섬 · 승인 = head → 비 .md 이유 · 기준판 = 이유 0 · 변이 =====
mkpr 1 doc1 "design/x.md=PR1" "design/x.json={}"; A1="$PRSHA"; adv "design/y/b1.md=M1"; M1="$(omain)"
BASE_SHA=c5fbe4bb21aca124f8114a1524e99fe3bd3f4d4d   # r1176 직전 팩 origin/main(nano 가지 base)
TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" && pwd -P)"; PFX="$(cd "$HERE/.." && pwd -P)"; PFX="${PFX#$TOP/}"; mkdir -p "$T/red"
if [ -n "$TOP" ] && git -C "$TOP" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  for f in "$BIN"/*; do ln -s "$f" "$T/red/$(basename "$f")"; done; rm -f "$T/red/ft-merge-land.sh"
  git -C "$TOP" show "$BASE_SHA:$PFX/kit/fable-team/bin/ft-merge-land.sh" > "$T/red/ft-merge-land.sh" && [ -s "$T/red/ft-merge-land.sh" ] || { echo "FAIL 기준판을 못 꺼냄"; exit 1; }
  land "$T/red/ft-merge-land.sh" 1 --approve-sha "$A1"
  rejw "$M1" && [[ "$out" != *"$SKIP"* ]]; ck "기준판(r1176 직전 판): R1 → REJECT «최신화 먼저» 만 · 건너뛴 이유 0(지금 결함 재현)" $?
else echo "SKIP 기준판 칸(R1 이유 0 재현) — base_sha $BASE_SHA 객체 없음(git 사본 아님)"; fi
land "$LAND" 1 --approve-sha "$A1"
rejw "$M1" && [[ "$out" == *"$SKIP 비 .md 1개: design/x.json — 문서 자동 병합 대상 아님"* ]] && [[ "$out" == *"증거는 .md 한 장으로"* ]] && [ ! -s "$STUB_LOG" ]
ck "ⓐ R1 → REJECT rc1 · 줄에 «비 .md 1개: design/x.json» · main 불변 · PR 쓰기 0" $?
MUTW="$(mut no-why 'DOCAM_WHY="비 .md' ': "비 .md')"
land "$MUTW/ft-merge-land.sh" 1 --approve-sha "$A1"; rejw "$M1" && [[ "$out" != *"$SKIP"* ]]; ck "ⓐ 변이(비 .md 이유 줄 삭제) → R1 FAIL 재현(이유 0 · 거절은 그대로)" $?

# ===== R2: 문서 PR(design/x.md) · main 앞섬 · 승인 sha ≠ head → 승인 ≠ head 이유 =====
mkpr 2 doc2 "design/x2.md=PR2"; A2="$PRSHA"; put design/x2b.md PR2B; cm "$W" "pr 2 more"; pushpr 2 doc2; H2="$PRSHA"; adv "design/y/b2.md=M2"; M2="$(omain)"
land "$LAND" 2 --approve-sha "$A2"
rejw "$M2" && [[ "$out" == *"$SKIP 승인 sha ${A2:0:10} ≠ PR head ${H2:0:10} — main 병합만 한 head 면 승인 sha 그대로 다시 착지(EQUIV 판정)"* ]] && [[ "$out" != *"비 .md"* ]]
ck "ⓑ R2 → REJECT rc1 · 줄에 «승인 sha … ≠ PR head …» · main 불변" $?

# ===== R3: 문서 PR(design/x.md) · main 앞섬 · 승인 = head → 자동 병합 그대로 =====
mkpr 3 doc3 "design/x3.md=PR3"; A3="$PRSHA"; adv "design/y/b3.md=M3"; M3="$(omain)"
land "$LAND" 3 --approve-sha "$A3"
[ "$rc" = 0 ] && [[ "$out" == *"$AUTO"* ]] && [[ "$out" == *"LANDED pr=3 "* ]] && [[ "$out" != *"$SKIP"* ]] && [ "$(sha "$ORIGIN" main^)" = "$M3" ]
ck "ⓒ R3 → 자동 병합 INFO · 착지 rc0 · 건너뜀 줄 0" $?

# ===== R4: 코드 PR(a.py) · main 앞섬 → 비 .md 이유 · rc 그대로 =====
mkpr 4 code4 "a.py=print(4)"; A4="$PRSHA"; adv "design/y/b4.md=M4"; M4="$(omain)"
land "$LAND" 4 --approve-sha "$A4"
rejw "$M4" && [[ "$out" == *"$SKIP 비 .md 1개: a.py — "* ]]; ck "ⓐ R4 → REJECT rc1(지금과 같음) · 줄에 «비 .md 1개: a.py»" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
