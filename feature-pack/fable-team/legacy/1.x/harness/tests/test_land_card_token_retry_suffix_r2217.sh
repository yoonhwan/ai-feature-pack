#!/usr/bin/env bash
# test_land_card_token_retry_suffix_r2217.sh — r2217: 다시 딴 나노 가지(nano/<stem>-r<숫자>) 토큰이 0장이면 꼬리를 1회 떼고 <stem>.md 를 찾는다
#   세계 = 임시 git 리포(카드 ref 트리 design/**/indices/*/*.md · 표 없음 = origin/main) · ⑧ = cards.git(ops/main-base) + 카드 루트 clone
#   실 리포·실 PR·실 main·sleep 0 · 반례 ②~⑧(카드 r2217 동결 · ① = 기존 시험 재실행) · 변이 M1~M3 = 사본 bin 1곳 + 원본 대조
#   FT_R2217_BIN = 다른 bin(기준판) 주입
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset FT_CARD_REF REPO GIT_DIR GIT_WORK_TREE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "${FT_R2217_BIN:-$HERE/../bin}" && pwd -P)"; KIT="$HERE/../kit/fable-team/bin"; T0=$SECONDS
fail=0; OUT=""; ERR=""; SE=""
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: out=[$OUT] err=[$ERR] se=[$SE]"; fail=$((fail + 1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
RM="design/teams/room/indices/대기"; H="design/harness/indices/진행"; S="R-x-uuid"
mkw() {  # mkw <이름> <카드 상대경로…> — 카드 ref = origin/main(표 없음) · 카드는 index 에만
  local d="$T/$1" bl; shift; git init -q -b main "$d" || exit 1
  bl="$(printf '# 인덱스: x\n\n## 상태\n- 대기\n' | git -C "$d" hash-object -w --stdin)" || exit 1
  for c in "$@"; do git -C "$d" update-index --add --cacheinfo "100644,$bl,$c" || exit 1; done
  git -C "$d" commit -qm cards && git -C "$d" update-ref refs/remotes/origin/main HEAD || exit 1
}
pick() {  # pick <bin> <세계> <토큰> → OUT = 상대경로(«|» 이음) · ERR = FM_CARDS_ERR · SE = stderr
  local r; r="$(cd "$T/$2" && . "$1/ft-merge-lib.sh" && { fm_cards_by_tokens "$T/$2" "$3" 2>"$T/se"; printf 'ERR=%s\n' "$FM_CARDS_ERR"; })"
  ERR="$(printf '%s\n' "$r" | sed -n 's/^ERR=//p')"; OUT="$(printf '%s\n' "$r" | grep -v '^ERR=' | sed "s|^$T/$2/||" | paste -sd'|' -)"; SE="$(cat "$T/se")"
}
mkdir -p "$T/fk"; RG="$(command -v git)"   # O2: 가짜 git = 호출 1줄 적고 실 git
printf '#!/bin/bash\necho x >> "%s/gitlog"\nexec "%s" "$@"\n' "$T" "$RG" > "$T/fk/git"; chmod +x "$T/fk/git"
gcount() { : > "$T/gitlog"; PATH="$T/fk:$PATH" pick "$1" "$2" "$3"; wc -l < "$T/gitlog" | tr -d ' '; }

mkw w2 "$RM/$S.md"
mkw w3 "$RM/$S-r2.md" "$H/$S.md"
mkw w4 "$RM/R-y-other.md"
mkw w7 "design/teams/a/indices/대기/R-X-uuid.md" "design/teams/b/indices/진행/r-x_UUID.md"
info() { [ "$(printf '%s\n' "$SE" | grep -c '^INFO 카드 토큰 꼬리 뗌')" = 1 ] && printf '%s\n' "$SE" | grep -qx "INFO 카드 토큰 꼬리 뗌 $1 → $2"; }
c2() { pick "$1" w2 "$S-r2"; [ "$OUT" = "$RM/$S.md" ] && [ -z "$ERR" ] && info "$S-r2" "$S"; }
c3() { pick "$1" w3 "$S-r2"; [ "$OUT" = "$RM/$S-r2.md" ] && [ -z "$ERR" ] && ! printf '%s\n' "$SE" | grep -q '^INFO'; }
c4() { pick "$1" w4 "$S-r2"; [ -z "$OUT" ] && case "$ERR" in "토큰 $S-r2 카드 0장"*) true;; *) false;; esac; }
c5() { pick "$1" w2 "$S-r12"; [ "$OUT" = "$RM/$S.md" ] && info "$S-r12" "$S"; }
c5b() { pick "$1" w2 "$S-r2-r3"; [ -z "$OUT" ] && [ -n "$ERR" ]; }   # 꼬리 1회만(-r2-r3 → -r2 · R-x-uuid-r2.md 없음 = 0장)
c6() { local t; for t in "$S-rx" "$S-r" "$S-2"; do pick "$1" w2 "$t"; [ -z "$OUT" ] && [ -n "$ERR" ] || return 1; done; }
c7() { pick "$1" w7 r-x-uuid-r2; [ -z "$OUT" ] && case "$ERR" in "토큰 r-x-uuid slug 겹침 2장"*) true;; *) false;; esac; }   # slug 는 소문자 → 토큰도 소문자 꼴

