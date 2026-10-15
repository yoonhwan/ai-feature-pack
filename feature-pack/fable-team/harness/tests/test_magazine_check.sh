#!/bin/bash
# test_magazine_check.sh — R184: 08:15 매거진 미발행 경보(ft-magazine-check.sh) · 꺼진 예약 점검(ft-launchd-check.sh)
# ⓒ 로그에 오늘 줄 없음 → [긴급] 1통 · 있음 → 0 · 같은 날 두 번 → 1통 · 08:15 전 → 0
# ⓓ disabled + 내림 기록 없음 → [급] 1통 · 기록 있음 → 0 + «내림 중» 1줄
# ⓔ 변이: ft-magazine-check.sh 에서 «오늘 날짜 줄 검사» 를 뺀 복사본 → ⓒ(있음 → 0통) FAIL 이어야 한다
# 실 launchctl·슬랙·mbox·HOME 0 — 전부 가짜. 시험 입력은 GIT_* 없이.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

mkdir -p "$T/bin" "$T/state"
# 가짜 mbox — 호출 기록만
printf '#!/usr/bin/env bash\necho "$*" >> "%s/mbox.calls"\n' "$T" > "$T/mbox.sh"
# 가짜 launchctl — print = 있음 · print-disabled = $T/disabled.txt 내용
printf '#!/usr/bin/env bash\ncase "$1" in print-disabled) cat "%s/disabled.txt";; esac\nexit 0\n' "$T" > "$T/bin/launchctl"
chmod +x "$T/mbox.sh" "$T/bin/launchctl"
: > "$T/disabled.txt"
calls() { [ -f "$T/mbox.calls" ] && wc -l < "$T/mbox.calls" | tr -d ' ' || echo 0; }
reset() { rm -f "$T/mbox.calls"; rm -rf "$T/state/mc" "$T/state/lc"; }

mag() {  # $1 = 시각 · $2 = 스크립트(기본 정본)
  FT_MAG_LOG="$T/mag.out" FT_MAG_NOW="$1" FT_MAG_MBOX="$T/mbox.sh" FT_MAG_STATE="$T/state/mc" FT_MAG_NOTIFY="planner#t" \
    FT_MAG_LAUNCHCTL="$T/bin/launchctl" bash "${2:-$BIN/ft-magazine-check.sh}" 2>&1
}
printf 'published date=2026-10-14 ts=1 md=x\nemit-model date=2026-10-15 file=y\n' > "$T/mag.out"

bash -n "$BIN/ft-magazine-check.sh" && bash -n "$BIN/ft-launchd-check.sh" && ok "bash -n 2종" || bad "bash -n"

# ⓒ 오늘 줄 없음 → 1통
reset; OUT="$(mag '2026-10-15 08:15')"; rc=$?
[ $rc -eq 0 ] && [ "$(calls)" = 1 ] && grep -q '^send planner#t ft-magazine-check \[긴급\] 아침 매거진 미발행 2026-10-15 — 예약 상태 enabled · 마지막 게시 2026-10-14' "$T/mbox.calls" && ok "ⓒ 오늘 줄 없음 → [긴급] 1통(상태·마지막 게시 포함)" || bad "ⓒ 없음 rc=$rc calls=$(calls): $OUT"
# 같은 날 두 번째 실행 → 추가 0통
mag '2026-10-15 08:16' >/dev/null; [ "$(calls)" = 1 ] && ok "ⓒ 같은 날 두 번 → 1통 유지" || bad "ⓒ 같은 날 중복 calls=$(calls)"
# 08:15 전 → 0통
reset; mag '2026-10-15 08:14' >/dev/null; [ "$(calls)" = 0 ] && ok "ⓒ 08:15 전 → 0통" || bad "ⓒ 이른 시각 calls=$(calls)"
# 오늘 줄 있음 → 0통
printf 'published date=2026-10-15 ts=2 md=x\n' >> "$T/mag.out"
reset; mag '2026-10-15 08:20' >/dev/null; [ "$(calls)" = 0 ] && ok "ⓒ 오늘 published 줄 있음 → 0통" || bad "ⓒ 있음인데 calls=$(calls)"
# 예약 disabled 이면 상태 칸에 disabled
printf 'disabled services = {\n\t"com.byz.ft-magazine" => disabled\n}\n' > "$T/disabled.txt"
reset; mag '2026-10-16 08:15' >/dev/null; grep -q '예약 상태 disabled' "$T/mbox.calls" && ok "ⓒ 예약 상태 칸 = disabled" || bad "ⓒ 상태 칸"
: > "$T/disabled.txt"

