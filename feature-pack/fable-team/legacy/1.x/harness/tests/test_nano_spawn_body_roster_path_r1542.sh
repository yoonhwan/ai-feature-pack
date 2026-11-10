#!/usr/bin/env bash
# test_nano_spawn_body_roster_path_r1542.sh — r1542: 나노 첫 발주문(BODY)이 «실제 명부 경로»를 알려 주는가
#   ⓐ FT_SEATS_JSON=<임시>/seats-harness.json → BODY 에 «명부 = <그 절대경로>» 1줄 + «내 행은 spawn 이 이미 등록» + «손으로 쓰기 0»
#   ⓑ FT_SEATS_JSON 없음 → «명부 = <루트>/.fable-team/seats.json»(지금 기본값)
#   ⓒ 명부 줄은 BODY 안 1회 · 다른 고정 줄 순서·내용 변화 0 (고치기 직전 main 고정 sha BODY 와 «명부 줄만 지운» 비교)
#   ⓓ SEATBELT.md 부팅 ②·③ 이 «발주문의 명부 경로» 를 본다 · «.fable-team/seats.json» 은 기본값 설명으로만 남는다
#   ⓔ :9·:986 주석이 «명부(FT_SEATS_JSON) 등록»
#   변이 M1(BODY 명부 경로를 늘 .fable-team/seats.json 으로) → ⓐ FAIL · M2(명부 줄 삭제) → ⓐ ⓑ FAIL
# 꼴 = test_nano_spawn_body_press.sh · test_nano_spawn_body_search_roster.sh (정적 · BODY 줄 eval · tmux·send·실 좌석·실 우편함 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRACKED="$HERE/../../harness/bin/ft-nano-spawn.sh"
KIT="$HERE/../../harness/kit/fable-team/bin/ft-nano-spawn.sh"
SEATBELT="$HERE/../../skill/references/SEATBELT.md"
ROSTER_SENT='★명부 = $SEATS · 내 행은 spawn 이 이미 등록함 · 손으로 쓰기 0★'
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# emit_body <파일> <FT_SEATS_JSON 값 | 빈 문자열=없음> → BODY 전문 (해당 파일의 ^BODY= 줄을 그대로 eval)
#   SEATS 해석 줄(^SEATS=)도 파일에서 그대로 가져와 실행한다 — 명부 경로 규칙이 시험에 복사되지 않는다.
emit_body() {
  local f="$1" seats="$2" bodyf
  bodyf="$TMP/body-$RANDOM.txt"
  grep -m1 '^BODY=' "$f" > "$bodyf"
  [ -s "$bodyf" ] || { printf '\n'; return 0; }
  env -u FT_SEATS_JSON FT_SEATS_JSON="$seats" ROOT='/tmp/r1542-root' \
      IDX_WT='/tmp/r1542-wt' NEW_IDX='design/harness/indices/진행/r1542-card.md' \
      BRANCH='nano/r1542-nano-boot-roster-path-in-first-ord' FROM='byz-harness-master-pi#171' \
      WTDIR='/tmp/r1542-wt' SLUG='r1542-nano-boot-roster-path-in-first-ord' \
      _SBR='/tmp/r1542-wt/design/v65/SEATBELT-README.md' _SBR_REF='' \
      _WFX='' _NFX='' _SPX='' _SRX='' _AFX='' _RLX='' _PKX='' _EBN='' \
      bash -c 'if [ -n "$FT_SEATS_JSON" ]; then export FT_SEATS_JSON; fi   # ⓑ 갈래 = 환경변수 자체가 없다
               SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
               . "$1"; printf "%s" "$BODY"' _ "$bodyf"
}