CB="$T/cards.git"; C="$T/croot"; IX="design/harness/indices"
git init -q --bare -b ops/main-base "$CB"; git clone -q "$CB" "$C" 2>/dev/null; git -C "$C" checkout -q -b ops/main-base
mkdir -p "$C/$IX/진행" "$C/.fable-team/state"
printf 'harness\t.\torigin/ops/main-base\t%s\n' "$IX" > "$C/.fable-team/state/directive-roots.tsv"
printf '/.fable-team/\n' >> "$C/.git/info/exclude"
c8() {  # c8 <bin> — fm_land_card_line 끝에서 끝: 가지 nano/R-x-uuid-r2 · 카드 R-x-uuid.md → 상태 절 끝 착지 줄 1줄
  local q; q="$(printf '8%.0s' {1..40})"
  git -C "$C" fetch -q origin 2>/dev/null; git -C "$C" reset -q --hard origin/ops/main-base 2>/dev/null
  printf '# 카드 ⑧\n\n## 상태\n- 진행\n' > "$C/$IX/진행/$S.md"; git -C "$C" add -A && git -C "$C" commit -qm "card $1" && git -C "$C" push -q origin ops/main-base || return 1
  OUT="$(cd "$C" && . "$1/ft-merge-lib.sh" && fm_land_card_line "$C" 801 "$q" '다시 딴 가지' "nano/$S-r2" pack main 2>/dev/null)"
  ERR="$(git -C "$CB" show "ops/main-base:$IX/진행/$S.md")"
  [ "$(printf '%s\n' "$ERR" | tail -n1)" = "- 착지: $q (pack origin/main · PR #801 · ft-merge-land)" ] && [ "$(printf '%s\n' "$ERR" | grep -c '^- 착지:')" = 1 ]
}

S1=$SECONDS
echo "### 반례 ②~⑧"
ck "② R-x-uuid-r2 · R-x-uuid.md 만 → 1장 + INFO 꼬리 뗌 1줄" c2 "$BIN"
G2="$(gcount "$BIN" w2 "$S-r2")"; G0="$(gcount "$BIN" w2 "$S")"
ck "② O2 git 호출 수 = 정확한 이름 사례와 같음($G2 = $G0)" [ "$G2" = "$G0" ]
ck "③ R-x-uuid-r2.md · R-x-uuid.md 둘 다 → R-x-uuid-r2.md 1장만 · INFO 0" c3 "$BIN"
ck "④ 둘 다 없음 → 0장 + FM_CARDS_ERR(지금 꼴)" c4 "$BIN"
ck "⑤ R-x-uuid-r12 → R-x-uuid.md 1장" c5 "$BIN"
ck "⑤ R-x-uuid-r2-r3 → 꼬리 1회만(0장)" c5b "$BIN"
ck "⑥ -rx · -r · -2 → 꼬리 대조 0 · 0장" c6 "$BIN"
ck "⑦ 꼬리 뗀 토큰 slug 2장 → 0장 + slug 겹침" c7 "$BIN"
ck "⑧ fm_land_card_line nano/R-x-uuid-r2 → 상태 절 끝 착지 줄 1줄" c8 "$BIN"
S2=$SECONDS

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
if mut m1 '[ "${#hit[@]}" -eq 0 ] && [ -z "$serr" ] && fm_card_tail_pick' 'fm_card_tail_pick'; then
  ck "M1 꼬리 대조 먼저 → ③ 잡힘" miss c3 "$T/m1"; ck "M1 원본 대조 ③" c3 "$BIN"
fi
if mut m2 '=~ ^(.+)-r[0-9]+$ ]]' '=~ ^(.+)-r?[0-9]+$ ]]'; then
  ck "M2 꼬리 정규식 -[0-9]+ 로 넓힘 → ⑥ 잡힘" miss c6 "$T/m2"; ck "M2 원본 대조 ⑥" c6 "$BIN"
fi
if mut m3 'if [ "$n" -eq 1 ]; then hit[${#hit[@]}]="$c"; return 0' 'if c="${c%%$'"'"'\n'"'"'*}"; then hit[${#hit[@]}]="$c"; return 0'; then
  ck "M3 꼬리 slug 겹침 검사 빼기 → ⑦ 잡힘" miss c7 "$T/m3"; ck "M3 원본 대조 ⑦" c7 "$BIN"
fi
S3=$SECONDS

echo "### 짝 사본"
ck "bin·kit cmp0(ft-merge-lib.sh)" cmp -s "$HERE/../bin/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"
echo "단계별 초: 준비 $((S1 - T0)) · 반례 $((S2 - S1)) · 변이 $((S3 - S2)) · 전체 $((SECONDS - T0))"
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
