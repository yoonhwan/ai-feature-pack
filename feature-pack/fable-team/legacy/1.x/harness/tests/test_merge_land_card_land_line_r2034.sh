#!/usr/bin/env bash
# test_merge_land_card_land_line_r2034.sh — r2034: ft-merge-land 가 착지 성공 뒤 카드 «## 상태» 절 끝에 «- 착지: <Q> (…)» 1줄을 직접 쓴다.
#   세계 = 임시 리포 2개: ⓐ 코드 리포(_merge_fixture origin.git + clone W) ⓑ 카드 ref 리포(cards.git · 가지 ops/main-base · 카드 폴더 대기·진행·완성)
#   + 카드 루트 C(= FT_ROOT · cards.git clone · directive-roots.tsv harness 행 = origin/ops/main-base) · gh 스텁 · 실 좌석·실 리포·sleep 0
#   bin 은 HERE 사본(가짜 ft-head-lag.sh·ft-nano-record.sh 만 끼움 — 착지 뒤 무관 단계) · FT_R2034_BIN = 변이 사본 주입
#   반례 ①~⑦(카드 r2034 동결) · 변이 M1~M3 = FT_R2034_BIN=<변이 사본> 으로 같은 시험(원본 대조 = 인자 없이 1회)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each FT_CRITICAL_OFF=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "${FT_R2034_BIN:-$HERE/../bin}" && pwd -P)"; KIT="$HERE/../kit/fable-team/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"
CB="$T/cards.git"; C="$T/croot"; IX="design/harness/indices"
git init -q --bare -b ops/main-base "$CB"; git clone -q "$CB" "$C" 2>/dev/null; git -C "$C" checkout -q -b ops/main-base
git -C "$C" config user.name t; git -C "$C" config user.email t@t; git -C "$C" config commit.gpgsign false
mkdir -p "$C/$IX/대기" "$C/$IX/진행" "$C/$IX/완성" "$C/.fable-team/state"
printf 'harness\t.\torigin/ops/main-base\t%s\n' "$IX" > "$C/.fable-team/state/directive-roots.tsv"
printf '/.fable-team/\n' >> "$(git -C "$C" rev-parse --git-path info/exclude | sed "s|^\.git|$C/.git|")"
printf '# 대기 카드\n\n## 상태\n- 대기\n' > "$C/$IX/대기/r9000-wait.md"; printf '# 끝 카드\n\n## 상태\n- 완성\n' > "$C/$IX/완성/r8999-done.md"
cm "$C" seed && git -C "$C" push -q origin ops/main-base
export FT_ROOT="$C" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/install-stub"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
exit 0
EOF
printf '#!/bin/bash\necho "OK n=1 (r2034 stub)"\nexit 0\n' > "$T/install-stub"; chmod +x "$T/gh-stub" "$T/install-stub"
FIXB="$T/bin"; cp -R "$BIN" "$FIXB"
printf '#!/bin/bash\nexit 0\n' > "$FIXB/ft-head-lag.sh"; printf '#!/bin/bash\nexit 0\n' > "$FIXB/ft-nano-record.sh"
LAND_RE='^- 착지: ([0-9a-f]{40})(?=\s|$)'   # = ft2/adapters/pi/keeper_land.py:24 LAND (아래에서 같은 글자인지 대조)

