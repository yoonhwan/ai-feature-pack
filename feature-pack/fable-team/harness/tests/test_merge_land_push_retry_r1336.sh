#!/usr/bin/env bash
# test_merge_land_push_retry_r1336.sh — r1336: ft-merge-land push 1회 상한이 부하에서 모자라 «착지 0» 이 반복되는 것을 고친다
#   V1 1차 timeout · ls-remote = M · 남은 ≥ PB → 재시도 1회(상한 2×PB) · 성공 = LANDED + «재시도 1» 줄 + push-timing.tsv 2줄
#   V2 남은 < PB → 재시도 0 · 지금 문구 거절   V3 ls-remote = Q → 착지됨(2중 push 0)   V4 ls-remote 실패 → «원격 상태 불명»(재시도 0)
#   V5 2차 timeout · ls = M → «착지 0 확정(재시도 1 포함)» · 3차 0   V6 2차 non-FF → 지금 non-FF 문구   V7 tsv 쓰기 실패 → WARN 1줄 · 착지 rc 그대로
#   V8 닫기 장부: already merged / already closed / MERGED 상태 = 지움 · 다른 실패(OPEN · 조회 실패) = 남김   V9 PB: 객체 9 = 14 · F=4.5 주면 11
#   V10 2차 상한 = min(2×PB, 남은 시간) · 총 마감 안에 끝남
#   변이 4(변이는 «mut» 인자로 따로 돈다 — 시험 1개 70초 상한): 1 ls=M 확인 삭제 → V3·V4 · 2 AB2 가 남은 시간 무시 → V10 · 3 F 기본 4.5 → V9 · 4 장부가 다른 실패도 지움 → V8
#   기준판 대조: R1336_BIN=<origin/main 판 bin 폴더> 로 돌리면 V1·V9 가 FAIL 이어야 한다
#   임시 origin+clone · 가짜 timeout(push 인자 기록 · 시도별 결과 주입) · gh 스텁 · 실 gh·실 원격·실 Redis 0 · 자기 재호출 0 · 고정 sleep 은 가짜 push 의 «걸린 시간 흉내» 뿐
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each FT_MERGE_LAND_CODE_AUTOMERGE=0 FT_HEAVY_SLOTS=0
MODE="${1:-all}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "${R1336_BIN:-$HERE/../bin}" && pwd -P)"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; QUIET=""; mfail=0; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then [ -n "$QUIET" ] || echo "PASS $1"; elif [ -n "$QUIET" ]; then mfail=$((mfail+1)); else echo "FAIL $1 :: rc=$rc out=${out:0:500}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/shimP" "$T/.fable-team"
REAL_GIT="$(command -v git)"; REAL_TO="$(command -v timeout || command -v gtimeout)"; PLOG="$T/push.log"; CPL="$T/state/merge-close-pending.jsonl"; TSV="$T/state/push-timing.tsv"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/noop" T
printf '#!/bin/bash\nexit 0\n' > "$T/noop"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
if [ "$1 $2" = "pr view" ]; then   # 장부 PR(st.<n> 파일 있음) = 그 상태 · 없으면 착지 PR 의 JSON
  f="$T/st.$3"; [ -f "$f" ] || { cat "$STUB_JSON"; exit 0; }
  [ "$(cat "$f")" = FAIL ] && { echo "gh: network error" >&2; exit 1; }
  printf '{"state":"%s"}\n' "$(cat "$f")"; exit 0
fi
[ "$1" = pr-close ] || exit 0
f="$T/cm.$2"; [ -f "$f" ] || exit 0
cat "$f" >&2; exit 1
EOF
cat > "$T/shimP/git" <<EOF
#!/bin/bash
r=0; o=0; for a in "\$@"; do [ "\$a" = rev-list ] && r=1; [ "\$a" = --objects ] && o=1; done
[ "\$r\$o" = 11 ] && [ -n "\${STUB_OBJECTS:-}" ] && { seq 1 "\$STUB_OBJECTS"; exit 0; }
exec "$REAL_GIT" "\$@"
EOF
cat > "$T/shimP/timeout" <<EOF
#!/bin/bash
p=0; l=0; for a in "\$@"; do [ "\$a" = push ] && p=1; [ "\$a" = ls-remote ] && l=1; done
[ "\$l" = 1 ] && [ -n "\${STUB_LSREMOTE_FAIL:-}" ] && { echo "fatal: unable to access (stub)" >&2; exit 128; }
[ "\$p" = 1 ] || exec "$REAL_TO" "\$@"
echo "\$1" >> "$PLOG"; n="\$(wc -l < "$PLOG" | tr -d ' ')"; mode="\$(printf '%s' "\${PUSH_MODES:-ok}" | cut -d' ' -f"\$n")"; [ -n "\$mode" ] || mode=ok
[ -n "\${PUSH_SLEEP:-}" ] && [ "\$n" = 1 ] && sleep "\$PUSH_SLEEP"
case "\$mode" in
  rc124) exit 124;;
  reject) echo " ! [rejected]        Q -> main (fetch first)" >&2; echo "error: failed to push some refs" >&2; exit 1;;
  afterland) shift; "\$@" >/dev/null 2>&1; echo "remote: Resolving deltas: 100% (3/3), done." >&2; echo "To stub-origin" >&2; exit 124;;
  *) shift; exec "\$@";;
