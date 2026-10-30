#!/usr/bin/env bash
# test_merge_land_docam_evidence_r1181.sh — r1181: 문서 PR main 자동 병합(docam)이 design/**/evidence/ 아래 비코드 증거(txt·json·jsonl·log·out·csv·tsv·png·jpg·jpeg)도 받는다
#   반례 R1~R6(카드 동결 집합) · 변이 1(EVID_RE 끔 → R1 REJECT) · 기준판(r1181 직전 main 고정 sha 판 = R1 REJECT)
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
notauto() { [ "$rc" = 1 ] && [[ "$out" == *"$STALE"* ]] && [[ "$out" != *"$AUTO"* ]] && [ "$(omain)" = "$1" ]; }
EV=design/teams/t/evidence

# ===== 사전: 문법 · 줄 수 상한 · 짝 사본 =====
bash -n "$LAND"; ck "bash -n ft-merge-land.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 상한 유지)" $?
cmp -s "$LAND" "$KIT/ft-merge-land.sh"; ck "ⓔ 짝 사본 bin·kit cmp0" $?
echo "단계 초: 사전 $((SECONDS - T_START))s"

# ===== 기준판 + 변이 + R1: 증거 PR(RESULT.md + a.json) · main 이 다른 문서 1커밋 앞섬 · 승인 == head =====
mkpr 1 ev1 "$EV/x/RESULT.md=R1" "$EV/x/a.json={\"r\":1}"; A1="$PRSHA"; adv "design/y/b.md=MAIN-B"; M1="$(omain)"
BASE_SHA=f1a77fb8d1ec2fc7846d83d89b89667da3e3ed38   # r1181 직전 팩 origin/main(고정 sha — 착지 뒤 origin/main 은 새 코드가 된다)
TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" && pwd -P)"; PFX="$(cd "$HERE/.." && pwd -P)"; PFX="${PFX#$TOP/}"; mkdir -p "$T/red"
if [ -n "$TOP" ] && git -C "$TOP" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  for f in "$BIN"/*; do ln -s "$f" "$T/red/$(basename "$f")"; done; rm -f "$T/red/ft-merge-land.sh"
  git -C "$TOP" show "$BASE_SHA:$PFX/kit/fable-team/bin/ft-merge-land.sh" > "$T/red/ft-merge-land.sh" && [ -s "$T/red/ft-merge-land.sh" ] || { echo "FAIL 기준판을 못 꺼냄"; exit 1; }
  land "$T/red/ft-merge-land.sh" 1 --approve-sha "$A1"; notauto "$M1"
  ck "기준판(r1181 직전 main 판): R1 → REJECT «최신화 먼저» · main 불변(승인 다시 받기 재현)" $?
else echo "SKIP 기준판 칸(R1 REJECT 재현) — base_sha $BASE_SHA 객체 없음(git 사본 아님)"; fi
MUTE="$(mut evid-off '-e "$DOC_RE" -e "$EVID_RE"' '-e "$DOC_RE"')"
land "$MUTE/ft-merge-land.sh" 1 --approve-sha "$A1"; notauto "$M1"; ck "ⓐ 변이(EVID_RE 끔) → R1 FAIL 재현(REJECT 그대로 · main 불변)" $?
land "$LAND" 1 --approve-sha "$A1"
[ "$rc" = 0 ] && [[ "$out" == *"$AUTO"* ]] && [[ "$out" == *"증거 비 .md 1개"* ]] && [[ "$out" == *"LANDED pr=1 "* ]] && [ "$(oshow "$EV/x/a.json")" = '{"r":1}' ] && [ "$(oshow design/y/b.md)" = MAIN-B ] && [ "$(sha "$ORIGIN" main^)" = "$M1" ]
ck "ⓐ R1 → 착지 rc0 · INFO 자동 병합 줄(증거 비 .md 1개) · a.json(PR 판)·b.md(main 판) 둘 다 · 부모 = 앞선 main" $?
[ "$(ls "$T/state/autonomy-merge-approved" | grep -c .)" = 1 ] && [ -f "$T/state/autonomy-merge-approved/$A1" ] && tail -n1 "$T/state/merge-gate.log" | grep -q " doc-auto-merge=$A1"
ck "ⓐ R1 재승인 0(승인 파일 = A 1개) · merge-gate.log doc-auto-merge 칸" $?
echo "단계 초: 기준판+변이+R1 $((SECONDS - T_START))s"

# ===== R2: R1 꼴 + shot.png(바이너리) → 자동 병합 + 착지 · png 바이트 그대로 =====
mkpr 2 ev2 "$EV/r2/RESULT.md=R2" "$EV/r2/a.json={}"; printf '\x89PNG\r\n\x1a\n\x00\x01\xff\xfe' > "$W/$EV/r2/shot.png"; cm "$W" "pr 2 png"; pushpr 2 ev2; A2="$PRSHA"
adv "design/y/b2.md=MAIN-B2"
land "$LAND" 2 --approve-sha "$A2"
[ "$rc" = 0 ] && [[ "$out" == *"$AUTO"* ]] && [[ "$out" == *"증거 비 .md 2개"* ]] && [ "$(sha "$ORIGIN" "main:$EV/r2/shot.png")" = "$(sha "$W" "$A2:$EV/r2/shot.png")" ]
ck "ⓐ R2 바이너리 png 포함 → 착지 rc0 · png 바이트 같음 · 증거 비 .md 2개" $?

# ===== R3·R4: evidence 아래 코드 확장자 · evidence 밖 .json → 지금 REJECT 그대로 =====
mkpr 3 ev3 "$EV/r3/RESULT.md=R3" "$EV/r3/run.sh=echo r3"; A3="$PRSHA"; adv "design/y/b3.md=M3"; M3="$(omain)"
land "$LAND" 3 --approve-sha "$A3"; notauto "$M3"; ck "ⓑ R3 evidence 아래 run.sh → REJECT 게이트 그대로(자동 병합 0 · main 불변)" $?
mkpr 4 ev4 "design/teams/t/notes/a.json={}"; A4="$PRSHA"; adv "design/y/b4.md=M4"; M4="$(omain)"
land "$LAND" 4 --approve-sha "$A4"; notauto "$M4"; ck "ⓑ R4 evidence 밖 notes/a.json → REJECT 게이트 그대로" $?

# ===== R5: main 도 같은 a.json 을 바꿈 → REJECT «같은 파일» =====
mkpr 5 ev5 "$EV/r5/RESULT.md=R5" "$EV/r5/a.json={\"pr\":5}"; A5="$PRSHA"; adv "$EV/r5/a.json={\"main\":5}"; M5="$(omain)"
land "$LAND" 5 --approve-sha "$A5"
[ "$rc" = 1 ] && [[ "$out" == *"같은 파일 $EV/r5/a.json(사람 최신화)"* ]] && [ "$(omain)" = "$M5" ] && [ ! -s "$STUB_LOG" ]; ck "ⓒ R5 → REJECT «같은 파일 …/a.json» · main 불변 · PR 쓰기 0" $?

# ===== R6: 승인 sha ≠ head(승인 뒤 push) + main 앞섬 → docam 0 · 지금 REJECT 그대로 =====
mkpr 6 ev6 "$EV/r6/RESULT.md=R6" "$EV/r6/a.json={}"; A6="$PRSHA"; put "$EV/r6/b.txt" more; cm "$W" "pr 6 more"; pushpr 6 ev6; adv "design/y/b6.md=M6"; M6="$(omain)"
land "$LAND" 6 --approve-sha "$A6"; notauto "$M6"; ck "ⓓ R6 승인 sha ≠ head → 자동 병합 0 · 지금 사유 그대로" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
