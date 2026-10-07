#!/usr/bin/env bash
# test_press_baseline_check.sh — #834 press 기준선 게이트 ⑥ (설계 DESIGN-834-baseline-gate-arch165.md §7 C2 + «C2 잔여 2»).
#   고정 입력 임시 git 저장소만 사용 · 실제 press·오디오 0. 전 케이스를 «ft-press-gate.sh 최종 exit» 로 단언:
#   SELFTEST 성공 = 3 · 막힘 = 1 · 보통 모드에 SELFTEST 상속 = 1 · SELFTEST 출력에 «발화해도 된다» 0건.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
GATE="$BIN/ft-press-gate.sh"
fail=0; n=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
bash -n "$BIN/ft-press-baseline-check.sh" && ok "bash -n baseline-check" || bad "bash -n baseline-check"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/worker" "$R/design/v65/baselines/ev" "$R/cards" "$T/root/.fable-team"
echo '{}' > "$T/root/.fable-team/seats.json"
git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo 'x = 1' > "$R/worker/a.py"
cat > "$R/design/v65/baselines/FLAGS.md" <<'EOF'
| key | 기본값 | OFF 값 | 읽는 자리 |
|---|---|---|---|
| `V65_TOGGLE_A` | `1` | `0` | worker/a.py:1 |
| `V65_TOGGLE_B` | `off` | `off` | worker/a.py:1 |
EOF
git -C "$R" add -A && git -C "$R" commit -qm base
SHA="$(git -C "$R" rev-parse HEAD)"
OKFLAGS="V65_TOGGLE_A=1,V65_TOGGLE_B=off"

result() { # 파일 set_sha session_id → 러너 RESULT json
  printf '{"set_sha":"%s","side_lang_at_press":{"right":"ko","left":"en"},"session_id":"%s","failed":true}\n' "$2" "$3" > "$1"; }
result "$R/design/v65/baselines/ev/RESULT-ok.json" "$SHA" run-1
result "$R/design/v65/baselines/ev/RESULT-other.json" "$(printf 'a%.0s' {1..40})" run-1