# ⓔ 변이 — 오늘 날짜 줄 검사를 뺀다 → «있음 → 0통» 이 깨져야 한다(시험이 날짜 비교를 실제로 잡는다)
grep -v 'published date=\$TODAY' "$BIN/ft-magazine-check.sh" > "$T/mut.sh"
reset; mag '2026-10-15 08:20' "$T/mut.sh" >/dev/null
[ "$(calls)" = 1 ] && ok "ⓔ 변이(날짜 비교 제거) → ⓒ «있음 → 0통» FAIL 을 시험이 잡음" || bad "ⓔ 변이가 안 잡힘 calls=$(calls)"

# ⓓ 꺼짐 점검
printf 'com.byz.ft-magazine\n# 주석\ncom.byz.ft-board-publish\n' > "$T/expected.txt"
printf 'disabled services = {\n\t"com.byz.ft-magazine" => disabled\n\t"com.byz.ft-board-publish" => enabled\n}\n' > "$T/disabled.txt"
mkdir -p "$T/rec"
ldc() {
  FT_LDC_EXPECTED="$T/expected.txt" FT_LDC_RECORDS="$T/rec" FT_LDC_STATE="$T/state/lc" FT_LDC_NOW=2026-10-15 FT_LDC_MBOX="$T/mbox.sh" \
    FT_LDC_NOTIFY="hmaster#t" FT_LDC_LAUNCHCTL="$T/bin/launchctl" bash "$BIN/ft-launchd-check.sh" 2>&1
}
reset; OUT="$(ldc)"
[ "$(calls)" = 1 ] && grep -q '^send hmaster#t ft-launchd-check \[급\] 예약 com.byz.ft-magazine' "$T/mbox.calls" && echo "$OUT" | grep -q '내림 기록 없음' && ok "ⓓ disabled + 기록 없음 → [급] 1통" || bad "ⓓ 기록 없음 calls=$(calls): $OUT"
ldc >/dev/null; [ "$(calls)" = 1 ] && ok "ⓓ 같은 날 두 번 → 1통 유지" || bad "ⓓ 하루 1회 calls=$(calls)"
printf '사유: 판정 1425 로 내림\n판정: 오빠 1424·1425\n' > "$T/rec/com.byz.ft-magazine.md"
reset; OUT="$(ldc)"; [ "$(calls)" = 1 ] && echo "$OUT" | grep -q '불완전' && ok "ⓓ 기록 불완전(조건 줄 없음) → [급] 1통" || bad "ⓓ 불완전 calls=$(calls): $OUT"
printf '사유: 판정 1425 로 내림\n판정: 오빠 1424·1425\n다시 올릴 조건: 새 발행 길 설치 뒤\n누가: harness master\n' > "$T/rec/com.byz.ft-magazine.md"
reset; OUT="$(ldc)"; [ "$(calls)" = 0 ] && [ "$(echo "$OUT" | grep -c '내림 중(판정 1425 로 내림)')" = 1 ] && ok "ⓓ 기록 있음 → 0통 + «내림 중(사유)» 1줄" || bad "ⓓ 기록 있음 calls=$(calls): $OUT"
: > "$T/disabled.txt"; reset; OUT="$(ldc)"; [ "$(calls)" = 0 ] && [ -z "$OUT" ] && ok "ⓓ 전부 enabled → 출력 0 · 0통" || bad "ⓓ enabled calls=$(calls): $OUT"

