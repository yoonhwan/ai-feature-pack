#!/usr/bin/env bash
# test_merge_land_card_only_pr_r2248.sh — r2248: 카드 파일(design/**/indices/**)만 바꾼 PR 을 ft-merge-land 가 합치면 카드 «- 착지:» 줄 0 · 장부 카드 짝 0 · 나노 닫기 줄 0
#   세계 A = test_merge_land_card_land_line_r2034 꼴(코드 리포 W + 카드 ref 리포 cards.git ops/main-base · gh 스텁 · bin 사본) — ① ③ ④ ⑤ ⑦ + ② 장부 행
#   세계 B = _nano_record_r1717_fixture(가짜 명부·mbox·tmux) — ② 나노 기록 due(별 프로세스 `--due` · 변수 섞임 0)
#   FT_R2248_BIN = 시험할 bin(기본 추적본 · 기준판·변이 사본) · FT_R2248_ONLY = 돌릴 사례(c1 c2 c3 c4 c5 c7 · 빈 값 = 전부) · 기준판 Red·변이 M1~M3 = 짝 시험 test_merge_land_card_only_pr_mut_r2248.sh(70초 상한 · 쪼갬)
#   실 좌석·실 리포·실 gh·네트워크 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
BIN="$(cd "${FT_R2248_BIN:-$HERE/../bin}" && pwd -P)"; KIT="$HERE/../kit/fable-team/bin"; ONLY="${FT_R2248_ONLY:-}"
want() { [ -z "$ONLY" ] || [[ " $ONLY " == *" $1 "* ]]; }

if [ "${1:-}" = --due ]; then   # 반례 ②(나노 기록 쪽): 카드 쥔 나노가 살아 있어도 카드 파일만 착지 = due 에 닫기 줄 0
  R1717_BIN="$BIN"; . "$HERE/_nano_record_r1717_fixture.sh"; world
  s=r9002-x; pr=202; n="byz-harness-nano-r9002#0"; fresh; card "$s"; seats "$n|nano|$s"
  M="$(g "$PACK" rev-parse origin/main)"; g "$PACK" checkout -q -B w2 "$M"; mkdir -p "$PACK/$IDX/대기"; echo set > "$PACK/$IDX/대기/$s.md"
  g "$PACK" add -A; g "$PACK" commit -qm set; S="$(g "$PACK" rev-parse HEAD)"; Q="$(g "$PACK" commit-tree "$S^{tree}" -p "$M" -m squash)"
  ( set +u; . "$BIN/ft-merge-lib.sh"; REPO="$PACK"; TARGET=main; HEADSHA="$S"; FT_SEAT="byz-harness-planner-pi#1"
    fm_card_only "$PACK" "$M" "$Q"; fm_land_turn_first "$ROOT" "$pr" "docs/r9002-set" "r9002 세트 줄" ) >/dev/null 2>&1
  L="$(grep "\"pr\": $pr, " "$STATE/land-record-turn.jsonl")"
  has "② 장부 행 cards [] · card_only" "$L" '"cards": [], "ts"'; has "② 장부 card_only 표시" "$L" '"card_only": true'
  rec due --pr "$pr" --no-fetch; eq "② due rc0" "$RC" 0
  hasnt "② due 에 나노 닫기 차례 0" "$OUT" "차례 $n"; has "② due = 끝 PR#$pr" "$OUT" "끝 PR#$pr pr=$pr "
  finish
fi

