#!/usr/bin/env bash
# test_merge_land_close_first_r1592.sh — r1592: ft-merge-land 는 push ok·원장(103줄) «직후»에 PR 코멘트·닫기를 먼저 한다.
#   뒤 단계(ft-head-lag·설치 검사·착지 쪽지)가 바깥 timeout 70 s 에 걸려도 PR 은 닫히거나 «닫기 대기» 장부에 남는다.
#   ⓐ 순서 = 닫기가 head-lag·설치 검사보다 먼저 · ⓑ 닫기 실패 = 장부 1줄 + 뒤 단계 그대로 + 최종 rc 3 · 변이 M1(원래 자리로 되돌리기) = ⓐ FAIL
#   임시 origin+clone · 가짜 gh(FT_GH/FT_GH_WRITE)·가짜 ft-head-lag.sh(HERE 사본)·가짜 설치 검사 — 셋 다 같은 순서 파일에 1줄 · sleep 0 · 실 원격·실 gh·실 토큰 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"; ORDER="$T/order.txt"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" ORDER FT_INSTALL_CHECK="$T/install-stub"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
[ "$1" = pr-close ] || exit 0
echo close >> "$ORDER"
case " ${FAIL_CLOSE:-} " in *" $2 "*|*" all "*) echo "GraphQL: Resource not accessible by personal access token (addComment)" >&2; exit 1;; esac
exit 0
EOF
printf '#!/bin/bash\necho install >> "$ORDER"\necho "OK n=1 (r1592 stub)"\nexit 0\n' > "$T/install-stub"
chmod +x "$T/gh-stub" "$T/install-stub"
FIXB="$T/bin"; cp -R "$BIN" "$FIXB"   # HERE 사본 — 가짜 ft-head-lag.sh 를 같은 폴더에 끼운다(실 도구 무수정)
printf '#!/bin/bash\necho head-lag >> "$ORDER"\nexit 0\n' > "$FIXB/ft-head-lag.sh"; chmod +x "$FIXB/ft-head-lag.sh"
CPL="$T/state/merge-close-pending.jsonl"
mkpr() {  # mkpr <번호> — origin/main 위 PR head 를 refs/pull/N/head 에 올리고 스텁 JSON
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() {  # land <land.sh> <번호> [KEY=VAL…]
  local l="$1" n="$2"; shift 2; mkpr "$n"; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$ORDER"
  out="$(env "$@" bash "$l" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
}
first() { head -n1 "$ORDER" | tr -d '[:space:]'; }   # 순서 파일 첫 줄 = 가장 먼저 돈 단계
seqno() { grep -n "^$1\$" "$ORDER" 2>/dev/null | head -n1 | cut -d: -f1; }   # 단계의 줄 번호(빈 값 = 안 돎)
S1=$SECONDS

# ⓐ 순서 — 닫기가 head-lag·설치 검사보다 먼저 · 착지 rc 0 · 세 단계 다 돎
land "$FIXB/ft-merge-land.sh" 41
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(first)" = close ] \
  && [ -n "$(seqno head-lag)" ] && [ -n "$(seqno install)" ] \
  && [ "$(seqno close)" -lt "$(seqno head-lag)" ] && [ "$(seqno close)" -lt "$(seqno install)" ]; ck "ⓐ 첫 줄 = close · close < head-lag · close < install · rc0" $?

# ⓑ 닫기 실패 — 장부 1줄 · WARN 줄 그대로 · 뒤 단계(head-lag·설치 검사·착지 쪽지)는 그대로 돈다 · 최종 rc 3
land "$FIXB/ft-merge-land.sh" 42 FAIL_CLOSE=all
[ "$rc" = 3 ] && [ "$(first)" = close ] && [ -n "$(seqno head-lag)" ] && [ -n "$(seqno install)" ] \
  && [[ "$out" == *"WARN 착지는 성공 — PR #42 코멘트/닫기 실패: 손으로 처리(착지 sha $(sha "$ORIGIN" refs/heads/main))"* ]] \
  && grep -qE 'INFO 착지 쪽지 생략|NOTIFIED 착지' <<<"$out"; ck "ⓑ 닫기 실패 → rc3 · WARN · head-lag·설치·착지 쪽지 그대로" $?
[ "$(grep -c . "$CPL" 2>/dev/null)" = 1 ] && python3 -c 'import json,sys;d=json.loads(open(sys.argv[1]).readline());sys.exit(0 if d["pr"]==42 else 1)' "$CPL"; ck "ⓑ «닫기 대기» 장부 1줄 = pr 42" $?
: > "$CPL"
S2=$SECONDS

# 변이 M1 — 닫기 블록을 원래 자리(맨 끝)로 되돌린 사본: ⓐ 가 잡는다(첫 줄 = head-lag)
rm -rf "$T/m"; cp -R "$BIN" "$T/m"; printf '#!/bin/bash\necho head-lag >> "$ORDER"\nexit 0\n' > "$T/m/ft-head-lag.sh"
python3 -c 'import sys
p=sys.argv[1]; L=open(p,encoding="utf-8").read().splitlines()
i=[n for n,l in enumerate(L) if l.startswith("CR=0; CB=")]
assert len(i)==1, i
b=L[i[0]:i[0]+4]; assert b[3].lstrip().startswith("|| {"), b
del L[i[0]:i[0]+4]
open(p,"w",encoding="utf-8").write("\n".join(L+b)+"\n")' "$T/m/ft-merge-land.sh"
land "$T/m/ft-merge-land.sh" 43
[ "$(first)" != close ] && [ "$(first)" = head-lag ]; ck "변이 M1 원래 자리로 → 첫 줄 = head-lag(ⓐ 반례가 잡음)" $?
S3=$SECONDS

# 키트 사본 · 줄 상한 · 문법
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh"; ck "키트 사본 cmp0" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ] && bash -n "$LAND"; ck "ft-merge-land.sh ≤ 120줄 · bash -n" $?

echo "단계별 초: ⓐⓑ $((S2 - S1)) · 변이 $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
