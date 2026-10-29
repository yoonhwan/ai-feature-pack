#!/usr/bin/env bash
# test_merge_land_close_pending_r1131.sh — r1131: ⑦ PR 코멘트/닫기 실패 = «닫기 대기» 장부 1줄 · 다음 착지 시작 때 같은 리포 항목(최대 3)을 먼저 다시 닫는다
#   반례 R1~R6(카드 동결) + 상한 3 · 변이 2(장부 쓰기 삭제 · 재시도 삭제) · 키트 cmp · 줄 상한
#   임시 origin+clone · 닫기 도구 = 대역 스텁(FAIL_CLOSE 에 든 PR 번호면 «Resource not accessible» rc1) · 실 gh·실 토큰·실 원격 0 · 자기 재호출 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/noop"
printf '#!/bin/bash\nexit 0\n' > "$T/noop"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
[ "$1" = pr-close ] || exit 0
case " ${FAIL_CLOSE:-} " in *" $2 "*|*" all "*) echo "GraphQL: Resource not accessible by personal access token (addComment)" >&2; exit 1;; esac
exit 0
EOF
chmod +x "$T/gh-stub" "$T/noop"
CPL="$T/state/merge-close-pending.jsonl"; KEY="$(cd "$W" && dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
omain() { sha "$ORIGIN" refs/heads/main; }
mkpr() {  # mkpr <번호> — origin/main 위 PR head 를 refs/pull/N/head 에 올리고 스텁 JSON
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() {  # land <land.sh> <번호> [KEY=VAL…]
  local l="$1" n="$2"; shift 2; mkpr "$n"; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"
  out="$(env "$@" bash "$l" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
}
ent() { printf '{"repo":"%s","pr":%s,"sha":"%s","ts":1}\n' "$1" "$2" "${3:-0123456789012345678901234567890123456789}" >> "$CPL"; }   # 장부 줄 손 입력(시험용)
has() { grep -Eq "\"pr\": ?$1," "$CPL" 2>/dev/null; }
closes() { grep -c "^pr-close $1 " "$STUB_LOG" | tr -d ' '; }
S1=$SECONDS

# R1 ⑦ 성공 → 장부 0 · rc 0
land "$LAND" 11; [ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ ! -s "$CPL" ]; ck "R1 ⑦ 성공 → rc0 · 장부 0" $?

# R2 ⑦ 실패 → rc 3 · WARN 줄 그대로 · 장부 1줄(repo·pr·sha)
land "$LAND" 12 FAIL_CLOSE=all; Q12="$(omain)"
[ "$rc" = 3 ] && [[ "$out" == *"WARN 착지는 성공 — PR #12 코멘트/닫기 실패: 손으로 처리(착지 sha $Q12)"* ]]; ck "R2 ⑦ 실패 → rc3 · WARN 줄 그대로" $?
[ "$(grep -c . "$CPL" 2>/dev/null)" = 1 ] && python3 -c 'import json,sys;d=json.loads(open(sys.argv[1]).readline());sys.exit(0 if (d["repo"],d["pr"],d["sha"])==(sys.argv[2],12,sys.argv[3]) else 1)' "$CPL" "$KEY" "$Q12"; ck "R2 장부 1줄 = repo(대상 리포 루트) · pr 12 · 착지 sha" $?

# R3 같은 repo 2건 → 다음 착지 시작 때 2건 pr-close · 성공 건은 장부에서 빠짐 · 착지 본체 그대로
ent "$KEY" 13; land "$LAND" 14
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=14 "* ]] && [ "$(closes 12)" = 1 ] && [ "$(closes 13)" = 1 ] && [ ! -s "$CPL" ]; ck "R3 장부 2건 재시도 → 둘 다 닫힘 · 장부 비움 · 착지 rc0" $?
[ "$(grep -n '^pr-close 12 ' "$STUB_LOG" | cut -d: -f1)" -lt "$(grep -n '^pr view 14 ' "$STUB_LOG" | cut -d: -f1)" ] && grep -q "^pr-close 12 --comment .* --apply" "$STUB_LOG"; ck "R3 재시도는 gh pr view 앞 · pr-close --comment <파일> --apply 꼴" $?

# R4 재시도 실패 → 장부에 남음 · stdout 1줄 · 착지 rc 영향 0
ent "$KEY" 15; land "$LAND" 16 FAIL_CLOSE=15
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=16 "* ]] && has 15 && [ "$(grep -c '닫기 재시도 실패 PR #15' <<<"$out")" = 1 ]; ck "R4 재시도 실패 → 장부 남음 · 실패 줄 1 · 착지 rc0" $?
: > "$CPL"

# R5 장부 repo ≠ 이번 착지 repo → 건드리지 않음
ent other/repo 77; land "$LAND" 17
[ "$rc" = 0 ] && [ "$(closes 77)" = 0 ] && has 77 && [ "$(grep -c . "$CPL")" = 1 ]; ck "R5 다른 repo 항목 → 재시도 0 · 줄 그대로" $?
: > "$CPL"

# R6 남은 시간 < 20 s → 재시도 0 · «재시도 미룸» 1줄
ent "$KEY" 18; land "$LAND" 19 FT_LAND_TOTAL_S=19
[ "$(closes 18)" = 0 ] && has 18 && [ "$(grep -c '닫기 재시도 미룸' <<<"$out")" = 1 ]; ck "R6 남은 19s → 재시도 0 · 미룸 줄 1 · 장부 그대로" $?
: > "$CPL"

# 상한 3 — 같은 repo 4건이면 앞 3건만 · 1건 남음
for n in 21 22 23 24; do ent "$KEY" "$n"; done; land "$LAND" 25
[ "$rc" = 0 ] && [ "$(closes 21)$(closes 22)$(closes 23)$(closes 24)" = 1110 ] && [ "$(grep -c . "$CPL")" = 1 ] && has 24; ck "상한 3 · 4건 중 3건 닫고 1건 남김" $?
: > "$CPL"
S2=$SECONDS

# 변이 — 사본 bin 에서 한 줄 지우고 같은 반례를 다시: 잡히면(= 반례 실패) PASS
mut() {  # mut <이름> <지울 줄 패턴(python 정규식)> — 사본 land 의 그 패턴 부분을 «:» 로
  rm -rf "$T/m"; cp -R "$BIN" "$T/m"; python3 -c 'import re,sys;p=sys.argv[1];s=open(p).read();n=re.subn(sys.argv[2],":",s);open(p,"w").write(n[0]);sys.exit(0 if n[1]==1 else 1)' "$T/m/ft-merge-land.sh" "$2"
}
mut 1 'fm_close_pending_add "\$CPL" "\$CPK" "\$PR" "\$Q"' && land "$T/m/ft-merge-land.sh" 31 FAIL_CLOSE=all
[ "$rc" = 3 ] && [ ! -s "$CPL" ]; ck "변이1 장부 쓰기 삭제 → R2 장부 0(반례가 잡음)" $?
: > "$CPL"; ent "$KEY" 32
mut 2 'fm_close_retry "\$CPL" "\$CPK" "\$SLUG" "\$GH_W" \$\(\(LIM - \(SECONDS - T0\)\)\)' && land "$T/m/ft-merge-land.sh" 33
[ "$rc" = 0 ] && [ "$(closes 32)" = 0 ] && has 32; ck "변이2 재시도 삭제 → R3 장부 그대로(반례가 잡음)" $?
S3=$SECONDS

# 키트 사본 · 줄 상한
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 2 cmp0" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ] && bash -n "$LAND" && bash -n "$BIN/ft-merge-lib.sh"; ck "ft-merge-land.sh ≤ 120줄 · bash -n 2" $?

echo "단계별 초: 반례 $((S2 - S1)) · 변이 $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