esac
EOF
chmod +x "$T/gh-stub" "$T/noop" "$T/shimP/git" "$T/shimP/timeout"
omain() { sha "$ORIGIN" refs/heads/main; }
KEY="$(cd "$W" && dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
mkpr() {  # mkpr <번호> — origin/main 위 PR head 를 refs/pull/N/head 에 올리고 스텁 JSON
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
pland() {  # pland <PR> <env…> — 가짜 timeout·git 으로 착지 · 시도 기록 · tsv 초기화 · ELA = 걸린 초
  local pr="$1" e; shift; : > "$PLOG"; rm -f "$TSV"; mkpr "$pr"; apv --approve-sha "$PRSHA"; e=$SECONDS
  out="$(env PATH="$T/shimP:$PATH" "$@" bash "$LAND" "$pr" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; ELA=$((SECONDS - e))
}
np() { wc -l < "$PLOG" | tr -d ' '; }
ab() { sed -n "${1}p" "$PLOG"; }   # n 번째 push 의 timeout 인자(= AB)
tc() { sed -n "${1}p" "$TSV" | cut -f"$2"; }   # tsv n 번째 줄의 m 번째 칸(1 시각 · 2 시도 · 3 부하 · 4 객체 · 5 PB · 6 AB · 7 소요 · 8 rc · 9 판정)
ent() { printf '{"repo":"%s","pr":%s,"sha":"0123456789012345678901234567890123456789","ts":1}\n' "$KEY" "$1" >> "$CPL"; }
has() { grep -Eq "\"pr\": ?$1," "$CPL" 2>/dev/null; }

v1() { local m; m="$(omain)"; pland 51 STUB_OBJECTS=1 PUSH_MODES="rc124 ok"
  [ "$rc" = 0 ] && [ "$(np)" = 2 ] && [[ "$out" == LANDED* || "$out" == *"LANDED pr=51 "* ]] && [ "$(omain)" != "$m" ] && [[ "$out" == *"재시도 1(1차 timeout"*"원격 main = $m 확인"* ]]; ck "V1 1차 timeout · 원격 main = M · 남은 ≥ PB → 재시도 1회 → 착지 · «재시도 1» 줄" $?
  [ "$(ab 1)" = 14 ] && [ "$(ab 2)" = 28 ] && [[ "$out" == *"push ok objects=1 bound=14 attempt=28 took="* ]]; ck "V1 1차 상한 PB 14 · 2차 상한 2×PB 28 · push ok 줄 bound=14 attempt=28" $?
  [ "$(grep -c . "$TSV")" = 2 ] && [ "$(tc 1 2)/$(tc 1 4)/$(tc 1 5)/$(tc 1 6)/$(tc 1 8)/$(tc 1 9)" = "1/1/14/14/124/ls=M" ] && [ "$(tc 2 2)/$(tc 2 6)/$(tc 2 8)/$(tc 2 9)" = "2/28/0/ok" ]; ck "V1 push-timing.tsv 2줄 = 1차(시도 1·PB 14·AB 14·rc124·ls=M) · 2차(시도 2·AB 28·rc0·ok)" $?
  [ -n "$(tc 1 1)" ] && [ -n "$(tc 1 3)" ] && [ "$(awk -F'\t' '{print NF}' "$TSV" | sort -u)" = 9 ]; ck "V1 tsv 칸 9개 · 시각·부하 칸 채워짐" $?; }
v2() { local m; m="$(omain)"; pland 52 STUB_OBJECTS=1 FT_PUSH_FIXED_S=1 FT_LAND_TOTAL_S=15 PUSH_SLEEP=8 PUSH_MODES="rc124 ok"
  [ "$rc" = 1 ] && [ "$(np)" = 1 ] && [ "$(omain)" = "$m" ] && [[ "$out" == *"착지 0 확정(원격 main = $m) · push 응답 불명(rc=124) · 재시도 0 — 총 마감 안에 끝내지 못함"* ]] && [[ "$out" != *"재시도 1("* ]]; ck "V2 남은 < PB → 재시도 0 · 지금 문구 거절 · main 불변" $?; }
v3() { local m; m="$(omain)"; pland 53 STUB_OBJECTS=1 PUSH_MODES="afterland ok"
  [ "$rc" = 0 ] && [ "$(np)" = 1 ] && [ "$(omain)" != "$m" ] && [[ "$out" == *"confirmed=ls-remote"* ]] && [[ "$out" != *"재시도 1("* ]] && [ "$(tc 1 9)" = ls=Q ]; ck "V3 응답 후 timeout · 원격 = Q → 착지됨 · push 1회(2중 push 0) · tsv ls=Q" $?; }
v4() { local m; m="$(omain)"; pland 54 STUB_OBJECTS=1 PUSH_MODES="rc124 ok" STUB_LSREMOTE_FAIL=1
  [ "$rc" = 1 ] && [ "$(np)" = 1 ] && [ "$(omain)" = "$m" ] && [[ "$out" == *"원격 상태 불명"* ]] && [[ "$out" != *"착지 0 확정"* ]] && [ "$(tc 1 9)" = 불명 ]; ck "V4 ls-remote 실패 → «원격 상태 불명» · 재시도 0 · main 불변" $?; }
v5() { local m; m="$(omain)"; pland 55 STUB_OBJECTS=1 PUSH_MODES="rc124 rc124 ok"
  [ "$rc" = 1 ] && [ "$(np)" = 2 ] && [ "$(omain)" = "$m" ] && [[ "$out" == *"착지 0 확정(재시도 1 포함 · 원격 main = $m)"* ]] && [[ "$out" == *"3차 0"* ]] && [ "$(grep -c . "$TSV")" = 2 ]; ck "V5 2차 timeout · ls = M → «착지 0 확정(재시도 1 포함)» · 3차 0 · tsv 2줄" $?; }
v6() { local m; m="$(omain)"; pland 56 STUB_OBJECTS=1 PUSH_MODES="rc124 reject ok"
  [ "$rc" = 1 ] && [ "$(np)" = 2 ] && [ "$(omain)" = "$m" ] && [[ "$out" == *"서버가 non-FF 로 거절"* ]] && [ "$(tc 2 9)" = non-ff ]; ck "V6 2차 non-FF → 지금 non-FF 거절 문구 · main 불변 · tsv non-ff" $?; }
v7() { local m; m="$(omain)"; pland 57 STUB_OBJECTS=1 FT_PUSH_TIMING_FILE=/dev/null/x/push-timing.tsv
  [ "$rc" = 0 ] && [ "$(omain)" != "$m" ] && [ "$(grep -c 'WARN push-timing 기록 실패' <<<"$out")" = 1 ] && [[ "$out" == *"LANDED pr=57 "* ]]; ck "V7 tsv 쓰기 실패 → WARN 1줄 · 착지 rc0 그대로" $?; }
v8() {
  : > "$CPL"; printf '%s\n' "Pull request #41 is already closed" > "$T/cm.41"; printf '%s\n' "X Pull request #42 can't be closed because it was already merged" > "$T/cm.42"
  printf '%s\n' "GraphQL: Resource not accessible by personal access token" > "$T/cm.43"; echo MERGED > "$T/st.43"
  ent 41; ent 42; ent 43; pland 58
  [ "$rc" = 0 ] && [ ! -s "$CPL" ] && [ "$(grep -c '장부에서 지움' <<<"$out")" = 3 ]; ck "V8 already closed · already merged · gh 상태 MERGED → 성공으로 보고 장부에서 지움(INFO 3줄)" $?
  : > "$CPL"; cp "$T/cm.43" "$T/cm.44"; cp "$T/cm.43" "$T/cm.45"; echo OPEN > "$T/st.44"; echo FAIL > "$T/st.45"; ent 44; ent 45; pland 59
  [ "$rc" = 0 ] && has 44 && has 45 && [ "$(grep -c '닫기 재시도 실패 PR #4[45]' <<<"$out")" = 2 ] && [[ "$out" != *"장부에서 지움"* ]]; ck "V8 다른 실패(상태 OPEN · 상태 조회 실패) → 장부에 남김 · 실패 줄 2" $?
  : > "$CPL"; rm -f "$T"/cm.* "$T"/st.*; }
v9() { local a b c; a="$(. "$BIN/ft-merge-lib.sh"; fm_push_calc 9 2>/dev/null)"; b="$(. "$BIN/ft-merge-lib.sh"; FT_PUSH_FIXED_S=4.5 fm_push_calc 9 2>/dev/null)"; c="$(. "$BIN/ft-merge-lib.sh"; fm_push_calc '?' 2>/dev/null)"
  [ "$a" = 14 ] && [ "$b" = 11 ] && [ "$c" = 14 ]; ck "V9 PB: 객체 9 → 14(F 7 + 7×1) · FT_PUSH_FIXED_S=4.5 → 11(정수 내림) · 크기 모름 → 14 (got $a/$b/$c)" $?; }
v10() { local m a2; m="$(omain)"; pland 60 STUB_OBJECTS=1 FT_PUSH_FIXED_S=1 FT_LAND_TOTAL_S=20 PUSH_SLEEP=6 PUSH_MODES="rc124 ok"
  a2="$(ab 2)"; [ "$rc" = 0 ] && [ "$(np)" = 2 ] && [ "$(ab 1)" = 8 ] && [ "${a2:-0}" -ge 8 ] && [ "${a2:-99}" -le 14 ] && [ "$ELA" -le 20 ]; ck "V10 2차 상한 = min(2×PB 16, 남은 시간) → $a2 (8~14) · 착지 끝 ${ELA}s ≤ 총 마감 20" $?; }

mutcase() {  # mutcase <이름> <파일> <바꿀 문자열> <새 문자열> <반례 함수…> — 사본 bin 에서 한 곳만 바꾸고 같은 반례를 QUIET 로 다시: 하나라도 FAIL 이면 «잡힘» = PASS
  local nm="$1" f="$2" old="$3" new="$4"; shift 4; rm -rf "$T/m"; cp -R "$BIN" "$T/m"
  python3 -I -c 'import sys;p,o,n=sys.argv[1:4];s=open(p,encoding="utf-8").read();assert s.count(o)==1,s.count(o);open(p,"w",encoding="utf-8").write(s.replace(o,n))' "$T/m/$f" "$old" "$new" || { echo "FAIL $nm 변이 적용 실패(바꿀 곳 1곳 아님)"; fail=$((fail+1)); return; }
  local L0="$LAND" B0="$BIN" fn; LAND="$T/m/ft-merge-land.sh"; BIN="$T/m"; QUIET=1; mfail=0
  for fn in "$@"; do "$fn"; done
  QUIET=""; LAND="$L0"; BIN="$B0"
  [ "$mfail" -gt 0 ]; ck "$nm → 반례 $* 가 잡음(실패 $mfail)" $?
}

S1=$SECONDS
if [ "$MODE" = all ]; then
  bash -n "$LAND" && bash -n "$BIN/ft-merge-lib.sh"; ck "bash -n land · lib" $?
  [ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 시험 상한)" $?
  cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 2 cmp0" $?
  for f in v1 v2 v3 v4 v5 v6 v7 v8 v9 v10; do "$f"; done
else
  # 변이 1: 재시도 판정에서 «ls-remote = M 확인»(+ Q 판정) 삭제 → V3(2중 push)·V4(불명인데 재시도) FAIL
  mutcase "변이1 ls-remote 확인 삭제" ft-merge-land.sh '[ "$lrc" -eq 0 ] && [ "$LSV" = "$M" ]; then plog ls=M' 'true; then plog ls=M' v4
  mutcase "변이1b ls=Q 판정 삭제" ft-merge-land.sh 'if [ "$lrc" -eq 0 ] && [ "$LSV" = "$Q" ]; then plog ls=Q' 'if false; then plog ls=Q' v3
  mutcase "변이2 AB2 가 남은 시간 무시" ft-merge-land.sh 'AB=$((2 * PB < REM ? 2 * PB : REM))' 'AB=$((2 * PB))' v10
  mutcase "변이3 F 기본값 4.5 로 되돌림" ft-merge-lib.sh 'f="${FT_PUSH_FIXED_S:-7}"' 'f="${FT_PUSH_FIXED_S:-4.5}"' v9
  mutcase "변이4 장부가 다른 실패도 지움" ft-merge-lib.sh 'fm_pr_done() {' 'fm_pr_done() { return 0;' v8
fi
echo "단계별 초: 반례·변이 $((SECONDS - S1)) · 합계 $((SECONDS - T0)) (모드 $MODE)"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