# ── ⓕ (DA⑥ r1 HOLD 반송 r3) ──
# ⓕ1 로그 파일 없음 → 같은 [긴급] 1통(본문 «로그 없음») · 같은 날 두 번 → 1통 · rc 0
mag_nolog() { FT_MAG_LOG="$T/absent.out" FT_MAG_NOW="$1" FT_MAG_MBOX="$T/mbox.sh" FT_MAG_STATE="$T/state/mc" FT_MAG_NOTIFY="planner#t" \
  FT_MAG_LAUNCHCTL="$T/bin/launchctl" bash "$BIN/ft-magazine-check.sh" 2>&1; }
reset; OUT="$(mag_nolog '2026-10-15 08:15')"; rc=$?
[ $rc -eq 0 ] && [ "$(calls)" = 1 ] && grep -q '^send planner#t ft-magazine-check \[긴급\] 아침 매거진 미발행 2026-10-15.*로그 없음' "$T/mbox.calls" && ok "ⓕ1 로그 없음 → [긴급] 1통(본문 «로그 없음») · rc 0" || bad "ⓕ1 rc=$rc calls=$(calls): $OUT"
mag_nolog '2026-10-15 08:16' >/dev/null; [ "$(calls)" = 1 ] && ok "ⓕ1 로그 없음 같은 날 두 번 → 1통 유지" || bad "ⓕ1 중복 calls=$(calls)"
reset; mag_nolog '2026-10-15 08:14' >/dev/null; [ "$(calls)" = 0 ] && ok "ⓕ1 로그 없음 + 08:15 전 → 0통" || bad "ⓕ1 이른 시각 calls=$(calls)"

# ⓕ2 내림 기록 네 줄(사유·판정·다시 올릴 조건·누가) 중 하나라도 비면 → [급] 1통 · «내림 중» 0
printf 'disabled services = {\n\t"com.byz.ft-magazine" => disabled\n}\n' > "$T/disabled.txt"
printf 'com.byz.ft-magazine\n' > "$T/expected.txt"
ldcs() { FT_LDC_EXPECTED="$T/expected.txt" FT_LDC_RECORDS="$T/rec" FT_LDC_STATE="$T/state/lc" FT_LDC_NOW=2026-10-15 FT_LDC_MBOX="$T/mbox.sh" \
  FT_LDC_NOTIFY="hmaster#t" FT_LDC_LAUNCHCTL="$T/bin/launchctl" bash "${1:-$BIN/ft-launchd-check.sh}" 2>&1; }
rec4() { printf '사유: %s\n판정: %s\n다시 올릴 조건: %s\n누가: %s\n' "$1" "$2" "$3" "$4" > "$T/rec/com.byz.ft-magazine.md"; }
case2() {  # $1 = 이름 · $2 = 빠진 항목 표기 · 나머지 = rec4 인자 · $SCRIPT 로 대상 스크립트
  local name="$1" miss="$2"; shift 2; rec4 "$@"; reset; OUT="$(ldcs "${SCRIPT:-}")"
  [ "$(calls)" = 1 ] && echo "$OUT" | grep -q "내림 기록 불완전($miss)" && ! echo "$OUT" | grep -q '내림 중' && ok "ⓕ2 $name → [급] 1통 · «내림 중» 0" || bad "ⓕ2 $name calls=$(calls): $OUT"
}
case2 "빈 판정" 판정 "사유A" "" "조건A" "누가A"
case2 "빈 다시 올릴 조건" "다시 올릴 조건" "사유A" "판정A" "" "누가A"
case2 "빈 사유" 사유 "" "판정A" "조건A" "누가A"
printf '사유: 사유A\n판정: 판정A\n다시 올릴 조건: 조건A\n' > "$T/rec/com.byz.ft-magazine.md"; reset; OUT="$(ldcs)"
[ "$(calls)" = 1 ] && echo "$OUT" | grep -q '내림 기록 불완전(누가)' && ok "ⓕ2 누가 줄 없음 → [급] 1통" || bad "ⓕ2 누가 없음 calls=$(calls): $OUT"
rec4 사유A 판정A 조건A 누가A; reset; OUT="$(ldcs)"
[ "$(calls)" = 0 ] && echo "$OUT" | grep -q '내림 중(사유A)' && ok "ⓕ2 네 줄 모두 값 → 0통 + «내림 중(사유A)»" || bad "ⓕ2 정상 기록 calls=$(calls): $OUT"