base() { # 이름 [키 값]… → 기준선 파일(기본 머리줄 · 값 __DROP__ = 그 줄 빼기)
  local f="$R/design/v65/baselines/$1.md"; shift
  local -A v=([set_sha]="$SHA" [control]="lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=PRESS_SIDE_LANG_CLICK:1 flags=$OKFLAGS"
    [side_lang]="right=ko left=en" [server_ready]="2026-10-07T03:00:00Z" [visible_at_settle]="yes"
    [evidence]="design/v65/baselines/ev/RESULT-ok.json" [run_id]="run-1")
  while [ $# -gt 0 ]; do v[$1]="$2"; shift 2; done
  : > "$f"
  for k in set_sha control side_lang server_ready visible_at_settle evidence run_id; do
    [ "${v[$k]}" = "__DROP__" ] || echo "$k: ${v[$k]}" >> "$f"
  done
  printf '\n| 칸 | 값 |\n|---|---|\n| 빈 칸 | 0 |\n' >> "$f"
}
card() { # 이름 머리줄… → 카드 경로
  local f="$R/cards/$1.md"; shift
  { echo "# 카드 $1"; printf '%s\n' "$@"; } > "$f"; echo "$f"; }

gate() { # FT_PRESS_CARD(빈 값 = 미지정) [env…] → 최종 exit · 출력은 $OUT
  local c="$1"; shift
  OUT="$(env -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_CARD FT_PRESS_WT="$R" FT_PRESS_ROOT="$T/root" \
    ${c:+FT_PRESS_CARD="$c"} "$@" bash "$GATE" 2>&1)"; }
expect() { # 기대exit 출력패턴(막힌 칸·통과 줄) 설명 카드 [env…]
  local want="$1" pat="$2" desc="$3"; shift 3; n=$((n+1))
  gate "$@"; local got=$?
  if [ "$got" -eq "$want" ] && printf '%s' "$OUT" | grep -q -- "$pat" && ! printf '%s' "$OUT" | grep -q '발화해도 된다'; then ok "$n. $desc (exit $got)"
  else bad "$n. $desc (exit $got want $want)"; printf '%s\n' "$OUT" | sed 's/^/    /'; fi
}
ST="FT_PRESS_GATE_SELFTEST=1"
P="design/v65/baselines"

base ok
base nohdr visible_at_settle __DROP__
base badsha set_sha "$(printf 'b%.0s' {1..40})"
base unknown visible_at_settle unknown
base flagsoff control "lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=PRESS_SIDE_LANG_CLICK:1 flags=V65_TOGGLE_A=0,V65_TOGGLE_B=off"
base noev evidence "$P/ev/RESULT-missing.json"
base evother evidence "$P/ev/RESULT-other.json"
echo '[]' > "$R/$P/ev/RESULT-array.json"; base evarr evidence "$P/ev/RESULT-array.json"
# 검사기 비정상 종료 재현: BLOCK 줄 없이 비0 으로 죽는 python3 를 PATH 앞에 둔다(DA⑥ r1 — 줄 부재를 통과로 읽으면 안 된다)
mkdir -p "$T/fakebin" && printf '#!/bin/sh\nexit 9\n' > "$T/fakebin/python3" && chmod +x "$T/fakebin/python3"

expect 1 '⑥ 카드 미지정' "카드 미지정 → 막힘" "" "$ST"
expect 1 'BLOCK 카드 기준선: 없음' "카드 기준선: 없음 → 막힘" "$(card none '기준선: 없음' '실험: 없음')" "$ST"
expect 1 'BLOCK 기준선 파일: 없음' "기준선 파일 없음 → 막힘" "$(card nofile "기준선: $P/BASELINE-nope.md" '실험: 없음')" "$ST"
expect 1 'BLOCK 기준선 머리줄 빠짐: visible_at_settle' "머리줄 빠짐(visible_at_settle) → 막힘" "$(card c-nohdr "기준선: $P/nohdr.md" '실험: 없음')" "$ST"
expect 1 'BLOCK set_sha:' "set_sha 불량(이 저장소에 없음) → 막힘" "$(card c-badsha "기준선: $P/badsha.md" '실험: 없음')" "$ST"
expect 1 'BLOCK visible_at_settle: unknown' "visible_at_settle: unknown → 막힘" "$(card c-unknown "기준선: $P/unknown.md" '실험: 없음')" "$ST"
expect 1 'BLOCK side_lang:' "side_lang 불일치(카드 비교 언어 right=en) → 막힘" "$(card c-lang "기준선: $P/ok.md" '실험: 없음' '비교 언어: right=en,left=ko')" "$ST"
expect 1 'BLOCK self: 종류' "보통 카드(종류: 측정 · 회차: 12) self → 막힘" "$(card self-normal '기준선: self' '종류: 측정' '회차: 12' '실험: 없음' '프로필: default-3bubble')" "$ST"
expect 1 'BLOCK self: 프로필' "프로필 ≠ default-3bubble self → 막힘" "$(card self-prof '기준선: self' '종류: 기준선' '회차: 1' '실험: 없음' '프로필: long-3m')" "$ST"
expect 1 'BLOCK control flags: V65_TOGGLE_A=0' "flags 비기본(V65_TOGGLE_A=0) → 막힘" "$(card c-flags "기준선: $P/flagsoff.md" '실험: 없음')" "$ST"
expect 1 'BLOCK evidence: 증거 없음' "evidence 부재(머리줄 정상) → 막힘" "$(card c-noev "기준선: $P/noev.md" '실험: 없음')" "$ST"
expect 1 'BLOCK evidence: 증거 불일치 — RESULT set_sha' "evidence set_sha 불일치 → 막힘" "$(card c-evother "기준선: $P/evother.md" '실험: 없음')" "$ST"
OKCARD="$(card c-ok "기준선: $P/ok.md" '실험: V65_TOGGLE_B=on')"
expect 3 'diff 0 = 커밋 소스 동일' "정상 경로(실험 key ⊂ FLAGS.md · 측정 실패 회차도 유효) → SELFTEST 성공 3" "$OKCARD" "$ST"
SELFCARD="$(card self-ok '기준선: self' '종류: 기준선' '회차: 1' '실험: 없음' '프로필: default-3bubble')"
expect 3 '기준선 self — 이 회차가 기준선이다' "제한된 self(종류 기준선·회차 1·실험 없음·default-3bubble) → SELFTEST 성공 3" "$SELFCARD" "$ST"
expect 1 '시험 모드 상속 — 발사 금지' "보통 모드에 SELFTEST 상속(FT_PRESS_GATE_SELFTEST=0) → 막힘" "$OKCARD" FT_PRESS_GATE_SELFTEST=0
expect 1 'BLOCK evidence: 증거 없음 — 형식' "evidence JSON 배열 [] → 막힘" "$(card c-evarr "기준선: $P/evarr.md" '실험: 없음')" "$ST"
expect 1 'BLOCK 검사기: python 비정상 종료(rc=9)' "검사기 비정상 종료(BLOCK 줄 0 · rc 9) → 막힘" "$OKCARD" "$ST" PATH="$T/fakebin:$PATH"
echo 'x = 2' > "$R/worker/a.py"; git -C "$R" commit -qam change
expect 1 'BLOCK 세트 변경' "세트 경로 변경 뒤 → 막힘" "$OKCARD" "$ST"
n=$((n+1)); gate "$SELFCARD" "$ST"; got=$?
[ "$got" -eq 3 ] && printf '%s' "$OUT" | grep -q '^PRESS-GATE SELFTEST PASS$' && ! printf '%s' "$OUT" | grep -q '발화해도 된다' \
  && ok "$n. SELFTEST 성공 출력에 «발화해도 된다» 0건 · 마지막 판정 = SELFTEST PASS" || bad "$n. SELFTEST 출력 (exit $got)"

echo "cases=$n fail=$fail"; [ $fail -eq 0 ] && echo "ALL PASS"
[ $fail -eq 0 ]
