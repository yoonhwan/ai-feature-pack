#!/usr/bin/env bash
# test_merge_land_head_ref_missing_r1127.sh — r1127: GitHub 가 refs/pull/N/head 를 안 만든 PR 의 착지(같은 리포만 가지로 받아 headRefOid 대조)
#   임시 origin(bare)+clone · gh 는 스텁 · git 대역은 fetch 인자만 기록(실 gh·실 원격 0) · 반례 R1~R7 + 변이 3
#   픽스처 꼴 = test_merge_land_fetch_sec.sh mkpr(여기서는 pull ref 를 «안» 올리는 갈래를 더함)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(RSG_ACTIVE 재진입 표지)
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: 레벨 밖(each) — 실 슬랙 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"; LIB="$BIN/ft-merge-lib.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/deny"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; echo "REJECT usage" >&2; exit 2;; esac
echo "$*" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
printf '# 시험 목록\n^big-r7$\t-\n' > "$T/deny/list.txt"; export FT_MERGE_DENY_FILE="$T/deny/list.txt"
FS="$T/shim"; FLOG="$T/fetch.log"; mkdir -p "$FS"; REAL_GIT="$(command -v git)"
cat > "$FS/git" <<EOF
#!/bin/bash
for a in "\$@"; do [ "\$a" = fetch ] && { echo "\$*" >> "$FLOG"; break; }; done
exec "$REAL_GIT" "\$@"
EOF
printf '#!/bin/bash\necho "ICHK $*"\n' > "$FS/ichk"; chmod +x "$FS/git" "$FS/ichk"   # 착지 뒤 설치 검사는 이 카드 밖
omain() { sha "$ORIGIN" refs/heads/main; }
brf() { grep -c '+refs/heads/' "$FLOG" | tr -d ' '; }   # 가지 갈래 fetch 시도 수
nolr() { [ -z "$(git -C "$W" for-each-ref refs/ft-land)" ]; }   # R6: 개인 ref 남음 0
# mkpr <번호> <가지> <pull|branch|both> <false|true|-> — PR 커밋 1개(origin/main 위) · pull ref·가지 올림 선택 · isCrossRepository 칸(- = 칸 없음)
mkpr() {
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$2" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"; PRSHA="$(sha "$W" HEAD)"
  case "$3" in pull|both) git -C "$W" push -q origin "$2:refs/pull/$1/head";; esac
  case "$3" in branch|both) git -C "$W" push -q origin "$2:refs/heads/$2";; esac
  python3 -c 'import json,sys;d={"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"feat: PR "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}
if sys.argv[4]!="-": d["isCrossRepository"]=(sys.argv[4]=="true")
print(json.dumps(d))' "$PRSHA" "$2" "$1" "$4" > "$STUB_JSON"
}
land() {  # land <land.sh> <PR> — 대역 PATH 로 착지(승인 = PRSHA)
  : > "$FLOG"; apv --approve-sha "$PRSHA"
  out="$(env PATH="$FS:$PATH" FT_INSTALL_CHECK="$FS/ichk" bash "$1" "$2" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
}
# 시나리오(변이 대조에 다시 쓴다) — 성립하면 rc0
r2() { mkpr "$1" "nano/r2-$1" branch false; land "$2" "$1"
  [ "$rc" = 0 ] && [[ "$out" == *"INFO PR #$1 head ref 없음 — 가지 nano/r2-$1 로 받음(headRefOid 대조)"* ]] && [[ "$out" == *LANDED* ]] && [ "$(git -C "$ORIGIN" rev-parse "refs/heads/main^{tree}")" = "$(git -C "$W" rev-parse "$PRSHA^{tree}")" ] && nolr; }
r3() { local M; mkpr "$1" "nano/r3-$1" branch false; echo moved > "$W/mv$1.txt"; cm "$W" "moved after gh view"; git -C "$W" push -q origin "nano/r3-$1:refs/heads/nano/r3-$1"; M="$(omain)"; land "$2" "$1"
  [ "$rc" = 1 ] && [[ "$out" == *"fetch 한 head("*") != PR head($PRSHA)"* ]] && [ "$(omain)" = "$M" ] && nolr; }
r5() { local M; mkpr "$1" "nano/r5-$1" branch true; M="$(omain)"; land "$2" "$1"
  [ "$rc" = 1 ] && [[ "$out" == *"REJECT PR head fetch 실패 (착지 0)"* ]] && [ "$(brf)" = 0 ] && [ "$(omain)" = "$M" ] && nolr; }