# check_body <label> <파일> — ⓐ ⓑ ⓒ (BODY 관측점)
check_body() {
  local label="$1" f="$2" out_a out_b n
  out_a="$(emit_body "$f" '/tmp/r1542-roster/seats-harness.json')"
  out_b="$(emit_body "$f" '')"
  case "$out_a" in *"명부 = /tmp/r1542-roster/seats-harness.json"*) ok "$label ⓐ FT_SEATS_JSON 절대경로 그대로";; *) bad "$label ⓐ 명부 절대경로 줄 없음";; esac
  case "$out_a" in *"내 행은 spawn 이 이미 등록"*) ok "$label ⓐ spawn 이 등록함 문장";; *) bad "$label ⓐ '내 행은 spawn 이 이미 등록' 없음";; esac
  case "$out_a" in *"손으로 쓰기 0"*) ok "$label ⓐ 손으로 쓰기 0 문장";; *) bad "$label ⓐ '손으로 쓰기 0' 없음";; esac
  case "$out_b" in *"명부 = /tmp/r1542-root/.fable-team/seats.json"*) ok "$label ⓑ 기본값 명부 경로";; *) bad "$label ⓑ 기본값 명부 경로 없음";; esac
  n="$(printf '%s' "$out_a" | grep -o '명부 = ' | wc -l | tr -d ' ')"
  [ "$n" = "1" ] && ok "$label ⓒ 명부 줄 1회" || bad "$label ⓒ 명부 줄 ${n}회 (기대 1)"
}

bash -n "$TRACKED" && ok "bash -n 추적본" || bad "bash -n 추적본"
bash -n "$KIT" && ok "bash -n 키트" || bad "bash -n 키트"
cmp -s "$TRACKED" "$KIT" && ok "두 사본 cmp 동일" || bad "두 사본 cmp 불일치"
check_body "추적본" "$TRACKED"
check_body "키트" "$KIT"

# ── ⓒ 다른 고정 줄 변화 0 — 고치기 직전 main(고정 sha · r1132) BODY 에서 «명부 줄만» 지운 것과 같아야 한다(줄 삽입 1개) ──
BASE_SHA=f71635da7b26d09b3e732f4d9e89da199649f191   # 이 카드 착수 시점 main — 떠다니는 ref(origin/main) 금지(r1132 FLOATBASE)
strip_roster() { sed 's/★명부 = \$SEATS · 내 행은 spawn 이 이미 등록함 · 손으로 쓰기 0★ //'; }
REPO_ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
REL_TRACKED="$(git -C "$HERE" ls-files --full-name --error-unmatch "$TRACKED" 2>/dev/null)"
BASE=""
[ -n "$REPO_ROOT" ] && [ -n "$REL_TRACKED" ] && BASE="$(git -C "$REPO_ROOT" show "$BASE_SHA:$REL_TRACKED" 2>/dev/null)"
if [ -n "$BASE" ]; then
  printf '%s\n' "$BASE" | grep -m1 '^BODY=' | sed 's/^BODY=//' | strip_roster > "$TMP/base_stripped.txt"
  grep -m1 '^BODY=' "$TRACKED" | sed 's/^BODY=//' | strip_roster > "$TMP/new_stripped.txt"
  cmp -s "$TMP/base_stripped.txt" "$TMP/new_stripped.txt" && ok "ⓒ 나머지 고정 줄 base 와 동일" || bad "ⓒ 명부 줄 말고 다른 글자가 바뀌었다"
  printf '%s\n' "$BASE" | grep -q '★명부 = ' && bad "ⓒ base 에 이미 명부 줄이 있다(비교 기준 오염)" || ok "ⓒ base 명부 줄 0(삽입 1개)"
else
  echo "SKIP ⓒ base 대조 — $BASE_SHA 사본 없음(shallow clone)"