export FT_AUTONOMY_LEVEL=each FT_CRITICAL_OFF=1
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
worlda() {  # 세계 A 준비(①③④⑤⑦ 을 돌릴 때만 · ② 만이면 0)
  mkrepo "$T"; mkdir -p "$T/state"; ghremote "$W" "$ORIGIN" o/w   # r1746: 원장 루트(카드 리포) ≠ 착지 리포 = github 꼴 원격 필요(전송은 가짜 ssh → 로컬 bare)
  CB="$T/cards.git"; C="$T/croot"; IX="design/harness/indices"; LEDGER="$C/.fable-team/state/land-record-turn.jsonl"
  git init -q --bare -b ops/main-base "$CB"; git clone -q "$CB" "$C" 2>/dev/null; git -C "$C" checkout -q -b ops/main-base
  git -C "$C" config user.name t; git -C "$C" config user.email t@t; git -C "$C" config commit.gpgsign false
  mkdir -p "$C/$IX/대기" "$C/$IX/진행" "$C/$IX/완성" "$C/.fable-team/state"
  printf 'harness\t.\torigin/ops/main-base\t%s\n' "$IX" > "$C/.fable-team/state/directive-roots.tsv"
  printf '/.fable-team/\n' >> "$(git -C "$C" rev-parse --git-path info/exclude | sed "s|^\.git|$C/.git|")"
  printf '# 대기 카드\n\n## 상태\n- 대기\n' > "$C/$IX/대기/r9000-wait.md"; cm "$C" seed && git -C "$C" push -q origin ops/main-base
  export FT_ROOT="$C" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/install-stub"
  printf '#!/bin/bash\necho "$*" >> "$STUB_LOG"\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\nexit 0\n' > "$T/gh-stub"
  printf '#!/bin/bash\necho "OK n=1 (r2248 stub)"\nexit 0\n' > "$T/install-stub"; chmod +x "$T/gh-stub" "$T/install-stub"
  FIXB="$T/bin"; cp -R "$BIN" "$FIXB"; rm -rf "$FIXB/__pycache__"
  printf '#!/bin/bash\nexit 0\n' > "$FIXB/ft-head-lag.sh"; printf '#!/bin/bash\nexit 0\n' > "$FIXB/ft-nano-record.sh"
  mkdir -p "$T/gitw"; printf '#!/bin/bash\ncase " $* " in *" diff --no-renames --name-only -z "*) [ -z "${FT_R2248_DIFF_FAIL:-}" ] || { echo "r2248 stub diff fail" >&2; exit 128; };; esac\nexec "%s" "$@"\n' "$(command -v git)" > "$T/gitw/git"; chmod +x "$T/gitw/git"
}
WA=""; for c in c1 c3 c4 c5 c7; do want "$c" && WA=1; done; [ -z "$WA" ] || worlda

card_put() {  # card_put <단계> <stem> — 카드 ref 에 착지 줄 없는 카드 1장
  git -C "$C" fetch -q origin && git -C "$C" reset -q --hard origin/ops/main-base
  printf '# 카드 %s\n\n## 상태\n- 진행\n' "$2" > "$C/$IX/$1/$2.md"; cm "$C" "card $2" && git -C "$C" push -q origin ops/main-base
}
card_lands() { git -C "$CB" show "ops/main-base:$IX/$1/$2.md" | grep -c '^- 착지:'; }
tip() { git -C "$CB" rev-parse ops/main-base; }
pr_push() {  # pr_push <번호> <가지> <제목> — W 의 지금 가지 → refs/pull/N/head + 스텁 JSON
  git -C "$W" push -q -f origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":sys.argv[3],"body":"본문","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$3" > "$STUB_JSON"
}
mkpr_f() {  # mkpr_f <번호> <가지> <제목> <파일…> — origin/main 위 1커밋(그 파일들만 바꿈)
  local n="$1" b="$2" ti="$3" f; shift 3
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$n" origin/main
  for f in "$@"; do mkdir -p "$W/$(dirname "$f")"; echo "pr$n" >> "$W/$f"; done; cm "$W" "pr $n"; pr_push "$n" "$b" "$ti"
}
land() {  # land <번호> [추가 인자…]
  local n="$1"; shift; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"
  out="$(bash "$FIXB/ft-merge-land.sh" "$n" --approve-sha "$PRSHA" --repo "$W" "$@" 2>&1)"; rc=$?
}
lrow() { grep "\"pr\": $1, " "$LEDGER" 2>/dev/null; }
ncards() { lrow "$1" | python3 -c 'import json,sys;print(len(json.loads(sys.stdin.read())["cards"]))' 2>/dev/null; }