# ── ⓐ R1 — pull ref 있음(가지도 있음) = 지금과 같음 · 가지 fetch 0 ──
mkpr 101 nano/r1 both false; land "$LAND" 101
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && [[ "$out" != *"head ref 없음"* ]] && [ "$(brf)" = 0 ] && [ "$(grep -c '+pull/101/head' "$FLOG")" -ge 1 ] && nolr; ck "ⓐ R1 pull ref 있음 → 착지 rc0 · INFO 0 · 가지 fetch 0" $?
# ── ⓑ R2 — pull ref 없음 · 같은 리포 · 가지 head == headRefOid → INFO 1줄 + 착지 ──
r2 102 "$LAND"; ck "ⓑ R2 pull ref 없음 · 같은 리포 · oid 같음 → INFO 1줄 · 착지 rc0 · main 트리 = PR 트리 · 개인 ref 0" $?
# ── ⓒ R3 — 가지가 gh 조회 뒤 움직임 → oid 결속 REJECT ──
r3 103 "$LAND"; ck "ⓒ R3 가지 head != headRefOid → «fetch 한 head(…) != PR head(…)» REJECT · main 불변 · 개인 ref 0" $?
# ── ⓓ R4 — pull ref·가지 둘 다 없음 → 새 문구 REJECT ──
M4="$(omain)"; mkpr 104 nano/r4 none false; land "$LAND" 104
[ "$rc" = 1 ] && [[ "$out" == *"PR head fetch 실패(pull/104/head·가지 nano/r4 둘 다)"* ]] && [ "$(brf)" -ge 1 ] && [ "$(omain)" = "$M4" ] && nolr; ck "ⓓ R4 둘 다 없음 → «PR head fetch 실패(pull/104/head·가지 nano/r4 둘 다)» · main 불변 · 개인 ref 0" $?
# ── ⓓ2 R5 — 포크(isCrossRepository true) → 가지 fetch 0 · 지금 문구 ──
r5 105 "$LAND"; ck "ⓓ2 R5 포크 PR → 가지 fetch 0 · «PR head fetch 실패» REJECT · main 불변" $?
M5="$(omain)"; mkpr 106 nano/r5b branch -; land "$LAND" 106
[ "$rc" = 1 ] && [[ "$out" == *"REJECT PR head fetch 실패 (착지 0)"* ]] && [ "$(brf)" = 0 ] && [ "$(omain)" = "$M5" ]; ck "ⓓ3 R5 isCrossRepository 칸 없음 → 가지 fetch 0 · 지금 문구 REJECT" $?
# ── ⓖ R7 — 가지 갈래도 착지 금지 목록을 탄다 ──
M7="$(omain)"; mkpr 107 big-r7 branch false; land "$LAND" 107
[ "$rc" = 1 ] && [[ "$out" == *"head ref 없음 — 가지 big-r7"* ]] && [[ "$out" != *LANDED* ]] && [[ "$out" == *"착지 금지 가지(big-r7"* ]] && [ "$(omain)" = "$M7" ] && nolr; ck "ⓖ R7 금지 가지(^big-r7$) → 가지로 받은 뒤 deny REJECT · main 불변 · 개인 ref 0" $?

# ── ⓗ 변이 3 — 시나리오가 각 변이를 잡는다(변이본에서 시나리오 성립 = 시험 검출력 0) ──
mutd() { local d="$1"; mkdir -p "$d"; cp "$LAND" "$d/ft-merge-land.sh"; cp "$LIB" "$d/ft-merge-lib.sh"
  for f in "$BIN"/*; do local b; b="$(basename "$f")"; [ "$b" = ft-merge-land.sh ] || [ "$b" = ft-merge-lib.sh ] || ln -sf "$f" "$d/$b"; done; }
V1="$T/mut1"; mutd "$V1"; sed -i '' '/HBR="\$(fm_head_branch/d' "$V1/ft-merge-land.sh"   # 두 번째 갈래 삭제
! cmp -s "$LAND" "$V1/ft-merge-land.sh" && ! r2 201 "$V1/ft-merge-land.sh"; ck "ⓗ1 변이(두 번째 갈래 삭제) → R2 착지 0 = 시나리오 FAIL(검출)" $?
V2="$T/mut2"; mutd "$V2"; sed -i '' 's|echo "INFO PR #|HEADSHA="$(G rev-parse "refs/ft-land/$PR")"; echo "INFO PR #|' "$V2/ft-merge-land.sh"   # 가지 갈래에서 oid 대조 무력화
! cmp -s "$LAND" "$V2/ft-merge-land.sh" && ! r3 202 "$V2/ft-merge-land.sh"; ck "ⓗ2 변이(가지 갈래 S == HEADSHA 건너뜀) → R3 착지 = 시나리오 FAIL(검출)" $?
V3="$T/mut3"; mutd "$V3"; sed -i '' 's/sys.exit(1) if d.get("isCrossRepository") is not False else //' "$V3/ft-merge-lib.sh"   # 포크 검사 삭제
! cmp -s "$LIB" "$V3/ft-merge-lib.sh" && ! r5 203 "$V3/ft-merge-land.sh"; ck "ⓗ3 변이(isCrossRepository 검사 삭제) → R5 가지 fetch 기록 = 시나리오 FAIL(검출)" $?

# ── ⓕ 짝 사본 · 줄 수 ──
cmp -s "$LAND" "$KIT/ft-merge-land.sh" && cmp -s "$LIB" "$KIT/ft-merge-lib.sh"; ck "ⓕ 키트 사본 2 cmp0" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ⓕ ft-merge-land.sh ≤ 120줄(기존 시험 상한)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
