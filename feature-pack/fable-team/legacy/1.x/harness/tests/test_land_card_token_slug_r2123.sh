#!/usr/bin/env bash
# test_land_card_token_slug_r2123.sh — r2123: 1.x 나노 가지 토큰(nano/<_slug(카드,40)>)으로 대문자·긴 이름 카드를 찾는다
#   세계 = 임시 git 리포(카드 ref 트리 design/**/indices/*/*.md) · directive-roots.tsv 없음(origin/main)·있음(origin/ops/main-base)
#   토큰 = 실제 bin/ft-nano-spawn.sh 의 _slug 정의(원본 · 변이 0) · 실 리포·실 PR·실 우편함·sleep 0
#   반례 ①~⑦(카드 r2123 동결) · 변이 M1~M4 = 사본 bin 에 1곳 바꿈 + 원본으로 같은 사례 1회 더(반대 결과 대조)
#   FT_R2123_BIN = 다른 bin(기준판) 주입
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset FT_CARD_REF REPO GIT_DIR GIT_WORK_TREE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "${FT_R2123_BIN:-$HERE/../bin}" && pwd -P)"; KIT="$HERE/../kit/fable-team/bin"; T0=$SECONDS
eval "$(grep -E '^_slug\(\) \{' "$HERE/../bin/ft-nano-spawn.sh")"   # 가지 이름 규칙 원본(:170)
fail=0; OUT=""; ERR=""
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: out=[$OUT] err=[$ERR]"; fail=$((fail + 1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
RM="design/teams/room/indices/대기"; H="design/harness/indices/대기"
mkw() {  # mkw <이름> <카드 ref> <카드 상대경로…> — 카드 ref = origin/main 이면 표 없음 · 아니면 표 1행
  #   카드는 index 에만 넣는다(macOS 대소문자 무시 디스크에서 r-room-a.md · R-room-a.md 가 한 파일이 되지 않게)
  local d="$T/$1" ref="$2" bl; shift 2; git init -q -b main "$d" || exit 1
  bl="$(printf '# 인덱스: x\n\n## 상태\n- 대기\n' | git -C "$d" hash-object -w --stdin)" || exit 1
  for c in "$@"; do git -C "$d" update-index --add --cacheinfo "100644,$bl,$c" || exit 1; done
  git -C "$d" commit -qm cards && git -C "$d" update-ref "refs/remotes/$ref" HEAD || exit 1
  mkdir -p "$d/.fable-team/state"
  [ "$ref" = origin/main ] || printf 'harness\t.\t%s\tdesign/harness/indices\n' "$ref" > "$d/.fable-team/state/directive-roots.tsv"
}
pick() {  # pick <bin> <세계> <토큰> → OUT = 세계 기준 상대경로(줄 → «|») · ERR = FM_CARDS_ERR
  local r; r="$(cd "$T/$2" && . "$1/ft-merge-lib.sh" && { fm_cards_by_tokens "$T/$2" "$3" 2>/dev/null; printf 'ERR=%s\n' "$FM_CARDS_ERR"; })"
  ERR="$(printf '%s\n' "$r" | sed -n 's/^ERR=//p')"; OUT="$(printf '%s\n' "$r" | grep -v '^ERR=' | sed "s|^$T/$2/||" | paste -sd'|' -)"
}
N2="R-room-runner-reconnect-lang-prepare-state"; N3="Room_Runner_Reconnect_Lang_Prepare_State_Extra_Abc"
N4="R-room-abcdefghij-abcdefghij-abcdefghij-tail"; N5A="${N3%_Abc}_One"; N5B="${N3%_Abc}_Two"
mkw w1 origin/main "$RM/r-room-a.md" "$RM/R-room-a.md"
mkw w2 origin/main "$RM/$N2.md"
mkw w2t origin/ops/main-base "$RM/$N2.md"
mkw w3 origin/main "$RM/$N3.md"
mkw w4 origin/main "$H/$N4.md"
mkw w5 origin/main "$RM/$N5A.md" "$RM/$N5B.md"
mkw w6 origin/main "design/teams/a/indices/대기/R-x-card.md" "design/teams/b/indices/진행/r-X-card.md"
mkw w7 origin/main "$H/r1234-x.md" "$H/R1234-x.md"
S2="$(_slug "$N2" 40)"; S3="$(_slug "$N3" 40)"; S4="$(_slug "$N4" 40)"; S5="$(_slug "$N5A" 40)"

