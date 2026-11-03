#!/usr/bin/env bash
# test_merge_land_code_automerge_r1270.sh — r1270: 승인 sha 가 있는 코드 PR 도 main 이 앞서면 ft-merge-land 가 같은 실행 안에서 C(첫 부모 S · 둘째 M)로 착지
#   반례 R1~R8(카드 동결) + R5b(승인 안 된 커밋이 섞인 head → EQUIV 가 막음) · 변이 4 · 임시 origin(bare)+clone · gh 는 스텁 — 실 gh·실 원격·실 push 0
#   자기 재호출은 real_state_guard 의 RSG_ACTIVE 재진입 표지 하나뿐 · 고정 sleep 0 · 네트워크 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset FT_MERGE_LAND_CODE_AUTOMERGE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T_START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
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
heads() { git -C "$ORIGIN" for-each-ref --format='%(refname)' refs/heads | tr '\n' ' '; }
put() { mkdir -p "$(dirname "$W/$1")"; printf '%s\n' "$2" > "$W/$1"; }   # put <경로> <내용>
pushpr() {  # pushpr <PR번호> <가지> — 지금 가지 HEAD 를 PR head 로(강제) · JSON 갱신
  git -C "$W" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"feat: PR "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" > "$STUB_JSON"
}
mkpr() {  # mkpr <PR번호> <가지> <경로=내용>... — origin/main 에서 가지를 따 파일을 쓰고 PR ref·JSON 작성
  local n="$1" b="$2"; shift 2; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"; pushpr "$n" "$b"
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
M_AP="$(mut ap-gate '[ -z "$AP" ] || [ "${FT_MERGE_LAND_CODE_AUTOMERGE:-1}" = 0 ] || CAMOK=1;' '[ "${FT_MERGE_LAND_CODE_AUTOMERGE:-1}" = 0 ] || CAMOK=1;')"
M_EQ="$(mut equiv-skip 'bash "$HERE/ft-approval-equiv.sh" "$AP" "$S"' "bash -c 'echo EQUIV approve=x head=x merges=1 files=0 mode=merge overlap=0 base=x' --")"
M_CODE="$(mut code-branch 'elif [ "$CAMOK" = 1 ]; then CAM="코드"' 'elif false; then CAM="코드"')"
M_OV="$(mut overlap-check '|| [ "$OV" = 0 ] ||' '|| true ||')"
AUTOC="INFO main 자동 병합(코드 · 승인 EQUIV 대상) C="; AUTOD="INFO 문서 PR main 자동 병합 C="; NOTDOC="문서 자동 병합 대상 아님"
rejected() { [ "$rc" = 1 ] && [[ "$out" != *LANDED* ]] && [[ "$out" == *"REJECT "* ]] && [ "$(omain)" = "$1" ]; }   # rejected <시험 전 main> — REJECT 줄 · 착지 0 · main 불변(INFO 자동 병합 줄은 REJECT 앞에 찍힐 수 있다)

# ===== 사전: 문법 · 줄 수 상한 · 짝 사본 =====
bash -n "$LAND"; ck "bash -n ft-merge-land.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 상한 유지)" $?
cmp -s "$LAND" "$KIT/ft-merge-land.sh"; ck "짝 사본 bin·kit cmp0" $?

# ===== R1: 승인된 코드 PR · head == 승인 sha · main 2커밋 앞섬(겹침 0) → 자동 병합 · EQUIV merges=1 overlap=0 · LANDED · PR 가지 push 0 =====
mkpr 1 c1 "bin/x1.sh=echo x1"; A1="$PRSHA"; adv "bin/y1a.sh=echo y1a"; adv "bin/y1b.sh=echo y1b"; M1="$(omain)"; H1="$(heads)"
land "$LAND" 1 --approve-sha "$A1"
[ "$rc" = 0 ] && [[ "$out" == *"$AUTOC"* ]] && [[ "$out" == *"merges=1"* && "$out" == *"overlap=0"* ]] && [[ "$out" == *"LANDED pr=1 "* ]] \
  && [ "$(oshow bin/x1.sh)" = "echo x1" ] && [ "$(oshow bin/y1a.sh)" = "echo y1a" ] && [ "$(oshow bin/y1b.sh)" = "echo y1b" ] && [ "$(sha "$ORIGIN" main^)" = "$M1" ]
ck "R1 → rc0 · INFO 코드 자동 병합 · EQUIV merges=1 overlap=0 · LANDED · 세 파일 다 main 에 · squash 1커밋(부모 = 앞선 main)" $?
[ "$(heads)" = "$H1" ] && [ "$(sha "$ORIGIN" refs/pull/1/head)" = "$A1" ]; ck "R1 PR 가지 push 0(원격 heads 불변 · PR head = 승인 sha)" $?
git -C "$ORIGIN" log -1 --format=%B main | grep -qF "main 자동 병합(코드 · 승인 EQUIV) C=" && grep -qF "main 자동 병합(코드 · 승인 EQUIV) C=" "$STUB_LOG" && git -C "$ORIGIN" log -1 --format=%B main | grep -qF "PR #1 (head $A1)"
ck "R1 표기: 착지 커밋 끝줄 · PR 코멘트 «main 자동 병합(코드 · 승인 EQUIV) C=»" $?

# ===== R2: R1 인데 main 이 같은 파일을 바꿈(겹침 1) → REJECT · 착지 0 =====
mkpr 2 c2 "bin/f2.sh=PR2"; A2="$PRSHA"; adv "bin/f2.sh=MAIN2"; M2="$(omain)"
land "$LAND" 2 --approve-sha "$A2"
rejected "$M2" && [[ "$out" == *"코드 PR 자동 병합 불가: 같은 파일 bin/f2.sh(사람 최신화)"* ]] && [ ! -s "$STUB_LOG" ]; ck "R2 같은 파일 겹침 → REJECT «같은 파일 bin/f2.sh» · main 불변 · PR 쓰기 0" $?

# ===== R3: merge-tree 충돌(파일 vs 폴더 · 같은 파일 이름 대조는 비켜 감) → REJECT «충돌» =====
mkpr 3 c3 "bin/d3=PR3-FILE"; A3="$PRSHA"; adv "bin/d3/x.sh=echo MAIN3-DIR"; M3="$(omain)"
land "$LAND" 3 --approve-sha "$A3"
rejected "$M3" && [[ "$out" == *"코드 PR 자동 병합 불가: merge-tree 충돌(사람 최신화)"* ]]; ck "R3 merge-tree 충돌 → REJECT «충돌» · main 불변" $?

# ===== R4: 승인 sha 없음 · 코드 PR → 지금 REJECT «비 .md N개» (코드 자동 병합 0) =====
mkpr 4 c4 "bin/x4.sh=echo x4"; A4="$PRSHA"; adv "bin/y4.sh=echo y4"; M4="$(omain)"
: > "$STUB_LOG"; out="$(bash "$LAND" 4 --repo "$W" 2>&1)"; rc=$?
rejected "$M4" && [[ "$out" == *"비 .md 1개: bin/x4.sh"* && "$out" == *"$NOTDOC"* ]]; ck "R4 승인 sha 없음 · 코드 PR → REJECT «비 .md 1개 … 문서 자동 병합 대상 아님» · 자동 병합 0" $?
: > "$STUB_LOG"; out="$(bash "$M_AP/ft-merge-land.sh" 4 --repo "$W" 2>&1)"; rc=$?
! { rejected "$M4" && [[ "$out" == *"비 .md 1개: bin/x4.sh"* ]]; }; ck "변이 1(승인 조건 제거) → R4 FAIL 재현(사유 문구가 바뀜)" $?
land "$M_CODE/ft-merge-land.sh" 4 --approve-sha "$A4"
rejected "$M4" && [[ "$out" == *"비 .md 1개: bin/x4.sh"* ]]; ck "변이 3(코드 갈래 제거) → R1 꼴 FAIL 재현(승인 sha 가 있어도 착지 0)" $?
land "$LAND" 4 --approve-sha "$A4"; r4ap=0; [ "$rc" = 0 ] && [[ "$out" == *"$AUTOC"* ]] && r4ap=1
[ "$r4ap" = 1 ]; ck "R4 대조: 같은 PR 에 승인 sha 를 주면 착지(길이 승인 sha 에만 열림)" $?

# ===== R5: 사람이 이미 main 을 1회 병합한 head(S ≠ 승인 sha) · main 이 또 앞섬 → C = merge(S, main) · EQUIV(승인 → C) 가 판정 =====
mkpr 5 c5 "bin/x5.sh=echo x5"; A5="$PRSHA"; adv "bin/y5a.sh=echo y5a"
git -C "$W" checkout -q c5; git -C "$W" merge -q --no-edit origin/main; pushpr 5 c5; S5="$PRSHA"; adv "bin/y5b.sh=echo y5b"; M5="$(omain)"
land "$LAND" 5 --approve-sha "$A5"
[ "$S5" != "$A5" ] && [ "$rc" = 0 ] && [[ "$out" == *"$AUTOC"* ]] && [[ "$out" == *"LANDED pr=5 "* ]] && [ "$(oshow bin/x5.sh)" = "echo x5" ] && [ "$(oshow bin/y5a.sh)" = "echo y5a" ] && [ "$(oshow bin/y5b.sh)" = "echo y5b" ]
ck "R5 head(S ≠ 승인) = 사람 병합 1회 · main 또 앞섬 → C 착지(EQUIV 가 받음) · 세 파일 다 main 에" $?

# ===== R5b(추가): head 에 «승인 안 된 커밋» 이 섞임 · main 앞섬 → EQUIV 가 막음 · 착지 0 =====
mkpr 55 c55 "bin/x55.sh=echo x55"; A55="$PRSHA"; put bin/extra55.sh "echo UNAPPROVED"; cm "$W" "pr 55 extra"; pushpr 55 c55; adv "bin/y55.sh=echo y55"; M55="$(omain)"
land "$LAND" 55 --approve-sha "$A55"
rejected "$M55" && [[ "$out" == *"동일승인 대조"* ]] && [ -z "$(oshow bin/extra55.sh)" ]; ck "R5b 승인 안 된 커밋이 섞인 head → REJECT «동일승인 대조 실패» · extra55.sh 가 main 에 안 올라감" $?
land "$M_EQ/ft-merge-land.sh" 55 --approve-sha "$A55"; [ "$rc" = 0 ] && [ "$(oshow bin/extra55.sh)" = "echo UNAPPROVED" ]; ck "변이 2(EQUIV 생략) → R5b FAIL 재현(승인 안 된 코드가 착지)" $?

# ===== R6: env FT_MERGE_LAND_CODE_AUTOMERGE=0 → R1 꼴이 지금처럼 REJECT =====
mkpr 6 c6 "bin/x6.sh=echo x6"; A6="$PRSHA"; adv "bin/y6.sh=echo y6"; M6="$(omain)"
FT_MERGE_LAND_CODE_AUTOMERGE=0 land "$LAND" 6 --approve-sha "$A6"
rejected "$M6" && [[ "$out" == *"ft-head-sync.sh 로 최신화 먼저"* && "$out" == *"$NOTDOC"* ]]; ck "R6 env=0 → R1 꼴이 지금처럼 REJECT(최신화 먼저 · 비 .md 사유 · main 불변)" $?
land "$LAND" 6 --approve-sha "$A6"; [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=6 "* ]]; ck "R6 대조: env 없이 같은 PR → 착지" $?

# ===== R7: 문서 PR → 지금 docam 그대로(문구·커밋 메시지 doc-only · 코드 문구 0) =====
mkpr 7 c7 "design/x/r7.md=PR7"; A7="$PRSHA"; adv "design/y/r7b.md=M7"; M7="$(omain)"
land "$LAND" 7 --approve-sha "$A7"
[ "$rc" = 0 ] && [[ "$out" == *"$AUTOD"* && "$out" != *"$AUTOC"* ]] && git -C "$ORIGIN" log -1 --format=%B main | grep -qF "main 자동 병합(문서 전용 · 겹침 0) C=" && ! git -C "$ORIGIN" log -1 --format=%B main | grep -qF "코드 · 승인" \
  && tail -n1 "$T/state/merge-gate.log" | grep -q " doc-auto-merge="; ck "R7 문서 PR → INFO «문서 PR main 자동 병합» · 메시지 «문서 전용 · 겹침 0» · log doc-auto-merge · 코드 문구 0" $?
mkpr 77 c77 "design/x/r77.md=PR77"; A77="$PRSHA"; put design/x/r77b.md MORE; cm "$W" "pr 77 more"; pushpr 77 c77; adv "design/y/r77c.md=M77"; M77="$(omain)"
land "$LAND" 77 --approve-sha "$A77"
rejected "$M77" && [[ "$out" == *"승인 sha ${A77:0:10} ≠ PR head"* ]]; ck "R7 문서 PR 인데 승인 sha ≠ head → 지금 사유 그대로 REJECT(코드 길은 코드가 있을 때만)" $?

# ===== R8(DA① 반례 1): 사람이 깨끗이 병합한 S(≠ 승인 A) · main 이 g8.py 만 또 바꿈 → EQUIV overlap=1 → REJECT =====
python3 -c 'print("\n".join("line%02d" % i for i in range(1, 31)))' > "$T/f8.txt"; adv "bin/f8.py=$(cat "$T/f8.txt")"
mkpr 8 c8 "bin/f8.py=$(sed '2s/.*/PR8-LINE2/' "$T/f8.txt")"; A8="$PRSHA"
adv "bin/f8.py=$(sed '28s/.*/MAIN8-LINE28/' "$T/f8.txt")"
git -C "$W" checkout -q c8; git -C "$W" merge -q --no-edit origin/main; pushpr 8 c8; S8="$PRSHA"; adv "bin/g8.py=print('g8')"; M8="$(omain)"
land "$LAND" 8 --approve-sha "$A8"
[ "$S8" != "$A8" ] && rejected "$M8" && [[ "$out" == *"승인 뒤 main 이 같은 파일 1개를 바꿈"* ]] && [[ "$out" == *"overlap=1"* ]]; ck "R8 병합 head S(≠승인) · EQUIV rc0 overlap=1 → REJECT «승인 뒤 main 이 같은 파일 1개를 바꿈» · 착지 0" $?
[[ "$out" == *"겹친 파일: bin/"* && "$out" == *"질문 관문 우회"* ]]; ck "R8b(r1275 단계 4 · V6) 같은 파일 REJECT 문구에 겹친 파일 이름 + «승인 sha 가 질문 때 main 위였나» 1줄" $?
land "$M_OV/ft-merge-land.sh" 8 --approve-sha "$A8"; [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=8 "* ]]; ck "변이 4(overlap=0 검사 제거) → R8 FAIL 재현(LANDED)" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
