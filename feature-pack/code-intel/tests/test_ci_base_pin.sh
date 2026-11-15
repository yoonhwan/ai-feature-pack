#!/usr/bin/env bash
# r18xx — ci 시험 «기준판 대조» 블록의 기준판 고정 시험 (카드 ci-test-base-sha-pin · 설계 = 카드 §계약 B1~B6 · §반례 표 · §변이)
#   기준판 = tests/fixtures/ci-base-97528b12 한 파일 · 내용 = 97528b12:feature-pack/code-intel/skill/scripts/ci
#            (blob cff07f3add33f4fee436223d87daef95459a74ff · 454줄 · sha256 f2eb9e1fba04a8773340b9b263e38ec9fb3194387bebe13b90c5e96931a17dbf)
#   반례 D2(.git 없는 사본) · D4(fixture 없음) · D5(fixture 1바이트 변조) · D6(fixture 를 지금 판으로 바꾼 변이)
#   변이 Y1(fixture 대신 origin/main 에서 꺼냄) · Y2(sha256 확인 빼기) · Y3(fixture 없으면 건너뛰기)
#   시험은 임시 사본에서 1회씩 · 병렬 4개까지 · 실 probe 0 · sleep 0 · 네트워크 0
#   실행: bash feature-pack/code-intel/tests/test_ci_base_pin.sh
[ -n "${CI_BASE_PIN_TEST_GUARD:-}" ] && exit 0        # 재진입 표지(자기 호출 가드)
if [ -z "${CI_BASE_PIN_TEST_TIMED:-}" ]; then
  export CI_BASE_PIN_TEST_TIMED=1
  command -v timeout >/dev/null 2>&1 && exec timeout 70 bash "$0" "$@"   # 시험 1개 상한 70초(하드 룰 22)
fi
export CI_BASE_PIN_TEST_GUARD=1
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUB="$HERE/test_ci_search_nonascii_panic.sh"
FIX="$HERE/fixtures/ci-base-97528b12"
CI="$HERE/../skill/scripts/ci"
FIX_SHA256="f2eb9e1fba04a8773340b9b263e38ec9fb3194387bebe13b90c5e96931a17dbf"
for f in "$SUB" "$FIX" "$CI"; do
  [ -f "$f" ] || { echo "판정 불가: 파일 없음 — $f"; exit 2; }
done

# 사용자 프로세스 상한(지금 + 여유) — 시험이 fork 폭주로 다른 좌석을 막지 않게(r1041)
_nproc="$(ps -U "$(id -u)" -o pid= 2>/dev/null | wc -l | tr -d ' ')"
[ -n "$_nproc" ] && ulimit -u "$((_nproc + 300))" 2>/dev/null

n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | grep -m1 . | cut -c1-120)";; esac; }
cnt() { printf '%s\n' "$1" | grep -c -- "$2" 2>/dev/null || true; }
sha_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-base-pin.XXXXXX")" || { echo "판정 불가: 임시 폴더 생성 실패"; exit 2; }
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$SB"' EXIT   # 남은 자식 시험 프로세스 정리(r1234)

