#!/usr/bin/env bash
# test_press_gate_load_gate_r769.sh — r769b: press 게이트 «부하 게이트»(5분 평균 load ≥ 임계면 시작 REJECT + 원인 상위 3).
#   왜: 부하 81~102 에서 돈 lecture p3-r6 이 청크 POST 1500ms 초과 15 · Redis Timeout 14 로 무효.
#   ★이 시험의 세계는 «나머지 검사 전부 통과»(dev 갈래)로 고정한다★ — 그래야 rc 가 «부하 게이트 때문에» 1 인지
#   다른 검사 실패에 기댄 1 인지 구분된다(arch r1 반송 2). 가짜 sysctl·ps·curl·gcloud·tmux 만 · 실제 부하·발사 0.
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
[ "${FAKE_LOAD_NONE:-0}" = "1" ] && exit 1   # 부하 «못 읽음» 경로
printf '{ %s }\n' "${FAKE_LOADAVG:-0.10 0.20 0.30}"
S
cat > "$FB/ps" <<'P'
#!/bin/sh
printf ' %%CPU   PID COMM\n 74.2 111 probe\n 61.9 222 XprotectService\n 57.8 333 claude\n'
P
cat > "$FB/lsof" <<'L'
#!/bin/sh
exit 1
L
cat > "$FB/tmux" <<'X'
#!/bin/sh
case "$1" in list-sessions) exit 0 ;; display-message) echo 'byz-v65-tester-claude#0' ;; esac
X
# dev 갈래를 «전부 통과» 시키는 스텁 — 주소는 게이트 기본값과 같아야 한다(다르면 _dev_runner 가 막는다)
EXP_WEB=https://byz-agents-web-dev-a3yix5apcq-du.a.run.app
EXP_GW=https://byz-agents-gateway-dev-a3yix5apcq-du.a.run.app
cat > "$FB/curl" <<C
#!/bin/sh
url=""; of=""
while [ \$# -gt 0 ]; do
  case "\$1" in -o) of=\$2; shift 2 ;; -m|-w) shift 2 ;; -s|-k) shift ;; http*) url=\$1; shift ;; *) shift ;; esac
done
case "\$url" in
  "$EXP_WEB/") body='<!DOCTYPE html><html lang="ko"><head><title>하우투 톡 — 실시간 AI 음성 통역</title><script src="/_next/static/chunks/main.js"></script></head><body><main>하우투 톡 실시간 AI 통역 — 병원 진료 설명도 바로 통역합니다</main></body></html>' ;;
  "$EXP_GW/api/v1/health/") body='{"status":"ok","consumer_ready":true}' ;;
  *) body='not found'; code=404 ;;
