#!/usr/bin/env bash
# test_merge_land_fetch_sec.sh — r1069: ft-merge-land.sh 의 PR head fetch 상한 = FT_FETCH_TIMEOUT_SEC(1~70 · 오빠 예외 판정) 시험
#   임시 origin+clone · gh 는 스텁 · 실 gh·실 원격 0 · 느린 fetch 는 「timeout 이 걸린 초」를 대역이 기록해 잰다(긴 sleep 0)
#   ★test_merge_land.sh 와 별 파일인 이유 = 그 시험이 이미 단독 70 초(하드 룰 22) — 칸을 더하면 넘는다★
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: 레벨 밖(each) — 실 슬랙 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LAND="$BIN/ft-merge-land.sh"; LIB="$BIN/ft-merge-lib.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; first=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"
REAL_GIT="$(command -v git)"; REAL_TO="$(command -v timeout)"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; echo "REJECT usage" >&2; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
mkpr() {  # mkpr <번호> <브랜치> <시작점> — PR head 를 origin refs/pull/N/head 에 올리고 스텁 JSON 작성
  git -C "$W" checkout -q -B "$2" "$3"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"본문 "+sys.argv[2],"state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
# 대역: timeout 은 fetch 에 걸린 «초»를 기록(그게 곧 상한) · git 은 fetch 를 느리게/실패시킨다(sleep 은 timeout 이 끊는다)
FS="$T/shimFS"; FTLOG="$T/ftsec.log"; mkdir -p "$FS"
cat > "$FS/timeout" <<EOF
#!/bin/bash
f=0; for a in "\$@"; do [ "\$a" = fetch ] && f=1; done
[ "\$f" = 1 ] && echo "\$1" >> "$FTLOG"
exec "$REAL_TO" "\$@"
EOF
cat > "$FS/git" <<EOF
#!/bin/bash
f=0; for a in "\$@"; do [ "\$a" = fetch ] && f=1; done
if [ "\$f" = 1 ]; then
  [ -n "\${FT_FAIL:-}" ] && { echo "fatal: stub fetch fail" >&2; exit 128; }
  [ -n "\${FT_SLOW:-}" ] && sleep "\$FT_SLOW"
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$FS/timeout" "$FS/git"
ftl() { wc -l < "$FTLOG" | tr -d ' '; }        # fetch 시도 수
fsec() { sed -n "${1}p" "$FTLOG"; }            # n번째 시도의 timeout 인자
printf '#!/bin/bash\necho "ICHK $*"\n' > "$FS/ichk"; chmod +x "$FS/ichk"   # 착지 뒤 설치 검사는 이 카드 밖 — 7 초를 쓰지 않게 스텁
fland() {  # fland <PR> <env…> — 대역 PATH 로 착지 · 첫 줄 = land stdout 첫 줄
  local pr="$1"; shift; : > "$FTLOG"; git -C "$W" fetch -q origin; mkpr "$pr" "pr$pr" origin/main; local P="$PRSHA"; apv --approve-sha "$P"
  out="$(env PATH="$FS:$PATH" FT_INSTALL_CHECK="$FS/ichk" "$@" bash "$LAND" "$pr" --approve-sha "$P" --repo "$W" 2>&1)"; rc=$?
  first="$(printf '%s\n' "$out" | head -n1)"
}
fold() {  # fold <PR> <env…> — PR 을 «옛 main(M0)» 위에 만들어 게이트 거절로 빠르게 끝낸다(fetch·첫 줄만 본다)
  local pr="$1"; shift; : > "$FTLOG"; git -C "$W" fetch -q origin; mkpr "$pr" "pr$pr" "$M0"; local P="$PRSHA"; apv --approve-sha "$P"
  out="$(env PATH="$FS:$PATH" "$@" bash "$LAND" "$pr" --approve-sha "$P" --repo "$W" 2>&1)"; rc=$?
  first="$(printf '%s\n' "$out" | head -n1)"
}
# ── ⓐ R1 — env 없음 = 지금 그대로(상한 7 · 재시도 1) · 첫 줄 예외 표기 0 ──
MA="$(omain)"; fland 70 FT_FAIL=1
[ "$rc" = 1 ] && [[ "$out" == *"PR head fetch 실패"* ]] && [ "$(ftl)" = 2 ] && [ "$(fsec 1)" = 7 ] && [ "$(fsec 2)" = 7 ] && [[ "$first" != *"오빠 예외"* ]] && [ "$(omain)" = "$MA" ]; ck "ⓐ R1 env 없음 → 상한 7 초 × 2회(재시도 1) · REJECT · 첫 줄 예외 0 · main 불변" $?
# ── ⓑ R2 — 유효 지정 = 상한이 그 값 · 예외 첫 줄 · 끝까지 착지(성공 경로 1회) ──
fland 71 FT_FETCH_TIMEOUT_SEC=20 FT_SLOW=1
[ "$rc" = 0 ] && [ "$first" = "오빠 예외 판정 · 지정 20" ] && [ "$(fsec 1)" = 20 ] && [[ "$out" == *LANDED* ]]; ck "ⓑ R2 지정 20 → 첫 줄 «오빠 예외 판정 · 지정 20» · 상한 20(느린 fetch 통과) · 착지" $?
# ── ⓑ2 R6 — 판정 번호 칸 ──
fold 72 FT_FETCH_TIMEOUT_SEC=20 FT_FETCH_EXCEPTION_ID=2901
[ "$first" = "오빠 예외 판정 2901 · 지정 20" ]; ck "ⓑ2 R6 판정 번호 2901 → 첫 줄 «오빠 예외 판정 2901 · 지정 20»" $?
# ── ⓒ R3·R4 — 꼴 틀림·70 초과 = WARN 1줄 + 7 초 · 예외 표기 0 ──
fold 73 FT_FETCH_TIMEOUT_SEC=90
[[ "$out" == *"WARN"*"FT_FETCH_TIMEOUT_SEC=90"* ]] && [ "$(fsec 1)" = 7 ] && [[ "$first" != *"오빠 예외"* ]]; ck "ⓒ R3 90(70 초과) → WARN 1줄 + 7 초 · 예외 표기 0" $?
fold 74 FT_FETCH_TIMEOUT_SEC=abc
[[ "$out" == *"WARN"*"FT_FETCH_TIMEOUT_SEC=abc"* ]] && [ "$(fsec 1)" = 7 ] && [[ "$first" != *"오빠 예외"* ]]; ck "ⓒ2 R4 abc(정수 아님) → WARN 1줄 + 7 초 · 예외 표기 0" $?
# ── ⓓ R5 — 1회 상한 = min(지정, 남은 시간) · 재시도는 남은 ≥ 지정일 때만 ──
MD="$(omain)"; fland 75 FT_FETCH_TIMEOUT_SEC=2 FT_LAND_TOTAL_S=3 FT_SLOW=5
[ "$rc" = 1 ] && [ "$(ftl)" = 1 ] && [ "$(fsec 1)" -le 2 ] && [[ "$out" == *"PR head fetch 실패"* ]] && [ "$(omain)" = "$MD" ]; ck "ⓓ R5 지정 2 · 총 마감 3 · fetch 가 그 시간을 다 씀 → 상한 min(2,남은)=$(fsec 1) · 재시도 0 · REJECT · main 불변" $?
# ── ⓔ 변이 검출력 — 지정값을 무시하면 ⓑ 칸이, 70 상한을 끄면 ⓒ 칸이 FAIL ──
mutd() { local d="$1"; mkdir -p "$d"; cp "$LAND" "$d/ft-merge-land.sh"; cp "$LIB" "$d/ft-merge-lib.sh"
  for f in "$BIN"/*; do local b; b="$(basename "$f")"; [ "$b" = ft-merge-land.sh ] || [ "$b" = ft-merge-lib.sh ] || ln -sf "$f" "$d/$b"; done; }
MB="$T/mutvalid"; mutd "$MB"; sed -i '' 's/; FM_FETCH_SEC_VALID=1//' "$MB/ft-merge-lib.sh"   # 유효 표지 삭제 = 지정을 받아도 «예외» 첫 줄이 없다
! cmp -s "$LIB" "$MB/ft-merge-lib.sh"; ck "ⓔ 변이본 적용(유효 표지 삭제)" $?
: > "$FTLOG"; git -C "$W" fetch -q origin; mkpr 76 pr76 "$M0"; P76="$PRSHA"; apv --approve-sha "$P76"
out="$(env PATH="$FS:$PATH" FT_FETCH_TIMEOUT_SEC=20 bash "$MB/ft-merge-land.sh" 76 --approve-sha "$P76" --repo "$W" 2>&1)"
first="$(printf '%s\n' "$out" | head -n1)"
[[ "$first" != "오빠 예외 판정 · 지정 20" ]] && [[ "$first" != *"오빠 예외"* ]]; ck "ⓔ 변이(지정값 무시)는 ⓑ 칸(첫 줄)에서 FAIL — 시험 검출력" $?
MC="$T/mutcap"; mutd "$MC"; sed -i '' 's/&& \[ "\$v" -le 70 \] 2>\/dev\/null//' "$MC/ft-merge-lib.sh"   # 70 상한만 끔
! cmp -s "$LIB" "$MC/ft-merge-lib.sh"; ck "ⓒ 변이본 적용(70 상한 삭제)" $?
: > "$FTLOG"; git -C "$W" fetch -q origin; mkpr 77 pr77 "$M0"; P77="$PRSHA"; apv --approve-sha "$P77"
out="$(env PATH="$FS:$PATH" FT_FETCH_TIMEOUT_SEC=90 bash "$MC/ft-merge-land.sh" 77 --approve-sha "$P77" --repo "$W" 2>&1)"
first="$(printf '%s\n' "$out" | head -n1)"; [ "$(fsec 1)" -lt 90 ] && [ "$(fsec 1)" -ge 10 ] && [[ "$first" == *"오빠 예외"* ]]; ck "ⓒ 변이(70 상한 끔)는 ⓒ 칸(WARN + 7 초)에서 FAIL — 지정 90 이 «예외» 첫 줄로 통과 · 시험 검출력" $?
# ── ⓕ 회귀 — land·lib 정적 상한(줄 수·600·300·force) ──
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(r1069 뒤에도)" $?
! grep -vE '^\s*#' "$LAND" "$LIB" | grep -qE '\b(600|300)\b'; ck "600·300 글자 0" $?
cmp -s "$LAND" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$LIB" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 2 cmp0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