mkcase() { # mkcase <이름> — 시험 파일·fixture·ci 사본을 만들고 사본 폴더(feature-pack/code-intel)를 출력
  local d="$SB/$1/feature-pack/code-intel"
  mkdir -p "$d/tests/fixtures" "$d/skill/scripts" || return 1
  cp "$SUB" "$d/tests/test_ci_search_nonascii_panic.sh" &&
    cp "$FIX" "$d/tests/fixtures/ci-base-97528b12" &&
    cp "$CI"  "$d/skill/scripts/ci" || return 1
  printf '%s' "$d"
}
mutate() { # mutate <파일> <옛 글> <새 글> — 그 글이 정확히 1번 있어야 바꾼다
  python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit("변이 자리 못 찾음(%d회): %r" % (s.count(old), old))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
run_bg() { # run_bg <이름> <사본 폴더> — 시험 1회를 백그라운드로 · 로그 = $SB/<이름>.log · rc = $SB/<이름>.rc
  ( bash "$2/tests/test_ci_search_nonascii_panic.sh" > "$SB/$1.log" 2>&1; echo $? > "$SB/$1.rc" ) &
}
rc_of() { tr -d '[:space:]' < "$SB/$1.rc" 2>/dev/null || true; }
logof() { cat "$SB/$1.log" 2>/dev/null; }

# ── fixture 자체 ──────────────────────────────────────────────────────────
echo "== B1 기준판 fixture — 1파일 · sha256 고정 · 실행 비트 0 =="
chk "B1 fixture sha256" "$(sha_of "$FIX")" "$FIX_SHA256"
chk "B1 fixture 454줄" "$(wc -l < "$FIX" | tr -d ' ')" "454"
chk "B1 fixture 실행 비트 0" "$([ -x "$FIX" ] && echo x || echo -)" "-"
chk "B1 시험 파일 실행 비트 0" "$([ -x "$SUB" ] && echo x || echo -)" "-"

# ── 사본 만들기(D2·D4·D5·D6 · 변이 Y1~Y3) ─────────────────────────────────
echo "== 임시 사본 7개 — D2·D4·D5·D6 · Y1·Y2·Y3 =="
D2="$(mkcase d2)" || { echo "판정 불가: 사본 만들기 실패"; exit 2; }
D4="$(mkcase d4)"; rm -f "$D4/tests/fixtures/ci-base-97528b12"                      # D4 — fixture 없음
D5="$(mkcase d5)"; printf 'x' >> "$D5/tests/fixtures/ci-base-97528b12"              # D5 — 끝에 1바이트
D6="$(mkcase d6)"; cp "$CI" "$D6/tests/fixtures/ci-base-97528b12"                   # D6 — 지금 판 ci 로 교체
CUR_SHA="$(sha_of "$CI")"
mutate "$D6/tests/test_ci_search_nonascii_panic.sh" "$FIX_SHA256" "$CUR_SHA" \
  || { echo "판정 불가: D6 sha256 상수 치환 실패"; exit 2; }

Y1="$(mkcase y1)"                                                                   # Y1 — origin/main 에서 꺼냄
mutate "$Y1/tests/test_ci_search_nonascii_panic.sh" \
  'BASE="$HERE/fixtures/ci-base-97528b12"' \
  'BASE="$SB/ci-base-git"; git -C "$HERE/../../.." show "$(git -C "$HERE/../../.." rev-parse origin/main 2>/dev/null)" > "$BASE" 2>/dev/null || rm -f "$BASE"' \
  || { echo "판정 불가: Y1 변이 실패"; exit 2; }
Y2="$(mkcase y2)"; printf 'x' >> "$Y2/tests/fixtures/ci-base-97528b12"              # Y2 — sha256 확인 빼기(D5 입력)
mutate "$Y2/tests/test_ci_search_nonascii_panic.sh" \
  'elif [ "$BASE_GOT" != "$BASE_SHA256" ]; then' 'elif false; then' \
  || { echo "판정 불가: Y2 변이 실패"; exit 2; }
Y3="$(mkcase y3)"; rm -f "$Y3/tests/fixtures/ci-base-97528b12"                      # Y3 — 없으면 건너뛰기(D4 입력)
mutate "$Y3/tests/test_ci_search_nonascii_panic.sh" \
  '  bad "기준판 fixture 없음 — $BASE"' '  :' \
  || { echo "판정 불가: Y3 변이 실패"; exit 2; }

# ── 실행 — 4개 → 3개(동시 상한 4) ─────────────────────────────────────────
echo "== 시험 실행 — 사본마다 1회(각 11초 안팎 · 동시 4개) =="
for c in d2 d4 d5 d6; do
  case "$c" in d2) run_bg d2 "$D2";; d4) run_bg d4 "$D4";; d5) run_bg d5 "$D5";; d6) run_bg d6 "$D6";; esac