card_put() {  # card_put <단계> <stem> <본문> — 카드 ref(cards.git ops/main-base)에 1커밋
  git -C "$C" fetch -q origin && git -C "$C" reset -q --hard origin/ops/main-base   # 앞 착지가 원격에 쓴 줄 위에서
  printf '%s' "$3" > "$C/$IX/$1/$2.md"; cm "$C" "card $2" && git -C "$C" push -q origin ops/main-base
}
card_get() { git -C "$CB" show "ops/main-base:$IX/$1/$2.md"; }   # 원격 카드 ref 의 본문(실제 push 결과)
tip() { git -C "$CB" rev-parse ops/main-base; }
mkpr() {  # mkpr <번호> <head 가지> <제목> — origin/main 위 PR head → refs/pull/N/head + 스텁 JSON
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":sys.argv[3],"body":"본문 r8999","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$3" > "$STUB_JSON"
}
land() {  # land <land.sh> <번호> [ft-merge-land 추가 인자…] (mkpr 뒤)
  local l="$1" n="$2"; shift 2; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"
  out="$(bash "$l" "$n" --approve-sha "$PRSHA" --repo "$W" "$@" 2>&1)"; rc=$?
  QL="$(sed -n 's/^LANDED pr=[0-9]* sha=\([0-9a-f]*\) .*/\1/p' <<<"$out")"
}
lands() { python3 -c 'import re,sys;print(" ".join(re.findall(sys.argv[1],sys.stdin.read(),re.M)))' "$LAND_RE"; }   # 카드 본문 → keeper 정규식 착지 sha 들
sec_last() { python3 -c 'import re,sys
L=sys.stdin.read().split("\n");s=L.index("## 상태");e=next((i for i in range(s+1,len(L)) if re.match(r"##\s",L[i])),len(L))
b=[x for x in L[s+1:e] if x.strip()];print(b[-1] if b else "")'; }   # 상태 절의 마지막 비지 않은 줄
S1=$SECONDS

echo "### ① 나노 가지 · 진행 카드(착지 줄 없음) · 착지 → 상태 절 끝 = 착지 줄"
card_put 진행 r9001-x $'# 카드 ①\n\n## 상태\n- 진행 · 나노 발주\n'
mkpr 101 nano/r9001-x 'r9001 착지 줄'; land "$FIXB/ft-merge-land.sh" 101; B1="$(card_get 진행 r9001-x)"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ -n "$QL" ]; ck "① 착지 rc0 · LANDED 첫 줄" $?
[ "$(lands <<<"$B1")" = "$QL" ]; ck "① keeper 정규식 착지 sha 1개 = Q" $?
[ "$(sec_last <<<"$B1")" = "- 착지: $QL (w origin/main · PR #101 · ft-merge-land)" ]; ck "① 상태 절 끝 줄 = «- 착지: <Q> (리포 이름 origin/main · PR #101 · ft-merge-land)»" $?
[ "$(git -c core.quotepath=false -C "$CB" diff --name-only "$(tip)~1" "$(tip)")" = "$IX/진행/r9001-x.md" ] && [ "$(git -C "$CB" rev-list --count "$(tip)")" = 3 ]; ck "① 카드 ref 1커밋 · 바뀐 파일 = 그 카드 1개" $?
grep -qx "DONE 카드 착지 줄 r9001-x ${QL:0:10}" <<<"$out"; ck "① stdout DONE 1줄" $?
grep -q '^pr-close 101 ' "$STUB_LOG"; ck "① PR 닫기 그대로" $?

echo "### ② 상태 절 뒤 «## 근거» → 착지 줄은 «## 근거» 앞(상태 절 안)"
card_put 진행 r9002-y $'# 카드 ②\n\n## 상태\n- 진행\n\n## 근거\n- 근거 줄\n'
mkpr 102 nano/r9002-y 'r9002 근거 절'; land "$FIXB/ft-merge-land.sh" 102; B2="$(card_get 진행 r9002-y)"
[ "$rc" = 0 ] && [ "$(sec_last <<<"$B2")" = "- 착지: $QL (w origin/main · PR #102 · ft-merge-land)" ] \
  && [ "$(grep -n '^- 착지:' <<<"$B2" | cut -d: -f1)" -lt "$(grep -n '^## 근거' <<<"$B2" | cut -d: -f1)" ] && [ "$(tail -n1 <<<"$B2")" = "- 근거 줄" ]; ck "② 착지 줄 = 상태 절 끝 · «## 근거» 앞 · 근거 절 그대로" $?