c1() { pick "$1" w1 r-room-a; [ "$OUT" = "$RM/r-room-a.md" ]; }
c2() { pick "$1" w2 "$S2"; [ "$OUT" = "$RM/$N2.md" ] && [ -z "$ERR" ]; }
c2t() { pick "$1" w2t "$S2"; [ "$OUT" = "$RM/$N2.md" ] && [ -z "$ERR" ]; }
c3() { pick "$1" w3 "$S3"; [ "$OUT" = "$RM/$N3.md" ]; }
c4() { pick "$1" w4 "$S4"; [ "$OUT" = "$H/$N4.md" ]; }
c5() { pick "$1" w5 "$S5"; [ -z "$OUT" ] && case "$ERR" in "토큰 $S5 slug 겹침 2장"*) true;; *) false;; esac; }
c5l() {  # ⑤ 착지 줄 = SKIP 카드 없음 — … slug 겹침 2장
  OUT="$(cd "$T/w5" && . "$1/ft-merge-lib.sh" && fm_land_card_line "$T/w5" 1 "$(printf 'a%.0s' {1..40})" t "nano/$S5" pack main 2>/dev/null)"
  case "$OUT" in "SKIP 카드 없음 — 토큰 $S5 slug 겹침 2장"*) true;; *) false;; esac
}
c6() { pick "$1" w6 r-x-card; [ -z "$OUT" ] && case "$ERR" in "토큰 r-x-card slug 겹침 2장"*) true;; *) false;; esac; }
c7() { pick "$1" w7 r1234; [ "$OUT" = "$H/r1234-x.md" ]; }

echo "### 토큰 = _slug 원본: ②=$S2(${#S2}) ③=$S3(${#S3}) ④=$S4(${#S4}) ⑤=$S5"
ck "② 토큰 = nano/<slug> 의 fm_card_tokens" [ "$(. "$BIN/ft-merge-lib.sh" && fm_card_tokens "nano/$S2" x)" = "$S2" ]
ck "① 정확한 이름 먼저(r-room-a.md 1장 · R-room-a.md 0)" c1 "$BIN"
ck "② 대문자 카드 · 40자 slug 토큰 → 1장(표 없음)" c2 "$BIN"
ck "② 대문자 카드 · 40자 slug 토큰 → 1장(표 있음 · ops/main-base)" c2t "$BIN"
ck "③ 50자(대문자·_) 카드 → 1장" c3 "$BIN"
ck "④ 40자째 «-» · 끝 - 지운 토큰 → 1장" c4 "$BIN"
ck "⑤ 앞 40자 같은 2장 → 0장 · slug 겹침 2장" c5 "$BIN"
ck "⑤ fm_land_card_line = SKIP 카드 없음 — slug 겹침 2장" c5l "$BIN"
ck "⑥ 다른 팀 폴더 같은 slug 2장 → 0장 · slug 겹침 2장" c6 "$BIN"
ck "⑦ r1234 → r1234-x.md 만" c7 "$BIN"

echo "### 변이(사본 · 원본 대조)"
mut() {  # mut <이름> <옛 글자> <새 글자> — 사본 bin 에 정확히 1곳
  rm -rf "$T/$1"; cp -R "$BIN" "$T/$1"
  python3 - "$T/$1/ft-merge-lib.sh" "$2" "$3" <<'PY' || { echo "FAIL $1 변이 못 끼움"; fail=$((fail + 1)); return 1; }
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
miss() { ! "$@"; }
if mut m1 '[ -z "$st" ] || cand=' 'true || cand='; then
  ck "M1 slug 대조 지움 → ② 잡힘" miss c2 "$T/m1"; ck "M1 slug 대조 지움 → ③ 잡힘" miss c3 "$T/m1"
  ck "M1 원본 대조 ②" c2 "$BIN"; ck "M1 원본 대조 ③" c3 "$BIN"
fi
if mut m2 'case "$ex " in *" $t "*) continue;; esac' ':'; then
  ck "M2 정확한 이름 먼저 지움 → ① 잡힘" miss c1 "$T/m2"; ck "M2 원본 대조 ①" c1 "$BIN"
fi
if mut m3 'if [ "$n" -eq 1 ]; then' 'if c="${c%%$'"'"'\n'"'"'*}"; then'; then
  ck "M3 겹침 첫 장 잡음 → ⑤ 잡힘" miss c5 "$T/m3"; ck "M3 겹침 첫 장 잡음 → ⑥ 잡힘" miss c6 "$T/m3"
  ck "M3 원본 대조 ⑤" c5 "$BIN"; ck "M3 원본 대조 ⑥" c6 "$BIN"
fi
if mut m4 's=substr(s,1,40); ' ''; then
  ck "M4 40자 자르기 지움 → ③ 잡힘" miss c3 "$T/m4"; ck "M4 40자 자르기 지움 → ④ 잡힘" miss c4 "$T/m4"
  ck "M4 원본 대조 ③" c3 "$BIN"; ck "M4 원본 대조 ④" c4 "$BIN"
fi

echo "### 짝 사본"
ck "bin·kit cmp0(ft-merge-lib.sh)" cmp -s "$HERE/../bin/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"
echo "단계별 초: 전체 $((SECONDS - T0))"
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
