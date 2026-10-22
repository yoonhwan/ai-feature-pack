#!/usr/bin/env bash
# test_press_gate_load_gate_r769.sh — r769b: press 게이트 «부하 게이트»(5분 평균 load ≥ 임계면 시작 REJECT + 원인 상위 3).
#   왜: 부하 81~102 에서 돈 lecture p3-r6 이 청크 POST 1500ms 초과 15 · Redis Timeout 14 로 무효.
#   가짜 sysctl·ps·lsof·curl·tmux 만 · 실제 부하·리스너·오디오 0 · 리포 파일 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${R769B_SUT:-$HERE/../../harness/bin/ft-press-gate.sh}"
fail=0; n=0
ok(){ echo "PASS $1"; }
bad(){ echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
cmp -s "$GATE" "$HERE/../kit/fable-team/bin/ft-press-gate.sh" && ok "kit 짝 cmp0" || bad "kit 짝 cmp0"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FB="$T/fb"; mkdir -p "$FB"
cat > "$FB/sysctl" <<'S'
#!/bin/sh
echo "sysctl $*" >> "${STUB_LOG:-/dev/null}"
printf '{ %s }\n' "${FAKE_LOADAVG:-0.10 0.20 0.30}"
S
cat > "$FB/ps" <<'P'
#!/bin/sh
echo "ps $*" >> "${STUB_LOG:-/dev/null}"
printf ' %%CPU   PID COMM\n 74.2 111 probe\n 61.9 222 XprotectService\n 57.8 333 claude\n'
P
cat > "$FB/lsof" <<'L'
#!/bin/sh
exit 1
L
cat > "$FB/curl" <<'C'
#!/bin/sh
printf '000'; exit 7
C
cat > "$FB/tmux" <<'X'
#!/bin/sh
case "$1" in list-sessions) exit 0 ;; display-message) echo 'byz-v65-tester-claude#0' ;; esac
X
chmod +x "$FB"/*
grep -q FAKE_LOADAVG "$FB/sysctl" && ok "가짜 sysctl·ps 설치" || bad "스텁 생성"

mkworld(){ # $1 이름
  W="$T/w-$1"; rm -rf "$W"
  R="$W/repo"; mkdir -p "$R/worker" "$R/shared" "$R/gateway" "$R/clients/web" "$W/root/.fable-team/state" "$W/fb"
  cp "$FB"/* "$W/fb"/
  echo '{}' > "$W/root/.fable-team/seats.json"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$W/root/.fable-team/state/all-stop.log"
  git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  echo 'x = 1' > "$R/worker/a.py"; git -C "$R" add -A >/dev/null; git -C "$R" commit -qm base
  printf 'activation bundle established\nWorker Starting - Warming up services\nselfhost prewarm SUMMARY: 5 ok / 0 FAILED\n' > "$W/worker.log"
}
gate(){ # $1 태그 [env…] → OUT · RC
  local tag="$1"; shift
  OUT="$(env -u FT_PRESS_LOAD_MAX -u FT_PRESS_TARGET -u FT_PORT_BASE -u FT_PRESS_PORTS -u FT_PRESS_SEAT -u TMUX_PANE \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$W/root" FT_PRESS_EVID="$W/ev" FT_PRESS_PERMIT_DIR="$W/permits" \
    TMUX_PANE=%1 STUB_LOG="$W/stub-$tag.log" PATH="$W/fb:$PATH" "$@" bash "$GATE" 2>&1)"; RC=$?
}
has(){ printf '%s' "$OUT" | grep -q -- "$1"; }

# ⓐ 부하 높음(5분 81.5 ≥ 60) → REJECT + 원인 상위 3
mkworld a
gate a FAKE_LOADAVG='1.00 81.50 20.00'
n=$((n+1)); [ "$RC" = 1 ] && has '5분 평균 부하 81.50 ≥ 임계 60' && has '원인 상위 3' \
  && has '111 probe' && has '222 XprotectService' && has '333 claude' && ! has '✓ 부하 5분 평균' \
  && ok "$n. ⓐ 부하 81.5 ≥ 60 → REJECT · 상위 3 프로세스 출력 (exit $RC)" \
  || { bad "$n. ⓐ 부하 높음 (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
n=$((n+1)); [ "$(printf '%s\n' "$OUT" | grep -c '^      .*[0-9]')" -ge 3 ] && ok "$n. ⓐ 상위 3 줄이 게이트 출력에 실제로 찍힘(들여쓴 3줄)" \
  || { bad "$n. ⓐ 상위 3 줄 수"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ⓑ 부하 낮음(5분 0.20 < 60) → 막지 않는다(다른 칸까지 진행)
mkworld b
gate b FAKE_LOADAVG='0.10 0.20 0.30'
n=$((n+1)); has '✓ 부하 5분 평균 0.20 < 임계 60' && ! has '✗ 5분 평균 부하' && has '미랜딩 제품 커밋' \
  && ok "$n. ⓑ 부하 0.20 < 60 → 부하 칸 통과(다른 검사는 그대로 진행)" \
  || { bad "$n. ⓑ 부하 낮음 (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ⓒ 임계 env 덮어쓰기 — 30 이면 30.5 는 막고 29.9 는 통과
mkworld c
gate c FAKE_LOADAVG='10.0 30.50 10.0' FT_PRESS_LOAD_MAX=30
n=$((n+1)); [ "$RC" = 1 ] && has '5분 평균 부하 30.50 ≥ 임계 30' && ok "$n. ⓒ FT_PRESS_LOAD_MAX=30 에서 30.5 → REJECT(exit $RC)" \
  || { bad "$n. ⓒ 임계 덮어쓰기 (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
gate c FAKE_LOADAVG='10.0 29.90 10.0' FT_PRESS_LOAD_MAX=30
n=$((n+1)); has '✓ 부하 5분 평균 29.90 < 임계 30' && ok "$n. ⓒ 임계 30 아래(29.9) → 통과 줄" \
  || { bad "$n. ⓒ 임계 아래"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ⓓ 잘못된 임계 = 막힘 · 못 읽음 = 경고만(부하 게이트 건너뜀)
mkworld d
gate d FAKE_LOADAVG='1.0 2.0 3.0' FT_PRESS_LOAD_MAX=abc
n=$((n+1)); [ "$RC" = 1 ] && has 'FT_PRESS_LOAD_MAX=abc — 숫자' && ok "$n. ⓓ 임계=abc → 막힘(exit $RC)" \
  || { bad "$n. ⓓ 잘못된 임계 (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
echo
[ "$fail" = 0 ] && { echo "ALL PASS ($n)"; exit 0; }
echo "FAILED $fail / $n"; exit 1
