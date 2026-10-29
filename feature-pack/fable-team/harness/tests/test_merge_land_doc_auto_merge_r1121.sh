#!/usr/bin/env bash
# test_merge_land_doc_auto_merge_r1121.sh — r1121: 문서 전용 PR 은 승인 뒤 main 이 앞서도 ft-merge-land 가 병합 커밋 C(첫 부모 S · 둘째 M)로 착지(재승인 0)
#   반례 R1~R9(카드 동결 집합) · 변이 3(C 대신 S · --no-renames 제거 · C 부모 순서 뒤집기) · 기준판(r1121 직전 main 고정 sha 판 = REJECT · r1132)
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
oshow() { git -C "$ORIGIN" show "main:$1" 2>/dev/null; }
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
AUTO="INFO 문서 PR main 자동 병합 C="; STALE="ft-head-sync.sh 로 최신화 먼저"

# ===== 사전: 문법 · 줄 수 상한 · 짝 사본 =====
bash -n "$LAND"; ck "bash -n ft-merge-land.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 상한 유지)" $?
cmp -s "$LAND" "$KIT/ft-merge-land.sh"; ck "ⓕ 짝 사본 bin·kit cmp0" $?

# ===== 기준판 + R1: 문서 PR 승인 뒤 main 이 다른 문서 1커밋 앞섬 =====
mkpr 1 doc1 "design/x/a.md=PR-A"; A1="$PRSHA"; adv "design/y/b.md=MAIN-B"; M1="$(omain)"
# 기준판 = r1121 착지 3959eb0144 의 첫 부모 고정 sha(r1132 — origin/main 은 착지 뒤 새 코드가 된다) · 경로는 실경로(/var↔/private/var)
BASE_SHA=c392b5e288e055ad61fba6cfb8b1763c9da1c99e
TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" && pwd -P)"; PFX="$(cd "$HERE/.." && pwd -P)"; PFX="${PFX#$TOP/}"; mkdir -p "$T/red"
HAVE_BASE=0; [ -n "$TOP" ] && git -C "$TOP" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null && HAVE_BASE=1
if [ "$HAVE_BASE" = 1 ]; then
  for f in "$BIN"/*; do ln -s "$f" "$T/red/$(basename "$f")"; done; rm -f "$T/red/ft-merge-land.sh"
  git -C "$TOP" show "$BASE_SHA:$PFX/kit/fable-team/bin/ft-merge-land.sh" > "$T/red/ft-merge-land.sh" && [ -s "$T/red/ft-merge-land.sh" ] || { echo "FAIL 기준판을 못 꺼냄"; exit 1; }
  land "$T/red/ft-merge-land.sh" 1 --approve-sha "$A1"
  [ "$rc" = 1 ] && [[ "$out" == *"$STALE"* ]] && [ "$(omain)" = "$M1" ]; ck "기준판(r1121 직전 main 판): R1 → REJECT «최신화 먼저» · main 불변(사람 왕복 1회 재현)" $?
else echo "SKIP 기준판 칸(R1 REJECT 재현) — base_sha $BASE_SHA 객체 없음(git 사본 아님 · git archive 사본)"; fi
land "$LAND" 1 --approve-sha "$A1"
[ "$rc" = 0 ] && [[ "$out" == *"$AUTO"* ]] && [[ "$out" == *"LANDED pr=1 "* ]] && [ "$(oshow design/x/a.md)" = PR-A ] && [ "$(oshow design/y/b.md)" = MAIN-B ] && [ "$(sha "$ORIGIN" main^)" = "$M1" ]
ck "ⓐ R1 → 착지 rc0 · INFO 자동 병합 줄 · a.md(PR 판)·b.md(main 판) 둘 다 · squash 1커밋(부모 = 앞선 main)" $?
[ "$(ls "$T/state/autonomy-merge-approved" | grep -c .)" = 1 ] && [ -f "$T/state/autonomy-merge-approved/$A1" ]; ck "ⓐ R1 재승인 0(승인 파일 = A 1개뿐)" $?
git -C "$ORIGIN" log -1 --format=%B main | grep -qF "main 자동 병합(문서 전용 · 겹침 0) C=" && git -C "$ORIGIN" log -1 --format=%B main | grep -qF "PR #1 (head $A1)" \
  && tail -n1 "$T/state/merge-gate.log" | grep -q " doc-auto-merge=$A1" && grep -qF "main 자동 병합(문서 전용 · 겹침 0)" "$STUB_LOG"
ck "ⓐ R1 표기: 착지 메시지 끝줄 · head = PR head · merge-gate.log doc-auto-merge · PR 코멘트" $?

# ===== R2: main 이 코드 파일 1커밋 앞섬 → 착지 · z.sh = main 판(되돌림 0) · 변이 ⓐ(C 대신 S) =====
adv "bin/z.sh=echo z1"; mkpr 2 doc2 "design/x/a2.md=PR-A2"; A2="$PRSHA"; adv "bin/z.sh=echo z2-main"; M2="$(omain)"
MUTS="$(mut keep-s 'S="$(G commit-tree' 'CC="$(G commit-tree')"
land "$MUTS/ft-merge-land.sh" 2 --approve-sha "$A2"; r2m=0; { [ "$rc" = 0 ] && [ "$(oshow bin/z.sh)" = "echo z2-main" ]; } && r2m=1
[ "$r2m" = 0 ] && [ "$(omain)" = "$M2" ]; ck "ⓐ 변이(C 대신 S 를 후보로) → R2 FAIL 재현(게이트 DENY · 착지 0)" $?
land "$LAND" 2 --approve-sha "$A2"
[ "$rc" = 0 ] && [[ "$out" == *"$AUTO"* ]] && [ "$(oshow bin/z.sh)" = "echo z2-main" ] && [ "$(oshow design/x/a2.md)" = PR-A2 ]; ck "ⓐ R2 → 착지 rc0 · z.sh = main 판(되돌림 0)" $?

# ===== R3: main 이 같은 파일 a.md 를 앞서 고침 → REJECT «같은 파일» =====
mkpr 3 doc3 "design/x/a.md=PR3-A"; A3="$PRSHA"; adv "design/x/a.md=MAIN3-A"; M3="$(omain)"
land "$LAND" 3 --approve-sha "$A3"
[ "$rc" = 1 ] && [[ "$out" == *"같은 파일 design/x/a.md(사람 최신화)"* ]] && [ "$(omain)" = "$M3" ] && [ ! -s "$STUB_LOG" ]; ck "ⓑ R3 → REJECT «같은 파일 design/x/a.md» · main 불변 · PR 쓰기 0" $?

# ===== R4·R5·R9: 코드 포함 · .md 아님 · 이름 바꾸기 → 지금 REJECT 그대로 · 변이 ⓒ(--no-renames 제거) =====
notauto() { [ "$rc" = 1 ] && [[ "$out" == *"$STALE"* ]] && [[ "$out" != *"$AUTO"* ]] && [ "$(omain)" = "$1" ]; }
mkpr 4 doc4 "design/x/c.md=PR4" "bin/q4.sh=echo q4"; A4="$PRSHA"; adv "design/y/d4.md=M4"; M4="$(omain)"
land "$LAND" 4 --approve-sha "$A4"; notauto "$M4"; ck "ⓒ R4 코드 1개 포함 → 지금 REJECT 그대로(최신화 먼저 · 자동 병합 0)" $?
mkpr 5 doc5 "design/x/a.json={}"; A5="$PRSHA"; adv "design/y/d5.md=M5"; M5="$(omain)"
land "$LAND" 5 --approve-sha "$A5"; notauto "$M5"; ck "ⓒ R5 design/ 아래 .json → 지금 REJECT 그대로" $?
adv "bin/q.sh=echo q-original-body-long-enough-for-rename"; git -C "$W" checkout -q -B doc9 origin/main; mkdir -p "$W/design/x"; git -C "$W" mv bin/q.sh design/x/q.md; cm "$W" "pr 9 rename"; pushpr 9 doc9; A9="$PRSHA"
adv "design/y/d9.md=M9"; M9="$(omain)"
land "$LAND" 9 --approve-sha "$A9"; notauto "$M9"; ck "ⓒ R9 이름 바꾸기 bin/q.sh→design/x/q.md → 지금 REJECT 그대로(--no-renames 가 bin/q.sh 를 잡음)" $?
MUTR="$(mut renames 'pf="$(G diff --no-renames' 'pf="$(G -c diff.renames=true diff -M')"
land "$MUTR/ft-merge-land.sh" 9 --approve-sha "$A9"
! notauto "$M9" && [[ "$out" == *"$AUTO"* ]]; ck "ⓒ 변이(--no-renames 제거) → R9 FAIL 재현(이름 바꾸기가 문서로 보여 자동 병합)" $?

# ===== R6: C 가 main 이 더한 줄을 지우는 꼴(변이 픽스처: C 트리 = S 트리) → 줄 계약 ④ 가 C 기준으로 DENY · 변이 ⓓ(부모 순서 뒤집기) =====
TREE_OLD='S="$(G commit-tree "${t%%$'"'"'\n'"'"'*}" -p "$S0" -p "$m"'
MUT6="$(mut tree-s "$TREE_OLD" 'S="$(G commit-tree "$S0^{tree}" -p "$S0" -p "$m"')"
MUT6R="$(mut tree-s-rev "$TREE_OLD" 'S="$(G commit-tree "$S0^{tree}" -p "$m" -p "$S0"')"
mkpr 6 doc6 "design/x/r6.md=PR6"; A6="$PRSHA"; adv "a.txt=MAIN6-LINE"; M6="$(omain)"
r6() { [ "$rc" = 1 ] && [[ "$out" == *"게이트(main 자동 병합 C="* ]] && [[ "$out" == *"main 이 더한 줄을 지움"* ]] && [ "$(omain)" = "$M6" ]; }
land "$MUT6/ft-merge-land.sh" 6 --approve-sha "$A6"; r6; ck "ⓓ R6(C 트리 = S 트리 픽스처) → 줄 계약 ④ 가 C 기준(첫 부모 사슬)으로 DENY · 착지 0" $?
land "$MUT6R/ft-merge-land.sh" 6 --approve-sha "$A6"; ! r6 && [ "$(omain)" = "$M6" ]; ck "ⓓ 변이(C 부모 순서 M·S = F==M 빈 검사) → R6 FAIL 재현(줄 계약이 못 봄)" $?
git -C "$W" fetch -q origin; land "$LAND" 6 --approve-sha "$A6"
[ "$rc" = 0 ] && [ "$(oshow a.txt)" = MAIN6-LINE ] && [ "$(oshow design/x/r6.md)" = PR6 ]; ck "ⓓ R6 같은 PR 을 정상 판으로 → 착지 rc0 · main 이 더한 줄 보존" $?

# ===== R7: main 이 후보를 이미 포함(정상 길) → 이 분기 안 탐 · Q 트리 == S 트리 =====
mkpr 7 doc7 "design/x/r7.md=PR7"; A7="$PRSHA"; M7="$(omain)"
land "$LAND" 7 --approve-sha "$A7"
[ "$rc" = 0 ] && [[ "$out" != *"$AUTO"* ]] && [ "$(sha "$ORIGIN" 'main^{tree}')" = "$(sha "$W" "$A7^{tree}")" ] && [ "$(sha "$ORIGIN" main^)" = "$M7" ] \
  && ! git -C "$ORIGIN" log -1 --format=%B main | grep -qF "자동 병합" && ! tail -n1 "$T/state/merge-gate.log" | grep -q doc-auto-merge
ck "ⓔ R7 정상 길 → 자동 병합 줄 0 · Q 트리 == S 트리 · 메시지·log 꼬리 0" $?

# ===== R8: 승인 A ≠ PR head S(승인 뒤 push) + main 앞섬 → 이 길 0 · 지금 REJECT 그대로 =====
mkpr 8 doc8 "design/x/r8.md=PR8"; A8="$PRSHA"; put design/x/r8b.md PR8B; cm "$W" "pr 8 more"; pushpr 8 doc8; adv "design/y/d8.md=M8"; M8="$(omain)"
land "$LAND" 8 --approve-sha "$A8"; notauto "$M8"; ck "ⓔ R8 승인 sha ≠ head → 자동 병합 0 · 지금 사유 그대로" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