c1() {
  echo "### ① 카드 파일 1개만 바꾼 PR(제목 r9001 · 가지 docs/r9001-set) → SKIP 1줄 · 카드 착지 줄 0 · 카드 ref push 0 · ② 장부 cards []"
  card_put 진행 r9001-x; local t1; t1="$(tip)"
  mkpr_f 201 docs/r9001-set 'r9001 세트 줄' "$IX/대기/r9001-x.md"; land 201
  [ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(grep -c '^SKIP 카드 파일만 바꾼 PR #201 — 카드 착지 줄 쓰기 0$' <<<"$out")" = 1 ] && [ "$(tip)" = "$t1" ] && [ "$(card_lands 진행 r9001-x)" = 0 ]
  ck "① rc0 · LANDED · SKIP 카드 파일만 1줄 · 카드 ref 그대로 · 착지 줄 0" $?
  [ "$(lrow 201 | grep -c .)" = 1 ] && [ "$(ncards 201)" = 0 ] && lrow 201 | grep -q '"card_only": true'; ck "② 장부 행 1 · cards [] · card_only 표시" $?
}
c3() {
  echo "### ③ 카드 파일 + 코드 파일 PR → 착지 줄 1(지금 판 그대로) · 짝 1"
  card_put 진행 r9003-x; mkpr_f 203 nano/r9003-x 'r9003 코드' "$IX/대기/r9003-x.md" x3.sh; land 203
  local q; q="$(sed -n 's/^LANDED pr=203 sha=\([0-9a-f]*\) .*/\1/p' <<<"$out")"
  [ "$rc" = 0 ] && [ -n "$q" ] && [ "$(grep -c "^DONE 카드 착지 줄 r9003-x ${q:0:10}$" <<<"$out")" = 1 ] && [ "$(card_lands 진행 r9003-x)" = 1 ] && [ "$(ncards 203)" -ge 1 ] && ! grep -q 'SKIP 카드 파일만' <<<"$out"
  ck "③ DONE 착지 줄 1 · 장부 cards ≥1(짝 있음 · 카드 ref + 착지 리포 두 곳이면 2) · SKIP 0" $?
}
c4() {
  echo "### ④ design/guides 문서 1개만 바꾼 PR(카드 번호 단 제목) → 착지 줄 1(결과물 docs = 지금 판 그대로)"
  card_put 진행 r9004-x; mkpr_f 204 docs/r9004-guide 'r9004 지침 문서' design/guides/r9004.md; land 204
  [ "$rc" = 0 ] && [ "$(grep -c '^DONE 카드 착지 줄 r9004-x ' <<<"$out")" = 1 ] && [ "$(card_lands 진행 r9004-x)" = 1 ] && [ "$(ncards 204)" = 1 ]
  ck "④ DONE 착지 줄 1 · 장부 cards 1" $?
}
c5() {
  echo "### ⑤ M..Q git diff 실패(가짜 git) → 판정 불가 1줄 · 착지 줄 0 · 짝 0 · 착지 rc0"
  card_put 진행 r9005-x; local t5; t5="$(tip)"; mkpr_f 205 nano/r9005-x 'r9005 diff 실패' x5.sh
  export FT_R2248_DIFF_FAIL=1; local op="$PATH"; PATH="$T/gitw:$PATH"; land 205; PATH="$op"; unset FT_R2248_DIFF_FAIL
  [ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(grep -c '^판정 불가 — 카드 파일만 판정 git diff 실패 rc=128$' <<<"$out")" = 1 ] && [ "$(grep -c '^판정 불가 — 카드 파일만' <<<"$out")" = 1 ] && [ "$(tip)" = "$t5" ] && [ "$(ncards 205)" = 0 ]
  ck "⑤ rc0 · LANDED · 판정 불가 1줄 · 카드 ref 그대로 · 장부 cards 0" $?
}
c7() {
  echo "### ⑦ --ff · 커밋 2개(코드 → 카드 파일만) → 착지 줄 1 · 짝 1(M 기준 = PR 커밋 전부)"
  card_put 진행 r9007-x; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B pr207 origin/main
  echo c > "$W/x7.sh"; cm "$W" code; mkdir -p "$W/$IX/대기"; echo set > "$W/$IX/대기/r9007-x.md"; cm "$W" card
  pr_push 207 nano/r9007-x 'r9007 ff 코드+카드'; land 207 --ff
  [ "$rc" = 0 ] && grep -q "^LANDED pr=207 sha=$PRSHA .*mode=ff" <<<"$out" && [ "$(grep -c "^DONE 카드 착지 줄 r9007-x ${PRSHA:0:10}$" <<<"$out")" = 1 ] && [ "$(card_lands 진행 r9007-x)" = 1 ] && [ "$(ncards 207)" -ge 1 ]
  ck "⑦ ff 착지 · DONE 착지 줄 1 · 장부 cards ≥1(짝 있음)" $?
}

if [ -z "$ONLY" ]; then
  echo "### 사전: bin·kit 짝 cmp0 · bash -n(/bin/bash 3.2 포함)"
  for f in ft-merge-land.sh ft-merge-lib.sh; do cmp -s "$HERE/../bin/$f" "$KIT/$f"; ck "짝 사본 cmp0 $f" $?; bash -n "$HERE/../bin/$f" && /bin/bash -n "$HERE/../bin/$f"; ck "bash -n $f" $?; done
fi
S1=$SECONDS
for c in c1 c3 c4 c5 c7; do want "$c" && "$c"; done
S2=$SECONDS
if want c2; then o="$(FT_R2248_BIN="$BIN" bash "$SELF" --due 2>&1)"; r=$?; printf '%s\n' "$o" | grep -E '^(PASS|FAIL)'; rc=$r; out="$o"; [ "$r" = 0 ]; ck "② 나노 기록 due(세계 B) 전부 PASS" $?; fi
S3=$SECONDS

echo "단계별 초: 준비 $((S1 - T0)) · 세계 A $((S2 - S1)) · 세계 B $((S3 - S2)) · 전체 $((SECONDS - T0))"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