esac
[ -n "\$of" ] && printf '%s' "\$body" > "\$of"
printf '%s' "\${code:-200}"
C
cat > "$FB/gcloud" <<'G'
#!/bin/sh
printf 'r/%s:%s\n' "$4" "${FAKE_IMG:-$DEV_WANT_SHA}"
G
chmod +x "$FB"/*

mkworld(){ # $1 이름
  W="$T/w-$1"; rm -rf "$W"
  R="$W/repo"; mkdir -p "$R/worker" "$R/design/v65/baselines/ev" "$W/root/.fable-team/state" "$W/fb"
  cp "$FB"/* "$W/fb"/
  echo '{}' > "$W/root/.fable-team/seats.json"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$W/root/.fable-team/state/all-stop.log"
  git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  echo 'x = 1' > "$R/worker/a.py"
  printf '| key | 기본값 | OFF 값 | 읽는 자리 |\n|---|---|---|---|\n| `V65_TOGGLE_A` | `1` | `0` | worker/a.py:1 |\n' > "$R/design/v65/baselines/FLAGS.md"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | v | 현역 |\n' > "$R/design/TEAMS.md"
  git -C "$R" add -A >/dev/null; git -C "$R" commit -qm base
  SHA="$(git -C "$R" rev-parse HEAD)"
  printf '{"set_sha":"%s","side_lang_at_press":{"right":"ko","left":"en"},"session_id":"run-1","failed":false}\n' "$SHA" > "$R/design/v65/baselines/ev/RESULT-ok.json"
  { echo "set_sha: $SHA"; echo "control: lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=PRESS_SIDE_LANG_CLICK:1 flags=V65_TOGGLE_A=1"
    echo "side_lang: right=ko left=en"; echo "server_ready: 2026-10-07T03:00:00Z"; echo "visible_at_settle: yes"
    echo "evidence: design/v65/baselines/ev/RESULT-ok.json"; echo "run_id: run-1"; printf '\n| 칸 | 값 |\n|---|---|\n| 빈 칸 | 0 |\n'; } > "$R/design/v65/baselines/ok.md"
  printf '# 카드 c-ok\n기준선: design/v65/baselines/ok.md\n실험: 없음\n' > "$R/card.md"
  git -C "$R" add -A >/dev/null; git -C "$R" commit -qm card
  DEV_WANT_SHA="$(git -C "$R" rev-parse HEAD)"
}
gate(){ # $1 태그 [env…] → OUT · RC  (dev 갈래 전부 통과 세계 · 부하만 변수)
  local tag="$1"; shift
  OUT="$(env -u FT_PRESS_LOAD_MAX -u FT_PRESS_TARGET -u FT_PRESS_PORTS -u FT_PRESS_PORT_BASE -u FT_PORT_BASE \
    -u FT_PRESS_SEAT -u FT_PRESS_GATE_SELFTEST -u TMUX -u TMUX_PANE \
    FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT="$DEV_WANT_SHA" BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" \
    DEV_WANT_SHA="$DEV_WANT_SHA" FT_PRESS_WT="$R" FT_PRESS_ROOT="$W/root" FT_PRESS_CARD="$R/card.md" \
    FT_PRESS_EVID="$W/ev-$tag" FT_PRESS_PERMIT_DIR="$W/permits-$tag" \
    TMUX_PANE=%1 STUB_LOG="$W/stub-$tag.log" PATH="$W/fb:$PATH" "$@" bash "$SUTX" 2>&1)"; RC=$?
}
has(){ printf '%s' "$OUT" | grep -q -- "$1"; }
lacks(){ ! printf '%s' "$OUT" | grep -q -- "$1"; }
SUTX="$GATE"

# ── 세계가 «전부 통과» 하는지 먼저 못 박는다(부하 낮음 = rc 0)
mkworld a
gate a FAKE_LOADAVG='0.10 0.20 0.30'
n=$((n+1)); [ "$RC" = 0 ] && has 'PRESS-GATE PASS' && has '✓ 부하 5분 평균 0.20 < 임계 60' \
  && ok "$n. 기준 세계: 부하 0.20 < 60 → 게이트 통과(rc=0 · 나머지 검사 전부 green)" \
  || { bad "$n. 기준 세계가 통과하지 않는다 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ⓐ 부하 높음 → rc=1 · 사유 줄 · 상위 3
mkworld b
gate b FAKE_LOADAVG='1.00 81.50 20.00'
n=$((n+1)); [ "$RC" = 1 ] && has '5분 평균 부하 81.50 ≥ 임계 60' && has '원인 상위 3' && lacks 'PRESS-GATE PASS' \
  && ok "$n. ⓐ 부하 81.5 → rc=1 · «5분 평균 부하…» 사유 줄(다른 검사는 전부 green 인 세계)" \
  || { bad "$n. ⓐ 부하 높음 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
n=$((n+1)); [ "$(printf '%s\n' "$OUT" | grep -cE '^ +[0-9.]+ +[0-9]+ ')" -ge 3 ] && has '111 probe' \
  && ok "$n. ⓐ 원인 상위 3 프로세스가 실제로 찍힘(3줄+)" \
  || { bad "$n. ⓐ 상위 3 줄"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ⓑ 변이 — 고부하 분기의 «FAIL=1» 만 지우면 이 시험이 빨강이어야 한다(rc 로 판정)
mkdir -p "$T/mutbin"
for f in "$HERE/../bin"/*; do [ "$(basename "$f")" = ft-press-gate.sh ] && continue; ln -sf "$f" "$T/mutbin/$(basename "$f")"; done
python3 - "$GATE" "$T/mutbin/ft-press-gate.sh" <<'PY'
import sys
src, dst = sys.argv[1:3]
a = '    FAIL=1; return\n  fi\n  say "✓" "부하 5분 평균'
s = open(src, encoding='utf-8').read()
assert a in s, "변이 원문 없음"
open(dst, 'w', encoding='utf-8').write(s.replace(a, '    return\n  fi\n  say "✓" "부하 5분 평균', 1))
PY
chmod +x "$T/mutbin/ft-press-gate.sh" 2>/dev/null && ok "변이 준비(고부하 FAIL=1 삭제)" || bad "변이 준비"
mkworld c
SUTX="$T/mutbin/ft-press-gate.sh"
gate c FAKE_LOADAVG='1.00 81.50 20.00'
SUTX="$GATE"
n=$((n+1)); [ "$RC" = 0 ] && has '✗ 5분 평균 부하 81.50' \
  && ok "$n. ⓑ 변이(FAIL=1 삭제) → rc=0 이지만 ✗ 부하 줄은 남는다 ⇒ ⓐ 의 «rc=1» 단언이 이 변이를 죽인다" \
  || { bad "$n. ⓑ 변이 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ⓒ 부하 못 읽음(sysctl 실패 + /proc 없음) → «⚠ … 건너뜀» · 다른 검사 결과 그대로(rc 0)
mkworld d
gate d FAKE_LOAD_NONE=1
n=$((n+1)); [ "$RC" = 0 ] && has '부하 5분 평균 못 읽음 — 부하 게이트 건너뜀' && has 'PRESS-GATE PASS' && lacks '건너뛀' \
  && ok "$n. ⓒ 부하 못 읽음 → ⚠ 건너뜀(오타 없음) · 나머지 검사 결과 그대로(rc=0)" \
  || { bad "$n. ⓒ 못 읽음 경로 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ⓓ 임계 env 덮어쓰기 — 30 이면 30.5 막고 29.9 통과
mkworld e
gate e FAKE_LOADAVG='10.0 30.50 10.0' FT_PRESS_LOAD_MAX=30
n=$((n+1)); [ "$RC" = 1 ] && has '5분 평균 부하 30.50 ≥ 임계 30' && ok "$n. ⓓ FT_PRESS_LOAD_MAX=30 에서 30.5 → rc=1" \
  || { bad "$n. ⓓ 임계 덮어쓰기 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
gate e FAKE_LOADAVG='10.0 29.90 10.0' FT_PRESS_LOAD_MAX=30
n=$((n+1)); [ "$RC" = 0 ] && has '✓ 부하 5분 평균 29.90 < 임계 30' && ok "$n. ⓓ 임계 30 아래(29.9) → rc=0" \
  || { bad "$n. ⓓ 임계 아래 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ⓕ 거절 = «기다림 신호» — 지금 load · 기준(FT_PRESS_LOAD_MAX) · 다시 볼 시각 3요소가 1줄에(planner 2681)
mkworld g
gate g FAKE_LOADAVG='1.00 81.50 20.00' FT_PRESS_LOAD_MAX=60
n=$((n+1)); [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -qE "^· 지금 load 81.50 · 기준 FT_PRESS_LOAD_MAX=60 · 다시 볼 시각 [0-9]{2}:[0-9]{2} " \
  && ok "$n. ⓕ REJECT 줄에 지금 load·기준·다시 볼 시각 3요소(기다림 신호)" \
  || { bad "$n. ⓕ 다시 볼 시각 줄 (rc=$RC)"; printf '%s\n' "$OUT" | grep '다시 볼' | sed 's/^/    /'; printf '%s\n' "$OUT" | sed 's/^/    /' | tail -12; }

# ⓔ 잘못된 임계 = 막힘
mkworld f
gate f FAKE_LOADAVG='1.0 2.0 3.0' FT_PRESS_LOAD_MAX=abc
n=$((n+1)); [ "$RC" = 1 ] && has 'FT_PRESS_LOAD_MAX=abc — 숫자' && ok "$n. ⓔ 임계=abc → rc=1(사유 줄)" \
  || { bad "$n. ⓔ 잘못된 임계 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

echo
[ "$fail" = 0 ] && { echo "ALL PASS ($n)"; exit 0; }
echo "FAILED $fail / $n"; exit 1
