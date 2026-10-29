#!/usr/bin/env bash
# test_merge_land_doc_exempt_auto_merge_r1141.sh — r1141: 승인 값 없이 «문서 면제» 로 착지하는 PR 도 main 이 앞서면 r1121 자동 병합 C 를 탄다(재승인 0)
#   반례 R1~R5(카드 동결 집합) + 안전 대조 R1x(면제 아닌 문서 PR · 승인 없음 → C 를 만들어도 문서 면제 판정이 C 에서 거절) · 변이 1(조건 되돌림) · 기준판(r1141 직전 main 고정 sha 판 = REJECT · r1132)
#   임시 origin(bare)+clone · gh·tmux 는 스텁 — 실 gh·실 원격·실 push 0 · 자기 재호출은 real_state_guard 의 RSG_ACTIVE 재진입 표지 하나뿐
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T_START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:500}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SEAT='byz-planner-master-claude#105'   # 문서 면제 판정 좌석(임시 명부의 planner _master · test_doc_exempt_r725.sh 꼴)
mkrepo "$T"; mkdir -p "$T/state" "$W/.fable-team" "$T/fakebin"
printf '.fable-team/\n' >> "$W/.git/info/exclude"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$SEAT" "$W/.fable-team/seats-planner.json"
printf '#!/bin/bash\n[ "$1" = display-message ] && { printf "%%s" "%s"; exit 0; }\nexit 1\n' "$SEAT" > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
export FT_ROOT="$W" FT_AUTONOMY_STATE_DIR="$T/state" FT_SEAT="$SEAT" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_MERGE_DENY_FILE="$T/deny.txt" FT_INSTALL_CHECK="$T/install-stub"
export TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
printf '# 시험 목록(빈)\n' > "$T/deny.txt"; printf '#!/bin/bash\nexit 0\n' > "$T/install-stub"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub" "$T/install-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
oshow() { git -C "$ORIGIN" show "main:$1" 2>/dev/null; }
put() { mkdir -p "$(dirname "$W/$1")"; printf '%s\n' "$2" > "$W/$1"; }
mkpr() {  # mkpr <PR번호> <가지> <경로=내용>... — origin/main 에서 가지를 따 파일을 쓰고 PR ref·JSON 작성
  local n="$1" b="$2"; shift 2; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"; pushpr "$n" "$b"
}
pushpr() {
  git -C "$W" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"docs: PR "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" > "$STUB_JSON"
}
adv() {  # adv <경로=내용>... — PR 을 딴 «뒤» main 이 앞섬(다른 팀 착지 흉내 · origin 에 직접)
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B main origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "main adv"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
}
land() { local b="$1"; shift; apv "$@"; : > "$STUB_LOG"; out="$(bash "$b" "$@" --repo "$W" 2>&1)"; rc=$?; }
napv() { ls "$T/state/autonomy-merge-approved" 2>/dev/null | grep -c .; }   # 승인 파일 수(재승인 0 확인)
binof() {  # binof <폴더> <ft-merge-land.sh 내용 출처 파일> → 나머지 bin 은 심링크인 사본 폴더
  mkdir -p "$1"; for f in "$BIN"/*; do ln -s "$f" "$1/$(basename "$f")"; done; rm -f "$1/ft-merge-land.sh"; cp "$2" "$1/ft-merge-land.sh"
}
AUTO="INFO 문서 PR main 자동 병합 C="; STALE="ft-head-sync.sh 로 최신화 먼저"
notauto() { [ "$rc" = 1 ] && [[ "$out" == *"$STALE"* ]] && [[ "$out" != *"$AUTO"* ]] && [ "$(omain)" = "$1" ]; }

# ===== 사전: 문법 · 줄 수 상한 · 짝 사본(ⓒ) =====
bash -n "$LAND"; ck "bash -n ft-merge-land.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 상한 유지)" $?
cmp -s "$LAND" "$KIT/ft-merge-land.sh"; ck "ⓒ 짝 사본 bin·kit cmp0" $?

# ===== 기준판 + 변이 + R1: 승인 값 없음 · 문서 면제 PR · main 이 다른 문서 1커밋 앞섬 =====
mkpr 1 doc1 "design/teams/planner/HANDOFF-r1.md=PR-1"; P1="$PRSHA"; adv "design/teams/planner/NOTE-main1.md=MAIN-1"; M1="$(omain)"
# 기준판 = r1141 착지 a965e948d7 의 첫 부모 고정 sha(r1132 — origin/main 은 착지 뒤 새 코드가 된다) · 경로는 실경로(/var↔/private/var)
BASE_SHA=32b8c0a0bf654f24a6bb558cc23b28f88ed01cc4
TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" && pwd -P)"; PFX="$(cd "$HERE/.." && pwd -P)"; PFX="${PFX#$TOP/}"
HAVE_BASE=0; [ -n "$TOP" ] && git -C "$TOP" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null && HAVE_BASE=1
if [ "$HAVE_BASE" = 1 ]; then
  git -C "$TOP" show "$BASE_SHA:$PFX/kit/fable-team/bin/ft-merge-land.sh" > "$T/red.sh" && [ -s "$T/red.sh" ] || { echo "FAIL 기준판을 못 꺼냄"; exit 1; }
  binof "$T/red" "$T/red.sh"
  land "$T/red/ft-merge-land.sh" 1; notauto "$M1"; ck "기준판(r1141 직전 main 판): R1 → REJECT «최신화 먼저» · main 불변(사람 왕복 재현)" $?
else echo "SKIP 기준판 칸(R1 REJECT 재현) — base_sha $BASE_SHA 객체 없음(git 사본 아님 · git archive 사본)"; fi
python3 - "$LAND" "$T/mut.sh" <<'PY' || { echo "FAIL 변이 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); old = '{ [ -z "$AP" ] || [ "$AP" = "$S" ]; }'
assert old in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, '[ -n "$AP" ] && [ "$AP" = "$S" ]', 1))
PY
binof "$T/mut" "$T/mut.sh"
land "$T/mut/ft-merge-land.sh" 1; notauto "$M1"; ck "ⓐ 변이(조건 되돌림 = 승인 값 필수) → R1 REJECT = FAIL 재현 · main 불변" $?
land "$LAND" 1
[ "$rc" = 0 ] && [[ "$out" == *"$AUTO"* ]] && [[ "$out" == *"LANDED pr=1 "* ]] && [ "$(oshow design/teams/planner/HANDOFF-r1.md)" = PR-1 ] \
  && [ "$(oshow design/teams/planner/NOTE-main1.md)" = MAIN-1 ] && [ "$(sha "$ORIGIN" main^)" = "$M1" ]
ck "ⓐ R1 → 착지 rc0 · INFO 자동 병합 줄 · PR 문서·main 문서 둘 다 · squash 1커밋(부모 = 앞선 main)" $?
tail -n1 "$T/state/merge-gate.log" | grep -q " doc-exempt=yes team=planner files=1 by=$SEAT doc-auto-merge=$P1" && [ "$(napv)" = 0 ] \
  && git -C "$ORIGIN" log -1 --format=%B main | grep -qF "PR #1 (head $P1)" && grep -q "^doc-exempt [0-9a-f]\{40\} team=planner files=1 by=$SEAT$" "$T/state/autonomy.log"
ck "ⓐ R1 기록: merge-gate.log doc-exempt=yes(files=1 = PR 문서만) + doc-auto-merge · 승인 파일 0(재승인 0) · 끝줄 PR head" $?

# ===== R1x(안전 대조): 승인 없음 · design/ .md 지만 문서 면제 아님(팀 폴더 밖) · main 앞섬 → C 는 만들어도 61행 면제 판정이 거절 =====
mkpr 11 doc11 "design/x/b.md=PR-11"; adv "design/teams/planner/NOTE-main11.md=MAIN-11"; M11="$(omain)"
land "$LAND" 11
[ "$rc" = 1 ] && [[ "$out" == *"승인 파일 없음 · doc-exempt 아님"* ]] && [ "$(omain)" = "$M11" ] && [ ! -s "$STUB_LOG" ]
ck "ⓑ R1x 면제 아닌 문서 PR · 승인 없음 → «승인 파일 없음 · doc-exempt 아님» REJECT · main 불변 · PR 쓰기 0" $?

# ===== R2: 승인 없음 · 문서 PR · main 이 같은 파일을 바꿈 → «같은 파일» REJECT =====
mkpr 2 doc2 "design/teams/planner/HANDOFF-r2.md=PR-2"; adv "design/teams/planner/HANDOFF-r2.md=MAIN-2"; M2="$(omain)"
land "$LAND" 2
[ "$rc" = 1 ] && [[ "$out" == *"같은 파일 design/teams/planner/HANDOFF-r2.md(사람 최신화)"* ]] && [ "$(omain)" = "$M2" ] && [ ! -s "$STUB_LOG" ]
ck "ⓑ R2 → REJECT «같은 파일 …(사람 최신화)» · main 불변 · PR 쓰기 0" $?

# ===== R3: 승인 없음 · 코드 파일 1개 섞임 · main 앞섬 → docam 대상 아님 · 지금 REJECT 그대로 =====
mkpr 3 doc3 "design/teams/planner/HANDOFF-r3.md=PR-3" "bin/q3.sh=echo q3"; adv "design/teams/planner/NOTE-main3.md=MAIN-3"; M3="$(omain)"
land "$LAND" 3; notauto "$M3"; ck "ⓑ R3 코드 1개 섞임 → 지금 REJECT 그대로(최신화 먼저 · 자동 병합 0)" $?

# ===== R4: 승인 값 있음 · 승인 ≠ PR head(승인 뒤 push) · main 앞섬 → 지금 그대로 =====
mkpr 4 doc4 "design/teams/planner/HANDOFF-r4.md=PR-4"; A4="$PRSHA"; put design/teams/planner/HANDOFF-r4b.md PR-4B; cm "$W" "pr 4 more"; pushpr 4 doc4
adv "design/teams/planner/NOTE-main4.md=MAIN-4"; M4="$(omain)"
land "$LAND" 4 --approve-sha "$A4"; notauto "$M4"; ck "ⓑ R4 승인 sha ≠ head → 자동 병합 0 · 지금 사유 그대로" $?

# ===== R5: 승인 없음 · 문서 면제 PR · main 안 앞섬 → 지금 그대로 착지(자동 병합 줄 0) =====
mkpr 5 doc5 "design/teams/planner/HANDOFF-r5.md=PR-5"; P5="$PRSHA"; M5="$(omain)"
land "$LAND" 5
[ "$rc" = 0 ] && [[ "$out" != *"$AUTO"* ]] && [[ "$out" == *"LANDED pr=5 "* ]] && [ "$(sha "$ORIGIN" 'main^{tree}')" = "$(sha "$W" "$P5^{tree}")" ] && [ "$(sha "$ORIGIN" main^)" = "$M5" ] \
  && tail -n1 "$T/state/merge-gate.log" | grep -q " doc-exempt=yes " && ! tail -n1 "$T/state/merge-gate.log" | grep -q doc-auto-merge
ck "ⓐ R5 정상 길 → 착지 rc0 · 자동 병합 줄 0 · Q 트리 == PR 트리 · doc-exempt=yes · doc-auto-merge 0" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]] && [ "$(napv)" = 1 ]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0) · 승인 파일 = R4 의 1개뿐" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
