#!/usr/bin/env bash
# test_merge_land_pack_close_as_user_r1179.sh — r1179: 착지 뒤 PR 닫기(본 닫기 + r1131 재시도)가 «사람 gh 로 닫는 리포 목록»(FT_PR_CLOSE_AS_USER · 기본 yoonhwan/ai-feature-pack)이면 사람 gh
#   반례 R1~R5(카드 동결) + 기준판(origin/main 사본 = Tank) · 변이 1(목록 판정 끔) · 되돌림(빈 값) · 키트 cmp
#   임시 BYZ 리포(cwd) + 임시 팩 리포(origin = github ssh 꼴 · GIT_SSH_COMMAND 스텁이 로컬 bare 로 전송) · 가짜 사람 gh · 가짜 Tank · 실 gh·실 토큰·실 원격 0 · 자기 재호출 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"; LAND="$BIN/ft-merge-land.sh"; AUT="$BIN/ft-autonomy.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub"

# ── 픽스처: BYZ 리포(승인 루트 · cwd) · 팩 리포 2개(yoonhwan/ai-feature-pack · other/repo)
mkrepo "$T/byz"; BYZ="$T/byz/w"; BYZ_ORIGIN="$T/byz/origin.git"; mkdir -p "$T/byz/.fable-team/state"
mkrepo "$T/pack"; PACK="$T/pack/w"; PACKO="$T/pack/origin.git"; git -C "$PACK" remote set-url origin git@github.com:yoonhwan/ai-feature-pack.git
mkrepo "$T/oth"; OTH="$T/oth/w"; OTHO="$T/oth/origin.git"; git -C "$OTH" remote set-url origin git@github.com:other/repo.git
cat > "$T/stub/ssh" <<'EOF'
#!/bin/bash
exec bash -c "$(printf '%s' "${!#}" | sed -E "s|'[^']*'|'$PACK_ORIGIN'|")"   # git-upload-pack '<원격 경로>' → 로컬 bare
EOF
cat > "$T/stub/gh" <<'EOF'
#!/bin/bash
echo "GH $* tok=${GH_TOKEN:-}${GITHUB_TOKEN:-}" >> "$STUB_LOG"
[ "$1 $2" = "pr close" ] && { [ -z "${FAIL_USER:-}" ] || { echo "GraphQL: Could not close (gh 사람 계정 실패)" >&2; exit 1; }; exit 0; }
[ "$1 $2" = "pr view" ] || exit 0
for a in "$@"; do [ "${pv:-}" = "-R" ] && R="$a"; pv="$a"; done
[ -n "${R:-}" ] && cat "$PACK_JSON" || cat "$BYZ_JSON"
EOF
printf '#!/bin/bash\necho "TANK $* repo=${FT_ISSUE_REPO:-}" >> "$STUB_LOG"\nexit 0\n' > "$T/stub/tank"
printf '#!/bin/bash\nexit 0\n' > "$T/stub/noop"; chmod +x "$T/stub"/*
export GIT_SSH_COMMAND="$T/stub/ssh" FT_GH="$T/stub/gh" FT_GH_WRITE="$T/stub/tank" STUB_LOG="$T/gh.log" FT_INSTALL_CHECK="$T/stub/noop" GH_TOKEN=bot-tok GITHUB_TOKEN=bot-tok2
export FT_ROOT="$T/byz" FT_AUTONOMY_STATE_DIR="$T/byz/.fable-team/state"; CPL="$FT_AUTONOMY_STATE_DIR/merge-close-pending.jsonl"
unset FT_PR_CLOSE_AS_USER

json() { python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$1" "$2"; }
mkpr() {  # mkpr <clone> <bare> <번호> <JSON파일> — origin/main 위 PR head + 승인
  local c="$1" b="$2" n="$3"; PRJSON="$4"
  PACK_ORIGIN="$b" git -C "$c" fetch -q origin; git -C "$c" checkout -q -B "pr$n" origin/main; echo "pr$n" > "$c/pr$n.txt"; cm "$c" "pr $n work"
  PACK_ORIGIN="$b" git -C "$c" push -q origin "pr$n:refs/pull/$n/head"; PRSHA="$(sha "$c" HEAD)"; PRNUM="$n"
  json "$PRSHA" "PR $n" > "$PRJSON"; bash "$AUT" approve-merge "$PRSHA" >/dev/null 2>&1
}
land() {  # land <land.sh> <clone> <bare> <번호> [KEY=VAL…] — cwd = BYZ(부른 리포) · clone 이 BYZ 면 --repo 없음(CROSS 아님)
  local l="$1" c="$2" b="$3" n="$4" ra=(); shift 4; mkpr "$c" "$b" "$n" "$T/pr$n.json"; : > "$STUB_LOG"; [ "$c" = "$BYZ" ] || ra=(--repo "$c")
  out="$(cd "$BYZ" && env "$@" PACK_ORIGIN="$b" PACK_JSON="$PRJSON" BYZ_JSON="$PRJSON" bash "$l" "$n" --approve-sha "$PRSHA" ${ra[@]+"${ra[@]}"} 2>&1)"; rc=$?
}
ucl() { grep -c "^GH pr close $1 -R yoonhwan/ai-feature-pack --comment .* tok=$" "$STUB_LOG" | tr -d ' '; }   # 사람 gh 닫기(토큰 빈) 수
tnk() { grep -c "^TANK pr-close $1 " "$STUB_LOG" | tr -d ' '; }
S1=$SECONDS

# 기준판(고치기 직전 main 고정 sha · r1132) — 지금 = 팩 착지도 Tank 1 · 사람 gh 0 · 객체 없는 사본(git archive)이면 SKIP
BASE_SHA="${FT_R1179_BASE:-55509ef3013b92a534a41026ae557554b453a20d}"; TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" && pwd -P)"
if [ -n "$TOP" ] && git -C "$TOP" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  mkdir -p "$T/base"; cp -R "$BIN/." "$T/base/"; RB="${BIN#"$TOP"/}"
  for f in ft-merge-land.sh ft-merge-lib.sh; do git -C "$TOP" show "$BASE_SHA:$RB/$f" > "$T/base/$f"; done
  land "$T/base/ft-merge-land.sh" "$PACK" "$PACKO" 5
  [ "$rc" = 0 ] && [ "$(tnk 5)" = 1 ] && [ "$(ucl 5)" = 0 ]; ck "기준판 팩 착지 → Tank 1 · 사람 gh 0(지금)" $?
else echo "SKIP 기준판 칸 — base_sha $BASE_SHA 객체 없음(git 사본 아님)"; fi

# R1 팩 착지 → 사람 gh close 1회(토큰 빈) · Tank 0 · rc0 · WARN 0 · INFO 1줄
land "$LAND" "$PACK" "$PACKO" 6
[ "$rc" = 0 ] && [ "$(ucl 6)" = 1 ] && [ "$(tnk 6)" = 0 ] && [[ "$out" != *WARN* ]] && [ "$(grep -c '^INFO PR #6 닫기 = 사람 gh(yoonhwan/ai-feature-pack)$' <<<"$out")" = 1 ]; ck "R1 팩 착지 → 사람 gh 1 · 토큰 빈 · Tank 0 · rc0 · WARN 0" $?
grep -q "^GH pr close 6 -R yoonhwan/ai-feature-pack --comment 착지 sha $(sha "$PACKO" refs/heads/main) " "$STUB_LOG"; ck "R1 코멘트 = 착지 sha 본문 문자열" $?

# R2 BYZ 리포(CROSS 아님 · slug 빈) → Tank 1 · 사람 gh close 0
land "$LAND" "$BYZ" "$BYZ_ORIGIN" 7
[ "$rc" = 0 ] && [ "$(tnk 7)" = 1 ] && ! grep -q '^GH pr close' "$STUB_LOG" && grep -q '^TANK pr-close 7 .* repo=$' "$STUB_LOG"; ck "R2 BYZ 착지 → Tank 1 · 사람 gh 0" $?

# R3 팩 착지 · 사람 gh 실패 → WARN · 장부 1줄 · rc3 · Tank 0(갈아타기 0)
land "$LAND" "$PACK" "$PACKO" 8 FAIL_USER=1; Q8="$(sha "$PACKO" refs/heads/main)"
[ "$rc" = 3 ] && [[ "$out" == *"WARN 착지는 성공 — PR #8 코멘트/닫기 실패: 손으로 처리(착지 sha $Q8)"* ]] && [ "$(tnk 8)" = 0 ] && ! grep -q '^TANK' "$STUB_LOG"; ck "R3 사람 gh 실패 → rc3 · WARN · Tank 0" $?
[ "$(grep -c . "$CPL" 2>/dev/null)" = 1 ] && grep -q '"repo": *"yoonhwan/ai-feature-pack"' "$CPL" && grep -Eq '"pr": ?8,' "$CPL"; ck "R3 장부 1줄(yoonhwan/ai-feature-pack · pr 8)" $?

# R4 장부의 팩 PR 8 → 다음 팩 착지 시작 때 사람 gh 로 닫음 · 장부 비움
land "$LAND" "$PACK" "$PACKO" 9
[ "$rc" = 0 ] && [ "$(ucl 8)" = 1 ] && [ "$(ucl 9)" = 1 ] && ! grep -q '^TANK' "$STUB_LOG" && [ ! -s "$CPL" ] && [[ "$out" == *"INFO 닫기 재시도 PR #8 닫음"* ]]; ck "R4 재시도 = 사람 gh · 장부 비움 · Tank 0" $?

# R5 CROSS · slug other/repo(목록 밖) → Tank 그대로(FT_ISSUE_REPO=other/repo)
land "$LAND" "$OTH" "$OTHO" 10
[ "$rc" = 0 ] && grep -q '^TANK pr-close 10 .* repo=other/repo$' "$STUB_LOG" && ! grep -q '^GH pr close' "$STUB_LOG"; ck "R5 목록 밖 리포 → Tank · 사람 gh 0" $?

# 되돌림 — FT_PR_CLOSE_AS_USER= (빈 값) → 팩도 Tank
land "$LAND" "$PACK" "$PACKO" 11 FT_PR_CLOSE_AS_USER=
[ "$rc" = 0 ] && [ "$(tnk 11)" = 1 ] && [ "$(ucl 11)" = 0 ]; ck "되돌림 빈 값 → 팩도 Tank" $?
S2=$SECONDS

# 변이 — 사본 lib 의 목록 판정을 끔(for 목록 비움) → R1 이 Tank 1 = 반례가 잡음
rm -rf "$T/m"; cp -R "$BIN" "$T/m"
python3 -c 'import sys;p=sys.argv[1];s=open(p).read();a="for u in ${FT_PR_CLOSE_AS_USER-yoonhwan/ai-feature-pack}; do";assert s.count(a)==1;open(p,"w").write(s.replace(a,"for u in ; do"))' "$T/m/ft-merge-lib.sh"
land "$T/m/ft-merge-land.sh" "$PACK" "$PACKO" 12
[ "$(tnk 12)" = 1 ] && [ "$(ucl 12)" = 0 ]; ck "변이 목록 판정 끔 → R1 Tank 1(반례가 잡음)" $?
S3=$SECONDS

cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 2 cmp0" $?
echo "단계별 초: 반례 $((S2 - S1)) · 변이 $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