done
wait
for c in y1 y2 y3; do
  case "$c" in y1) run_bg y1 "$Y1";; y2) run_bg y2 "$Y2";; y3) run_bg y3 "$Y3";; esac
done
wait

# ── D2 .git 없는 사본 — D1 과 같아야 = 블록이 git·origin/main 을 안 읽는다 ──
echo "== D2 .git 없는 사본(git archive 꼴) =="
chk "D2 사본에 .git 없음" "$([ -e "$D2/.git" ] && echo 있음 || echo 없음)" "없음"
chk "D2 rc" "$(rc_of d2)" "0"
has "D2 실패 0" "$(logof d2)" "실패 0 =="
has "D2 마지막 PASS" "$(logof d2 | tail -n 1)" "PASS"
has "D2 기준판 표지" "$(logof d2)" "기준판 = fixtures/ci-base-97528b12"
chk "D2 기준판 bl 47줄" "$(cnt "$(logof d2)" 'ok   기준판')" "47"

# ── D4 fixture 없음 → FAIL 1줄 · 기능 검사 결과는 그대로 ────────────────────
echo "== D4 fixture 를 지운 사본 =="
chk "D4 rc" "$(rc_of d4)" "1"
chk "D4 FAIL 줄 = 1" "$(cnt "$(logof d4)" '^  FAIL')" "1"
has "D4 FAIL 문구" "$(logof d4)" "FAIL 기준판 fixture 없음"
chk "D4 기준판 bl 줄 0" "$(cnt "$(logof d4)" 'ok   기준판')" "0"

# ── D5 fixture 1바이트 변조 → sha256 FAIL 1줄 · bl 호출 0 ──────────────────
echo "== D5 fixture 끝에 1바이트 더한 사본 =="
chk "D5 rc" "$(rc_of d5)" "1"
chk "D5 FAIL 줄 = 1" "$(cnt "$(logof d5)" '^  FAIL')" "1"
has "D5 FAIL 문구" "$(logof d5)" "FAIL 기준판 fixture sha256 다름"
chk "D5 기준판 bl 줄 0" "$(cnt "$(logof d5)" 'ok   기준판')" "0"
chk "D5 기준판 표지 0" "$(cnt "$(logof d5)" '기준판 = ')" "0"

# ── D6 fixture 를 지금 판으로 바꾸고 상수도 맞춘 사본 → 블록이 살아 있다 ────
echo "== D6 fixture = 지금 판 ci · sha256 상수 맞춤(변이) =="
chk "D6 rc" "$(rc_of d6)" "1"
chk "D6 «통과 — FAIL 이어야» 16줄" "$(cnt "$(logof d6)" 'FAIL 기준판 .* 통과 — FAIL 이어야')" "16"
has "D6 기준판 표지" "$(logof d6)" "기준판 = fixtures/ci-base-97528b12"

# ── 변이 Y1~Y3 — 지정 반례가 잡아야 한다 ──────────────────────────────────
echo "== 변이 — 각각 지정 반례가 FAIL 해야(잡힘) =="
chk "Y1(origin/main 에서 꺼냄) → D2 가 잡음" "$(rc_of y1)" "1"
has "Y1 잡은 문구" "$(logof y1)" "FAIL 기준판 fixture 없음"
chk "Y2(sha256 확인 빼기) → D5 가 잡음" "$(rc_of y2)" "0"
chk "Y2 대조 = D5 rc 1" "$(rc_of d5)" "1"
chk "Y3(fixture 없으면 건너뛰기) → D4 가 잡음" "$(rc_of y3)" "0"
chk "Y3 대조 = D4 rc 1" "$(rc_of d4)" "1"

echo "== 요약: $n 검사 · 실패 $fail =="
[ "$fail" -eq 0 ] || exit 1
echo "PASS"
