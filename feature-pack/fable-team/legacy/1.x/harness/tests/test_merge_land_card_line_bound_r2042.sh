#!/usr/bin/env bash
# test_merge_land_card_line_bound_r2042.sh — r2042: 착지 뒤 카드 착지 줄 상한 = 착지 본체 기준(fetch 상한 FTS + push 1단위 F+7) · 남은 총 마감으로 자름 · 고정 7초 폐기
#   세계 = r2034 시험과 같음: 코드 리포(_merge_fixture) + 카드 ref 리포(cards.git · ops/main-base) + 카드 루트 C · gh 스텁 · 실 좌석·실 리포 0
#   push 지연 스텁 = cards.git pre-receive 훅(N초 지연 뒤 성공 · 호출마다 1줄 기록) · sleep 은 그 훅 안에서만
#   반례 ①~⑥(카드 r2042 동결) · 변이·기준판 = FT_R2042_BIN=<사본 bin> 으로 같은 시험(원본 대조 = 인자 없이 1회)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each FT_CRITICAL_OFF=1
unset FT_LAND_CARD_LINE_S FT_LAND_DEADLINE FT_FETCH_TIMEOUT_SEC FT_PUSH_FIXED_S
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "${FT_R2042_BIN:-$HERE/../bin}" && pwd -P)"; KIT="$HERE/../kit/fable-team/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"
CB="$T/cards.git"; C="$T/croot"; IX="design/harness/indices"; HL="$T/hook.log"
git init -q --bare -b ops/main-base "$CB"; git clone -q "$CB" "$C" 2>/dev/null; git -C "$C" checkout -q -b ops/main-base
git -C "$C" config user.name t; git -C "$C" config user.email t@t; git -C "$C" config commit.gpgsign false
mkdir -p "$C/$IX/대기" "$C/$IX/진행" "$C/$IX/완성" "$C/.fable-team/state"
printf 'harness\t.\torigin/ops/main-base\t%s\n' "$IX" > "$C/.fable-team/state/directive-roots.tsv"
printf '/.fable-team/\n' >> "$(git -C "$C" rev-parse --git-path info/exclude | sed "s|^\.git|$C/.git|")"
printf '# 대기 카드\n\n## 상태\n- 대기\n' > "$C/$IX/대기/r9000-wait.md"
cm "$C" seed && git -C "$C" push -q origin ops/main-base
export FT_ROOT="$C" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/install-stub"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
exit 0
EOF
printf '#!/bin/bash\necho "OK n=1 (r2042 stub)"\nexit 0\n' > "$T/install-stub"; chmod +x "$T/gh-stub" "$T/install-stub"
FIXB="$T/bin"; cp -R "$BIN" "$FIXB"
printf '#!/bin/bash\nexit 0\n' > "$FIXB/ft-head-lag.sh"; printf '#!/bin/bash\nexit 0\n' > "$FIXB/ft-nano-record.sh"

card_put() {  # card_put <stem> <본문> — 카드 ref 에 1커밋(지연 훅 없이)
  rm -f "$CB/hooks/pre-receive"
  git -C "$C" fetch -q origin && git -C "$C" reset -q --hard origin/ops/main-base
  printf '%s' "$2" > "$C/$IX/진행/$1.md"; cm "$C" "card $1" && git -C "$C" push -q origin ops/main-base
}
slow() {  # slow <초> — 카드 ref push 지연 스텁(N초 뒤 성공 · 호출마다 hook.log 1줄)
  : > "$HL"; printf '#!/bin/sh\necho call >> "%s"\nsleep %s\nexit 0\n' "$HL" "$1" > "$CB/hooks/pre-receive"; chmod +x "$CB/hooks/pre-receive"
}
calls() { grep -c . "$HL" 2>/dev/null || true; }
card_get() { git -C "$CB" show "ops/main-base:$IX/진행/$1.md"; }
mkpr() {  # mkpr <번호> <head 가지> <제목>
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":sys.argv[3],"body":"본문","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$3" > "$STUB_JSON"
}
land() {  # land <번호> [env…] — ft-merge-land 1회(env 는 이 실행만)
  local n="$1"; shift; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"
  out="$(env "$@" bash "$FIXB/ft-merge-land.sh" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
  QL="$(sed -n 's/^LANDED pr=[0-9]* sha=\([0-9a-f]*\) .*/\1/p' <<<"$out")"
}
inv() {  # inv <번호> — ⑤ 착지 rc·LANDED 줄·PR 닫기·원격 main(기준 헤드) 불변
  [ "$rc" = 0 ] && grep -q "^LANDED pr=$1 sha=$QL " <<<"$out" && [ -n "$QL" ] && grep -q "^pr-close $1 " "$STUB_LOG" && [ "$(sha "$ORIGIN" refs/heads/main)" = "$QL" ]
}