fi
# ⓒ-2 명부 경로 규칙은 SEATS 해석 줄 하나 = FT_SEATS_JSON 우선 · 기본값 $ROOT/.fable-team/seats.json
grep -q '^SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"' "$TRACKED" && ok "ⓒ SEATS 해석 줄 불변" || bad "ⓒ SEATS 해석 줄이 바뀌었다"
[ "$(grep -c '^SEATS="\${FT_SEATS_JSON:-' "$TRACKED")" = "1" ] && ok "ⓒ SEATS 해석 줄 1개" || bad "ⓒ SEATS 해석 줄 1개 아님"

# ── ⓓ SEATBELT.md 부팅 ②·③ ──
if [ -f "$SEATBELT" ]; then
  B2="$(grep -m1 '^② 내 자리' "$SEATBELT")"
  B2N="$(sed -n '/^② 내 자리/,/^③ 내 일/p' "$SEATBELT")"
  B3="$(grep -m1 '^③ 내 일' "$SEATBELT")"
  case "$B2" in *"발주문의 명부 경로"*) ok "ⓓ ② 가 발주문의 명부 경로를 본다";; *) bad "ⓓ ② 에 «발주문의 명부 경로» 없음";; esac
  case "$B2N" in *"FT_SEATS_JSON"*) ok "ⓓ ② 에 FT_SEATS_JSON 설명";; *) bad "ⓓ ② 에 FT_SEATS_JSON 없음";; esac
  case "$B2N" in *"기본값"*) ok "ⓓ ② 의 seats.json 은 기본값 설명";; *) bad "ⓓ ② 의 seats.json 이 기본값 설명이 아니다";; esac
  case "$B2" in *"cat <루트>/.fable-team/seats.json"*) bad "ⓓ ② 에 옛 고정 경로(cat <루트>/.fable-team/seats.json) 남음";; *) ok "ⓓ ② 옛 고정 경로 0";; esac
  case "$B3" in *"명부"*) ok "ⓓ ③ 이 명부를 본다";; *) bad "ⓓ ③ 에 «명부» 없음";; esac
  case "$B3" in *"index 경로"*) ok "ⓓ ③ index 경로 안내 유지";; *) bad "ⓓ ③ index 경로 안내 사라짐";; esac
  # 음성 대조 — 옛 문구로 되돌린 사본은 ⓓ 가 FAIL
  sed 's/^② 내 자리    : cat <발주문의 명부 경로>/② 내 자리    : cat <루트>\/.fable-team\/seats.json/' "$SEATBELT" > "$TMP/sb_old.md"
  cmp -s "$SEATBELT" "$TMP/sb_old.md" && bad "ⓓ 음성 대조: sed 가 ② 를 바꾸지 못함"
  grep -m1 '^② 내 자리' "$TMP/sb_old.md" | grep -q 'cat <루트>/.fable-team/seats.json' && ok "ⓓ 음성 대조: 옛 문구 사본에서 «옛 고정 경로» 검출" || bad "ⓓ 음성 대조 실패"
else
  bad "ⓓ SEATBELT.md 없음: $SEATBELT"
fi

# ── ⓔ 주석 2줄 = 명부(FT_SEATS_JSON) 등록 ──
n="$(grep -c '명부(FT_SEATS_JSON) 등록' "$TRACKED")"
[ "$n" = "2" ] && ok "ⓔ 주석 2줄 명부(FT_SEATS_JSON) 등록" || bad "ⓔ 주석 칸 ${n}개 (기대 2)"
[ "$(grep -c '⑤ *명부(FT_SEATS_JSON) 등록' "$TRACKED")" = "2" ] && ok "ⓔ ⑤ 단계 주석 2줄" || bad "ⓔ ⑤ 단계 주석 2개 아님"
grep -q '⑤seats.json 등록' "$TRACKED" && bad "ⓔ 옛 주석 «⑤seats.json 등록» 남음" || ok "ⓔ 옛 주석 0"

# ── 변이 M1 · M2 — 고친 것을 되돌린 사본은 ⓐ/ⓑ 가 FAIL ──
# M1: BODY 명부 경로를 늘 .fable-team/seats.json 으로(카드 ⓐ 위반)
sed 's|명부 = \$SEATS|명부 = /tmp/r1542-root/.fable-team/seats.json|' "$TRACKED" > "$TMP/m1.sh"
cmp -s "$TRACKED" "$TMP/m1.sh" && bad "M1 변이: sed 가 명부 경로를 바꾸지 못함"
before="$fail"; out="$(check_body "M1" "$TMP/m1.sh")"; fail="$before"
echo "$out" | grep -q '^FAIL M1 ⓐ 명부 절대경로 줄 없음' && ok "M1 ⓐ FAIL 검출" || bad "M1 인데 ⓐ FAIL 이 안 남"
# M2: 명부 줄 삭제
sed 's|★명부 = \$SEATS · 내 행은 spawn 이 이미 등록함 · 손으로 쓰기 0★ ||' "$TRACKED" > "$TMP/m2.sh"
cmp -s "$TRACKED" "$TMP/m2.sh" && bad "M2 변이: sed 가 명부 줄을 지우지 못함"
before="$fail"; out="$(check_body "M2" "$TMP/m2.sh")"; fail="$before"
echo "$out" | grep -q '^FAIL M2 ⓐ 명부 절대경로 줄 없음' && ok "M2 ⓐ FAIL 검출" || bad "M2 인데 ⓐ FAIL 이 안 남"
echo "$out" | grep -q '^FAIL M2 ⓑ 기본값 명부 경로 없음' && ok "M2 ⓑ FAIL 검출" || bad "M2 인데 ⓑ FAIL 이 안 남"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