echo "### ③ 같은 Q 착지 줄 이미 있음(--ff · Q = PR head) → 쓰기 0 · ALREADY"
mkpr 103 nano/r9003-z 'r9003 이미'; card_put 진행 r9003-z $'# 카드 ③\n\n## 상태\n- 착지: '"$PRSHA"$' (기록 나노)\n'; T3="$(tip)"
land "$FIXB/ft-merge-land.sh" 103 --ff
[ "$rc" = 0 ] && [ "$QL" = "$PRSHA" ] && [ "$(tip)" = "$T3" ] && [ "$(grep -c '^- 착지:' <<<"$(card_get 진행 r9003-z)")" = 1 ] && [ "$(grep -c '^ALREADY 카드 착지 줄 r9003-z' <<<"$out")" = 1 ]; ck "③ 카드 ref 그대로 · 착지 줄 1개 · ALREADY 1줄" $?

echo "### ④ 다른 sha 착지 줄 있음 → 쓰기 0 · WARN"
OTH="$(printf 'a%.0s' $(seq 40))"
card_put 진행 r9004-w $'# 카드 ④\n\n## 상태\n- 착지: '"$OTH"$' (옛 착지)\n'; T4="$(tip)"
mkpr 104 nano/r9004-w 'r9004 다른 착지'; land "$FIXB/ft-merge-land.sh" 104
[ "$rc" = 0 ] && [ "$(tip)" = "$T4" ] && [ "$(grep -c "^WARN 다른 착지 줄 $OTH" <<<"$out")" = 1 ]; ck "④ 카드 ref 그대로 · WARN 다른 착지 줄 <sha> 1줄 · 착지 rc0" $?

echo "### ⑤ 카드 토큰 없음 → 쓰기 0 · SKIP · 착지 rc0"
T5="$(tip)"; mkpr 105 feat/plain '코드만 고침'; land "$FIXB/ft-merge-land.sh" 105
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(tip)" = "$T5" ] && [ "$(grep -c '^SKIP 카드 없음' <<<"$out")" = 1 ]; ck "⑤ 카드 ref 그대로 · SKIP 카드 없음 1줄 · rc0" $?

echo "### ⑥ 카드 ref push 실패(pre-receive 거절) → 판정 불가 1줄 · 착지 rc·LANDED·PR 닫기·기준 헤드 그대로"
card_put 진행 r9006-v $'# 카드 ⑥\n\n## 상태\n- 진행\n'; T6="$(tip)"
printf '#!/bin/sh\necho "r2034 stub reject" >&2\nexit 1\n' > "$CB/hooks/pre-receive"; chmod +x "$CB/hooks/pre-receive"
mkpr 106 nano/r9006-v 'r9006 push 실패'; land "$FIXB/ft-merge-land.sh" 106; rm -f "$CB/hooks/pre-receive"
BHF="$(ls "$C/.fable-team/state/" | grep '^base-head' | head -n1)"
[ "$rc" = 0 ] && [[ "$out" == "LANDED pr=106 sha=$QL "* ]] && [ "$(tip)" = "$T6" ] && [ "$(grep -c '^판정 불가 — 카드 착지 줄 r9006-v ' <<<"$out")" = 1 ] \
  && grep -q '^pr-close 106 ' "$STUB_LOG" && [ "$(head -n1 "$C/.fable-team/state/$BHF")" = "$QL" ] && [ "$(sha "$ORIGIN" refs/heads/main)" = "$QL" ]; ck "⑥ rc0 · LANDED · 판정 불가 1줄 · 카드 ref 그대로 · PR 닫기 · 기준 헤드 = Q · 원격 main = Q" $?