S1=$SECONDS
echo "### ① push 스텁 9초 · 남은 마감 넉넉 → DONE · 착지 줄 1"
card_put r9101-a $'# 카드 ①\n\n## 상태\n- 진행\n'; slow 9
mkpr 201 nano/r9101-a 'r9101'; land 201 X=1
grep -qx "DONE 카드 착지 줄 r9101-a ${QL:0:10}" <<<"$out" && [ "$(grep -c "^- 착지: $QL " <<<"$(card_get r9101-a)")" = 1 ]; ck "① DONE 1줄 · 카드 착지 줄 1개" $?
inv 201; ck "⑤-① 착지 rc0 · LANDED · PR 닫기 · 원격 main = Q" $?
S2=$SECONDS

echo "### ② 남은 마감 < push 1단위(F+7=14) → 시도 0 · «마감 부족» 1줄"
card_put r9102-b $'# 카드 ②\n\n## 상태\n- 진행\n'; slow 0
mkpr 202 nano/r9102-b 'r9102'; land 202 FT_LAND_DEADLINE=$(( $(date +%s) + 8 ))
[ "$(calls)" = 0 ] && [ "$(grep -cE '^판정 불가 — 카드 착지 줄 r9102 마감 부족\(남은 [0-9]+초\)$' <<<"$out")" = 1 ] && ! grep -q '^- 착지:' <<<"$(card_get r9102-b)"; ck "② 스텁 호출 0 · 마감 부족 1줄 · 카드 쓰기 0" $?
inv 202; ck "⑤-② 착지 rc0 · LANDED · PR 닫기 · 원격 main = Q" $?
S3=$SECONDS

echo "### ③ push 스텁 1초 → DONE"
card_put r9103-c $'# 카드 ③\n\n## 상태\n- 진행\n'; slow 1
mkpr 203 nano/r9103-c 'r9103'; land 203 X=1
grep -qx "DONE 카드 착지 줄 r9103-c ${QL:0:10}" <<<"$out" && [ "$(calls)" = 1 ]; ck "③ DONE 1줄 · 스텁 호출 1" $?
inv 203; ck "⑤-③ 착지 rc0 · LANDED · PR 닫기 · 원격 main = Q" $?
S4=$SECONDS

echo "### ④ push 스텁 > 상한(fetch 2 + push F1+7 = 10초) → «시간 초과(10초)» 1줄"
card_put r9104-d $'# 카드 ④\n\n## 상태\n- 진행\n'; slow 13
mkpr 204 nano/r9104-d 'r9104'; land 204 FT_FETCH_TIMEOUT_SEC=2 FT_PUSH_FIXED_S=1
[ "$(grep -c '^판정 불가 — 카드 착지 줄 r9104 시간 초과(10초)$' <<<"$out")" = 1 ] && ! grep -q '카드 착지 줄 .*7초' <<<"$out"; ck "④ 시간 초과(10초) 1줄 · 숫자 = 계산 상한" $?
inv 204; ck "⑤-④ 착지 rc0 · LANDED · PR 닫기 · 원격 main = Q" $?
rm -f "$CB/hooks/pre-receive"; S5=$SECONDS

echo "### ⑥ 회귀 · 짝 사본"
cmp -s "$BIN/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh" && cmp -s "$BIN/ft-merge-land.sh" "$KIT/ft-merge-land.sh"; ck "bin·kit cmp0" $?
bash -n "$BIN/ft-merge-lib.sh"; ck "ft-merge-lib.sh bash -n" $?

echo "단계별 초: ① $((S2 - S1)) · ② $((S3 - S2)) · ③ $((S4 - S3)) · ④ $((S5 - S4)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