# ⓕ3 변이 — 비공백 검사를 뺀 복사본 → ⓕ2(빈 판정 → [급] 1통) FAIL 이어야 한다
sed 's/|| missing+=.*$/|| :/' "$BIN/ft-launchd-check.sh" > "$T/mut-ldc.sh"
rec4 사유A "" 조건A 누가A; reset; OUT="$(ldcs "$T/mut-ldc.sh")"
[ "$(calls)" = 0 ] && ok "ⓕ3 변이(비공백 검사 제거) → ⓕ2 «빈 판정 → [급] 1통» FAIL 을 시험이 잡음" || bad "ⓕ3 변이가 안 잡힘 calls=$(calls)"

# ⓕ 틱 격리 — ft-tick 을 실제로 도는 쪽은 끄기 스위치(FT_TICK_LAUNCHD=0 · FT_TICK_MAGAZINE=0)로 새 감시가 안 불린다 · 기본은 불린다
mkdir -p "$T/tk/bin" "$T/tk/repo"
cp "$BIN/ft-tick.sh" "$T/tk/bin/ft-tick.sh"
printf '#!/bin/bash\necho M >> "%s/tk/called"\n' "$T" > "$T/tk/bin/ft-magazine-check.sh"
printf '#!/bin/bash\necho L >> "%s/tk/called"\n' "$T" > "$T/tk/bin/ft-launchd-check.sh"
printf '{"_master":"m#1","_hil_route":"p#1"}\n' > "$T/tk/seats.json"
tick() {  # KEY=VAL ... → 불린 횟수
  : > "$T/tk/called"
  ( cd "$T/tk/repo" && env "$@" FT_TICK_SEATS="$T/tk/seats.json" FT_TICK_STATE_DIR="$T/tk/state" FT_TICK_PIDFILE="$T/tk/pid" FT_TICK_STAMP_PREFIX="$T/tk/p-" \
      FT_TICK_MBOX="$T/mbox.sh" FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_API_OUTAGE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 \
      FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_LONG=0 FT_TICK_STALL_INTERVAL=99999999999 FT_TICK_GOAL_INTERVAL=99999999999 \
      timeout 60 bash "$T/tk/bin/ft-tick.sh" --once >/dev/null 2>&1 ); sort "$T/tk/called" | tr -d '\n'
}
[ "$(tick FT_TICK_X=1)" = "LM" ] && ok "ⓕ 틱 기본 = 두 점검 모두 부름" || bad "ⓕ 틱 기본: $(tick FT_TICK_X=1)"
[ -z "$(tick FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0)" ] && ok "ⓕ FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 → 0회" || bad "ⓕ 끄기 스위치 무시됨: $(tick FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0)"
[ "$(tick FT_TICK_MAGAZINE=0)" = "L" ] && ok "ⓕ FT_TICK_MAGAZINE=0 → 매거진 경보만 끔" || bad "ⓕ MAGAZINE=0: $(tick FT_TICK_MAGAZINE=0)"
# 실제로 ft-tick 을 도는 시험들은 두 스위치를 명시 설정한다
for t in test_dead_seat_resume test_live_bin_drift_check test_raised_seat test_ft_tick_master_seat test_seat_retire test_tick_team_msg; do
  grep -q 'FT_TICK_LAUNCHD=0' "$HERE/$t.sh" && grep -q 'FT_TICK_MAGAZINE=0' "$HERE/$t.sh" && ok "ⓕ $t 가 끄기 스위치를 명시 설정" || bad "ⓕ $t 에 끄기 스위치 없음"
done

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