echo "### ⑧ DA HOLD R1(A1): «## 상태» 절 없는 카드 → 문서 끝에 착지 줄 · 원문 그대로"
card_put 진행 r9011-no-state $'# 정상 텍스트 카드\n- 기존 본문\n'
mkpr 111 nano/r9011-no-state 'r9011 상태 절 없음'; land "$FIXB/ft-merge-land.sh" 111; B8="$(card_get 진행 r9011-no-state)"
[ "$rc" = 0 ] && [ "$B8" = $'# 정상 텍스트 카드\n- 기존 본문\n'"- 착지: $QL (w origin/main · PR #111 · ft-merge-land)" ] && [ "$(lands <<<"$B8")" = "$QL" ] \
  && grep -qx "DONE 카드 착지 줄 r9011-no-state ${QL:0:10}" <<<"$out"; ck "⑧ 문서 끝 착지 줄 1개 · 앞 본문 그대로 · DONE 1줄" $?

echo "### ⑨ DA HOLD 2 R2: 상태 절 있는 정상 카드 2장 · 같은 토큰 → 둘 다 착지 줄"
card_put 진행 r9012-a $'# 카드 ⑨a\n\n## 상태\n- 진행\n'; card_put 진행 r9012-b $'# 카드 ⑨b\n\n## 상태\n- 진행\n'
mkpr 112 ops/r9012-pair 'r9012 두 장'; land "$FIXB/ft-merge-land.sh" 112
for s in r9012-a r9012-b; do B9="$(card_get 진행 $s)"
  [ "$rc" = 0 ] && [ "$(lands <<<"$B9")" = "$QL" ] && [ "$(sec_last <<<"$B9")" = "- 착지: $QL (w origin/main · PR #112 · ft-merge-land)" ] \
    && [ "$(grep -c "^DONE 카드 착지 줄 $s ${QL:0:10}\$" <<<"$out")" = 1 ]; ck "⑨ $s 착지 줄 1개(keeper 정규식 = Q) · DONE 1줄" $?; done
! grep -q '^판정 불가 — 카드 착지 줄' <<<"$out"; ck "⑨ 판정 불가 0줄" $?
S2=$SECONDS

echo "### ⑦ 회귀: REJECT(승인 sha 어긋남)·DRY 는 카드 쓰기 0 · 출력 꼴 그대로"
card_put 진행 r9007-u $'# 카드 ⑦\n\n## 상태\n- 진행\n'; T7="$(tip)"
mkpr 107 nano/r9007-u 'r9007 거절'; apv --approve-sha "$PRSHA"; out="$(bash "$FIXB/ft-merge-land.sh" 107 --approve-sha "$M0" --repo "$W" 2>&1)"; rc=$?
[ "$rc" != 0 ] && ! grep -q '카드 착지 줄\|^SKIP 카드' <<<"$out" && [ "$(tip)" = "$T7" ]; ck "⑦ REJECT(rc≠0) · 카드 줄 0 · 카드 ref 그대로" $?
land "$FIXB/ft-merge-land.sh" 107 --dry
[ "$rc" = 0 ] && grep -q '^DRY ALLOW pr=107 ' <<<"$out" && ! grep -q '카드 착지 줄\|^SKIP 카드' <<<"$out" && [ "$(tip)" = "$T7" ]; ck "⑦ DRY ALLOW rc0 · 카드 줄 0 · 카드 ref 그대로" $?
S3=$SECONDS

echo "### 짝 사본 · 정규식 대조 · 줄 상한"
KL="$HERE/../../../../ft2/adapters/pi/keeper_land.py"; [ ! -f "$KL" ] || grep -qF "LAND = re.compile(r\"$LAND_RE\"" "$KL"; ck "keeper_land.py LAND 정규식 = 시험 정규식" $?
cmp -s "$BIN/ft-merge-land.sh" "$KIT/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"; ck "bin·kit cmp0(ft-merge-land·ft-merge-lib)" $?
[ "$(wc -l < "$BIN/ft-merge-land.sh" | tr -d ' ')" -le 120 ] && bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-merge-lib.sh"; ck "ft-merge-land.sh ≤ 120줄 · bash -n" $?

echo "단계별 초: ①~⑥ $((S2 - S1)) · ⑦ $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
