#!/usr/bin/env bash
# test_press_gate_numeric_env_r769.sh — r769 r2 반송(DA⑥ r2 HOLD): 숫자 env 입력 엄격 검사(_int_port · _decimal).
#   왜: ① FT_PRESS_PORT_BASE=017620 이 앞 0 허용 → $((…+1)) 이 8진으로 8080(기본 포트) 조회 · rc0
#       ② FT_PRESS_LOAD_MAX=60..0 이 점 개수 무제한 통과 → awk 문자열 비교 → «✓ 100.00 < 60..0» PASS
#   스텁만(sysctl·lsof·curl·tmux) · 실 포트·리스너 접촉 0 · 리포 파일 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${R769N_SUT:-$HERE/../../harness/bin/ft-press-gate.sh}"
fail=0; n=0
ok(){ echo "PASS $1"; }
bad(){ echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
cmp -s "$GATE" "$HERE/../kit/fable-team/bin/ft-press-gate.sh" && ok "kit 짝 cmp0" || bad "kit 짝 cmp0"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FB="$T/fb"; mkdir -p "$FB"
cat > "$FB/sysctl" <<'S'
#!/bin/sh
printf '{ %s }\n' "${FAKE_LOADAVG:-0.10 0.20 0.30}"
S
cat > "$FB/lsof" <<'L'
#!/bin/sh
echo "lsof $*" >> "${STUB_LOG:-/dev/null}"
exit 1
L
cat > "$FB/curl" <<'C'
#!/bin/sh
echo "curl $*" >> "${STUB_LOG:-/dev/null}"
printf '000'; exit 7
C
cat > "$FB/tmux" <<'X'
#!/bin/sh
case "$1" in list-sessions) exit 0 ;; display-message) echo 'byz-v65-tester-claude#0' ;; esac
X
chmod +x "$FB"/*

siblings(){ mkdir -p "$1"; for f in "$HERE/../bin"/*; do [ "$(basename "$f")" = ft-press-gate.sh ] && continue; ln -sf "$f" "$1/$(basename "$f")"; done; }
mkworld(){ # $1 이름
  W="$T/w-$1"; rm -rf "$W"
  R="$W/repo"; mkdir -p "$R/worker" "$W/root/.fable-team/state" "$W/fb"
  cp "$FB"/* "$W/fb"/
  echo '{}' > "$W/root/.fable-team/seats.json"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$W/root/.fable-team/state/all-stop.log"
  git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  echo 'x = 1' > "$R/worker/a.py"; git -C "$R" add -A >/dev/null; git -C "$R" commit -qm base
  printf 'activation bundle established\nWorker Starting - Warming up services\nselfhost prewarm SUMMARY: 5 ok / 0 FAILED\n' > "$W/worker.log"
  SIB="$W/fb"
}
gate(){ # $1 판 · $2 태그 [env…] → OUT · RC
  local sut="$1" tag="$2"; shift 2
  OUT="$(env -u FT_PRESS_LOAD_MAX -u FT_PRESS_TARGET -u FT_PRESS_PORTS -u FT_PRESS_PORT_BASE -u FT_PORT_BASE \
    -u FT_PRESS_WORKER_LOG -u FT_PRESS_SSE_HEALTH_URL -u FT_PRESS_SEAT -u FT_PRESS_GATE_SELFTEST -u TMUX -u TMUX_PANE \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$W/root" FT_PRESS_EVID="$W/ev-$tag" FT_PRESS_PERMIT_DIR="$W/permits-$tag" \
    TMUX_PANE=%1 STUB_LOG="$W/stub-$tag.log" PATH="$W/fb:$PATH" "$@" bash "$sut" 2>&1)"; RC=$?
}
has(){ printf '%s' "$OUT" | grep -q -- "$1"; }

# ── ⓟ 017620(앞 0 = 8진 사고) → ✗ rc1 · 접촉 0
mkworld p
gate "$GATE" p FT_PRESS_PORT_BASE=017620 FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:38343/api/v1/health/"
n=$((n+1)); [ "$RC" = 1 ] && has 'FT_PRESS_PORT_BASE 가 숫자 1024~65535 가 아니다: 017620' \
  && [ ! -s "$W/stub-p.log" ] && ! has '포트 갈래: FT_PRESS_PORT_BASE' \
  && ok "$n. ⓟ FT_PRESS_PORT_BASE=017620 → rc=1 · 접촉 0(8진 해석 차단)" \
  || { bad "$n. ⓟ 017620 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
# 고침 1·2 를 되돌린 변이에서는 ⓟ 가 통과해 버린다(빨강 확인)
siblings "$T/mutint"
python3 - "$GATE" "$T/mutint/ft-press-gate.sh" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src, encoding='utf-8').read()
a = '''_int_port(){
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  case "$1" in 0*) return 1 ;; esac
  [ "${#1}" -ge 4 ] && [ "${#1}" -le 5 ] || return 1
  [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]
}'''
b = '''_int_port(){ case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]; }'''
assert a in s
open(dst, 'w', encoding='utf-8').write(s.replace(a, b, 1))
PY
chmod +x "$T/mutint/ft-press-gate.sh" && ok "변이(앞 0 검사 삭제) 준비" || bad "변이 준비"
gate "$T/mutint/ft-press-gate.sh" pm FT_PRESS_PORT_BASE=017620 FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:38343/api/v1/health/"
n=$((n+1)); ! has '가 숫자 1024~65535 가 아니다: 017620' && has '포트 갈래: FT_PRESS_PORT_BASE=017620' \
  && ok "$n. ⓟ 변이(앞 0 검사 삭제) → «017620 통과» 모습 재현 ⇒ ⓟ 의 ✗ 단언이 이 변이를 죽인다" \
  || { bad "$n. ⓟ 변이 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ── ⓠ FT_PRESS_PORTS 칸에 08080
mkworld q
gate "$GATE" q FT_PRESS_PORTS="08080,8081,3001" FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:3001/api/v1/health/"
n=$((n+1)); [ "$RC" = 1 ] && has 'FT_PRESS_PORTS 포트가 숫자 1024~65535 가 아니다: 08080' && [ ! -s "$W/stub-q.log" ] \
  && ok "$n. ⓠ FT_PRESS_PORTS=08080,… → rc=1 · 접촉 0" \
  || { bad "$n. ⓠ 08080 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ── ⓡ LOAD_MAX 꼴 5종 — 60..0 · 1e2 · 60. · .5 · -1 (부하 100 을 줘도 통과 못 한다)
for v in '60..0' '1e2' '60.' '.5' '-1'; do
  mkworld "r$(printf '%s' "$v" | tr -cd '0-9a-z')"
  tag="r$(printf '%s' "$v" | tr -cd '0-9a-z')"
  gate "$GATE" "$tag" FAKE_LOADAVG='1.0 100.0 1.0' FT_PRESS_LOAD_MAX="$v"
  n=$((n+1)); [ "$RC" = 1 ] && has "FT_PRESS_LOAD_MAX=$v — 숫자(부하 임계)만" && ! has '✓ 부하 5분 평균' \
    && ok "$n. ⓡ FT_PRESS_LOAD_MAX=$v (부하 100) → rc=1 · «✓ 부하» 줄 없음" \
    || { bad "$n. ⓡ LOAD_MAX=$v (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
done
# 고침 3 을 되돌린 변이 — 60..0 이 «✓ 100.00 < 60..0» PASS 가 되는 모습 재현
siblings "$T/mutdec"
python3 - "$GATE" "$T/mutdec/ft-press-gate.sh" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src, encoding='utf-8').read()
a = '''_decimal(){
  case "$1" in ''|*[!0-9.]*|.*|*.|*.*.*) return 1 ;; esac
  return 0
}'''
b = '''_decimal(){ case "$1" in ''|*[!0-9.]*) return 1 ;; esac; return 0; }'''
assert a in s
open(dst, 'w', encoding='utf-8').write(s.replace(a, b, 1))
PY
chmod +x "$T/mutdec/ft-press-gate.sh"
mkworld rm
gate "$T/mutdec/ft-press-gate.sh" rm FAKE_LOADAVG='1.0 100.0 1.0' FT_PRESS_LOAD_MAX='60..0'
n=$((n+1)); has '✓ 부하 5분 평균 100.0 < 임계 60..0' && ok "$n. ⓡ 변이(점 개수 검사 삭제) → «✓ 100.00 < 60..0» 재현 ⇒ ⓡ 이 이 변이를 죽인다" \
  || { bad "$n. ⓡ 변이"; printf '%s\n' "$OUT" | grep '부하' | sed 's/^/    /'; }

# ── ⓢ 정상 값은 지금과 같은 출력(38341 · 60 · 72.5)
mkworld s
gate "$GATE" s FT_PRESS_PORT_BASE=38341 FT_PRESS_LOAD_MAX=60 FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:38343/api/v1/health/"
n=$((n+1)); [ "$RC" = 1 ] && has '포트 갈래: FT_PRESS_PORT_BASE=38341 → gateway 38341 · worker 38342 · 화면 38343' \
  && has '부하 5분 평균 0.20 < 임계 60' && has 'worker 리스너 없음(:38342)' && ! has '숫자 1024~65535 가 아니다' \
  && ok "$n. ⓢ 정상 값(38341 · 60) → 통과 경로 그대로(파생 포트 38342·38343 · ✗ 숫자 줄 없음)" \
  || { bad "$n. ⓢ 정상 값 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
gate "$GATE" s FT_PRESS_PORT_BASE=38341 FT_PRESS_LOAD_MAX=72.5 FAKE_LOADAVG='1.0 72.40 1.0' \
  FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:38343/api/v1/health/"
n=$((n+1)); [ "$RC" = 1 ] && has '✓ 부하 5분 평균 72.40 < 임계 72.5' && ok "$n. ⓢ 소수 임계 72.5 도 정상 처리" \
  || { bad "$n. ⓢ 소수 임계 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

echo
[ "$fail" = 0 ] && { echo "ALL PASS ($n)"; exit 0; }
echo "FAILED $fail / $n"; exit 1
