#!/usr/bin/env bash
# test_land_card_pair_exact_stem_r2411.sh — r2411: 착지 카드 짝짓기 = 가지 마지막 조각(FM_CARD_STEM)과 «이름이 정확히 같은» 카드가 있으면 그 카드만 · 없으면 지금대로 번호 앞머리
#   세계 = 임시 git 리포(카드 ref 트리 design/**/indices/*/*.md · 표 없음 = origin/main) · 실 PR·gh·mbox·네트워크·sleep 0
#   반례 ①~⑦(카드 r2411 동결) · 변이 M1~M3 = 사본 bin 1곳 + 원본 대조 · 기준판 42f98b9936 Red(①②③장부) · FT_R2411_BIN = 다른 bin 주입
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset FT_CARD_REF REPO GIT_DIR GIT_WORK_TREE FM_CARD_STEM FM_CARDS_T0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARN="$(cd "$HERE/.." && pwd -P)"
BIN="$(cd "${FT_R2411_BIN:-$HERE/../bin}" && pwd -P)"; KIT="$HERE/../kit/fable-team/bin"; T0=$SECONDS
fail=0; OUT=""; SE=""; ERR=""
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: out=[$OUT] err=[$ERR] se=[$SE]"; fail=$((fail + 1)); fi; }
miss() { ! "$@"; }
cnt() { printf '%s' "$1" | tr '|' '\n' | grep -c '\.md'; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
IX="design/harness/indices"
P="r2384-land-gate-worker-gateway-boot-test-pack"      # 실사건 19:56 팩 가지 이름 = 정확히 같은 카드
B="r2384-land-gate-worker-gateway-boot-test"           # 부모 카드(이름이 정확히 같으면 접두 카드들은 빠져야 한다)
Z="r2384-land-gate-worker-gateway-boot-test-byz"       # 형제 카드
mkw() {  # mkw <이름> <카드 상대경로…> — 카드 ref = origin/main · 카드는 index 에만
  local d="$T/$1" bl; shift; git init -q -b main "$d" || exit 1
  bl="$(printf '# 인덱스: x\n\n## 상태\n- 대기\n' | git -C "$d" hash-object -w --stdin)" || exit 1
  for c in "$@"; do git -C "$d" update-index --add --cacheinfo "100644,$bl,$c" || exit 1; done
  git -C "$d" commit -qm cards && git -C "$d" update-ref refs/remotes/origin/main HEAD || exit 1
}
pick() {  # pick <bin> <세계> <stem|-> <토큰…> → OUT(세계 기준 상대경로 «|» 이음) · SE(stderr) · ERR(FM_CARDS_ERR)
  local b="$1" d="$T/$2" st="$3" r; shift 3
  r="$(cd "$d" && . "$b/ft-merge-lib.sh" && { unset FM_CARD_STEM FM_CARDS_T0; [ "$st" = - ] || FM_CARD_STEM="$st"; fm_cards_by_tokens "$d" "$@" 2>"$T/se"; printf 'ERR=%s\n' "${FM_CARDS_ERR:-}"; } )"
  ERR="$(printf '%s\n' "$r" | sed -n 's/^ERR=//p' | paste -sd'|' -)"
  OUT="$(printf '%s\n' "$r" | grep -v '^ERR=' | sed '/^$/d' | sed "s|^$d/||" | paste -sd'|' -)"; SE="$(cat "$T/se")"
}
ledger() {  # ledger <bin> <세계> <PR> <가지> — ft-merge-land 와 같은 자리(fm_land_turn_first)로 장부 1줄 · stdout/stderr 버림
  ( cd "$T/$2" && . "$1/ft-merge-lib.sh" && { local q; q="$(git rev-parse HEAD)"; M="$q"; Q="$q"; HEADSHA="$q"; REPO="$T/$2"; TARGET=main; FT_SEAT=byz-harness-nano-x#0
      fm_land_turn_first "$T/$2" "$3" "$4" "PR $4 형제 카드" >/dev/null 2>&1; } )}
lg() { printf '%s\n' "$1" | grep -o 'design/[^"]*\.md' | paste -sd'|' -; }

mkw w1 "$IX/대기/$P.md" "$IX/대기/$B.md" "$IX/완성/$Z.md"
mkw w2 "$IX/대기/$B.md" "$IX/완성/$Z.md" "$IX/대기/$P.md"   # 부모 이름이 정확히 같은 세계(접두 형제 2장)
mkw w4 "$IX/대기/$P.md" "$IX/완성/$P.md"                    # 같은 이름이 두 단계 폴더
S1=$SECONDS

echo "### 반례 ①~⑦"
pick "$BIN" w1 "$P" r2384
ck "① 3장 중 정확한 이름 1장만" [ "$OUT" = "$IX/대기/$P.md" ]
ledger "$BIN" w1 9301 "nano/$P"
L1="$(grep '"pr": 9301' "$T/w1/.fable-team/state/land-record-turn.jsonl" 2>/dev/null)"
ck "① 장부 cards = 1장" [ "$(cnt "$(lg "$L1")")" = 1 ] && ck "① 장부 카드 = 정확한 이름" [ "$(lg "$L1")" = "$IX/대기/$P.md" ]

pick "$BIN" w2 "$B" r2384
ck "② 정확 일치 = basename 전체(접두 형제 2장 안 잡힘)" [ "$OUT" = "$IX/대기/$B.md" ]

pick "$BIN" w1 "$B-r9" r2384
ck "③ 정확한 이름 0장 = 지금대로 3장(K2 후퇴)" [ "$(cnt "$OUT")" = 3 ] && ck "③ 판정 불가 아님(cards_err 빈 값)" [ -z "$ERR" ]

pick "$BIN" w4 "$P" r2384
ck "④ 같은 이름이 두 단계 = 경로 2장 그대로" [ "$(cnt "$OUT")" = 2 ]

pick "$BIN" w1 - r2384
ck "⑤ FM_CARD_STEM 없음(기존 호출자) = 지금대로 3장" [ "$(cnt "$OUT")" = 3 ]

pick "$BIN" w1 "$P" r2384
ck "⑥ stdout = 경로만(INFO 0줄)" [ "$(printf '%s' "$OUT" | grep -c 'INFO')" = 0 ]
ck "⑥ stderr INFO 1줄(가지 조각 담김)" [ "$(printf '%s\n' "$SE" | grep -c "^INFO 카드 정확한 가지 이름 $P → 1장")" = 1 ]

pick "$BIN" w1 "$B-r9" r2384
ck "⑦ 좁힘 없음 = stderr 조용(INFO 0줄)" [ -z "$SE" ]
pick "$BIN" w4 "$P" r2384
ck "⑦ 정확 = 전체일 때도 INFO 0줄" [ -z "$SE" ]
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
c1() { pick "$1" w1 "$P" r2384; [ "$OUT" = "$IX/대기/$P.md" ]; }
c2() { pick "$1" w2 "$B" r2384; [ "$OUT" = "$IX/대기/$B.md" ]; }
c3() { pick "$1" w1 "$B-r9" r2384; [ "$(cnt "$OUT")" = 3 ]; }
if mut m1 'if [ -n "${FM_CARD_STEM:-}" ] && [ "${#hit[@]}" -gt 0 ]; then' 'if false; then'; then
  ck "M1 정확한 이름 먼저 빼기 → ① 잡힘" miss c1 "$T/m1"; ck "M1 원본 대조 ①" c1 "$BIN"
fi
if mut m2 '[ "${b%.md}" = "$FM_CARD_STEM" ] && xh' 'case "$b" in "$FM_CARD_STEM"*) true;; *) false;; esac && xh'; then
  ck "M2 접두 매칭으로 넓힘 → ② 잡힘" miss c2 "$T/m2"; ck "M2 원본 대조 ②" c2 "$BIN"
fi
if mut m3 '[ "${#xh[@]}" -gt 0 ] && [ "${#xh[@]}" -lt "${#hit[@]}" ]' '[ "${#xh[@]}" -lt "${#hit[@]}" ]'; then
  ck "M3 K2 후퇴 빼기(정확한 이름 0장 = 0장) → ③ 잡힘" miss c3 "$T/m3"; ck "M3 원본 대조 ③" c3 "$BIN"
fi
S3=$SECONDS

echo "### 기준판 42f98b9936 Red (착지 전 사본)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$HARN" archive 42f98b9936 -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-merge-lib.sh" ]; then
  pick "$BASE/bin" w1 "$P" r2384; ck "기준판 ① Red = 3장" [ "$(cnt "$OUT")" = 3 ]
  pick "$BASE/bin" w2 "$B" r2384; ck "기준판 ② Red = 3장" [ "$(cnt "$OUT")" = 3 ]
  ledger "$BASE/bin" w1 9302 "nano/$P"
  ck "기준판 ① 장부 Red = 3장" [ "$(cnt "$(lg "$(grep '"pr": 9302' "$T/w1/.fable-team/state/land-record-turn.jsonl")")")" = 3 ]
else echo "FAIL 기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fail=$((fail + 1)); fi
S4=$SECONDS

echo "### 회귀(기존 slug·retry·title·ref 규칙)"
for t in test_land_card_tokens_r1848.sh test_land_turn_card_from_branch_r1804.sh test_land_card_token_slug_r2123.sh test_land_card_token_retry_suffix_r2217.sh test_land_card_root_r1821.sh test_land_turn_cards_card_ref_r1743.sh; do
  if bash "$HERE/$t" >"$T/$t.log" 2>&1; then echo "PASS 회귀 $t"; else echo "FAIL 회귀 $t :: $(grep -c '^FAIL' "$T/$t.log") FAIL · $(tail -n1 "$T/$t.log")"; fail=$((fail + 1)); fi
done
S5=$SECONDS

echo "### 짝 사본"
ck "bin·kit cmp0(ft-merge-lib.sh)" cmp -s "$HERE/../bin/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"
ck "bash -n 새 lib" bash -n "$HERE/../bin/ft-merge-lib.sh"
echo "단계별 초: 준비 $((S1 - T0)) · 반례 $((S2 - S1)) · 변이 $((S3 - S2)) · 기준판 $((S4 - S3)) · 회귀 $((S5 - S4)) · 전체 $((SECONDS - T0))"
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
