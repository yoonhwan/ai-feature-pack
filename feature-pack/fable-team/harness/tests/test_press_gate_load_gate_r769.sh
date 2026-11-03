#!/usr/bin/env bash
# test_press_gate_load_gate_r769.sh — r769 단계 2(판정 3927 · 오빠 «C»): press 게이트 «부하 차단 해제 · 값 1줄».
#   계약: 5분 평균 load 가 아무리 높아도 차단 0 · 「부하 5분 평균 <v> (참고 · 차단 0)」 1줄만 · FT_PRESS_LOAD_MAX 는 무시 1줄 ·
#         못 읽으면 ⚠ 1줄 · 부하 때문에 rc 가 1 이 되는 길 0 · 다른 칸의 막힘은 그대로(L6).
#   ★이 시험의 세계는 «나머지 검사 전부 통과»(dev 갈래)로 고정한다★ — rc 가 «부하 때문에» 바뀌는지 다른 검사에 기대는지 갈린다.
#   가짜 sysctl·ps·curl·gcloud·tmux 만 · 실제 부하·발사 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${R769B_SUT:-$HERE/../../harness/bin/ft-press-gate.sh}"
fail=0; n=0
ok(){ echo "PASS $1"; }
bad(){ echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
# L7 bin·kit 같은 판
cmp -s "$GATE" "$HERE/../kit/fable-team/bin/ft-press-gate.sh" && ok "L7 kit 짝 cmp0" || bad "L7 kit 짝 cmp0"

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
count(){ printf '%s\n' "$OUT" | grep -c -- "$1"; }
SUTX="$GATE"

# ── 기준 세계: 부하 낮음(L2) → 같은 1줄 꼴 · rc 0 (나머지 검사 전부 green 인 세계임을 먼저 못 박는다)
mkworld a
gate a FAKE_LOADAVG='1.0 5.0 1.0'
n=$((n+1)); [ "$RC" = 0 ] && has 'PRESS-GATE PASS' && has '· 부하 5분 평균 5.0 (참고 · 차단 0)' && [ "$(count '부하 5분 평균')" = 1 ] && lacks '임계' \
  && ok "$n. L2 부하 5.0 → 「부하 5분 평균 5.0 (참고 · 차단 0)」 1줄 · rc=0 · PASS" \
  || { bad "$n. L2 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ── L1 부하 100 → 같은 1줄 · «≥ 임계» 0 · 부하 때문에 rc 1 아님 · 상위 3 프로세스 줄 0
mkworld b
gate b FAKE_LOADAVG='10.0 100.0 10.0'
n=$((n+1)); [ "$RC" = 0 ] && has 'PRESS-GATE PASS' && has '· 부하 5분 평균 100.0 (참고 · 차단 0)' && [ "$(count '부하 5분 평균')" = 1 ] \
  && lacks '≥ 임계' && lacks '원인 상위 3' && lacks '111 probe' && lacks '다시 볼 시각' \
  && ok "$n. L1 부하 100 → 값 1줄만 · «≥ 임계»·상위 3·다시 볼 시각 0 · rc=0 · PASS" \
  || { bad "$n. L1 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ── L3 FT_PRESS_LOAD_MAX=30 + 부하 100 → 무시 1줄 · 값 1줄 · rc 0
mkworld c
gate c FAKE_LOADAVG='10.0 100.0 10.0' FT_PRESS_LOAD_MAX=30
n=$((n+1)); [ "$RC" = 0 ] && has '⚠ FT_PRESS_LOAD_MAX 무시(판정 3927 · 부하 차단 없음)' && [ "$(count 'FT_PRESS_LOAD_MAX')" = 1 ] \
  && has '· 부하 5분 평균 100.0 (참고 · 차단 0)' && lacks '≥ 임계' && has 'PRESS-GATE PASS' \
  && ok "$n. L3 FT_PRESS_LOAD_MAX=30 + 부하 100 → 무시 1줄 + 값 1줄 · rc=0" \
  || { bad "$n. L3 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ── L4 이상한 값 3종 → 같은 무시 1줄 · «숫자(부하 임계)만» 0 · rc 0
for v in '60..0' '1e2' '-1'; do
  mkworld "d$(printf '%s' "$v" | tr -cd '0-9a-z')"
  gate "d$(printf '%s' "$v" | tr -cd '0-9a-z')" FAKE_LOADAVG='10.0 100.0 10.0' FT_PRESS_LOAD_MAX="$v"
  n=$((n+1)); [ "$RC" = 0 ] && has '⚠ FT_PRESS_LOAD_MAX 무시' && lacks '숫자(부하 임계)만' && lacks '✗' && has 'PRESS-GATE PASS' \
    && ok "$n. L4 FT_PRESS_LOAD_MAX=$v → 무시 1줄 · «숫자(부하 임계)만» 0 · rc=0" \
    || { bad "$n. L4 LOAD_MAX=$v (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
done

# ── L5 loadavg 못 읽음 → ⚠ 1줄 · rc 0
mkworld e
gate e FAKE_LOAD_NONE=1
n=$((n+1)); [ "$RC" = 0 ] && has '⚠ 부하 5분 평균 못 읽음' && lacks '(참고 · 차단 0)' && has 'PRESS-GATE PASS' \
  && ok "$n. L5 loadavg 못 읽음 → ⚠ 못 읽음 1줄 · rc=0" \
  || { bad "$n. L5 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ── L6 다른 칸 FAIL(dev 이미지 sha 불일치) → 부하 낮아도 높아도 그대로 rc 1 (부하 제거가 다른 관문을 안 엶)
mkworld f
gate f FAKE_LOADAVG='10.0 100.0 10.0' FAKE_IMG=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
n=$((n+1)); [ "$RC" = 1 ] && has '✗' && lacks 'PRESS-GATE PASS' && has '· 부하 5분 평균 100.0 (참고 · 차단 0)' \
  && ok "$n. L6 다른 칸(dev 이미지 불일치) FAIL → rc=1 그대로 · 부하 줄은 참고로 남음" \
  || { bad "$n. L6 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ── 변이 — 게이트 사본을 고쳐 «옛 동작을 되살리면» 위 단언이 빨강이 되는지(rc 로 판정)
mkdir -p "$T/mutbin"
for f in "$HERE/../bin"/*; do [ "$(basename "$f")" = ft-press-gate.sh ] && continue; ln -sf "$f" "$T/mutbin/$(basename "$f")"; done
mutate(){ # $1 이름 $2 바꿀 원문 $3 새 문장
  python3 - "$GATE" "$T/mutbin/ft-press-gate.sh" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding='utf-8').read()
assert a in s, "변이 원문 없음"
open(dst, 'w', encoding='utf-8').write(s.replace(a, b, 1))
PY
  chmod +x "$T/mutbin/ft-press-gate.sh"
}
# 변이 1: FAIL=1 되살림 → L1 이 rc 1 로 빨강
mutate m1 '  say "·" "부하 5분 평균 $v (참고 · 차단 0)"' '  say "·" "부하 5분 평균 $v (참고 · 차단 0)"; awk -v a="$v" "BEGIN{exit !(a>=60)}" && FAIL=1'
mkworld m1
SUTX="$T/mutbin/ft-press-gate.sh"; gate m1 FAKE_LOADAVG='10.0 100.0 10.0'; SUTX="$GATE"
n=$((n+1)); [ "$RC" = 1 ] && ok "$n. 변이 1(FAIL=1 되살림) → L1 세계에서 rc=1 ⇒ L1 의 «rc=0» 단언이 이 변이를 죽인다" \
  || { bad "$n. 변이 1 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
# 변이 2: FT_PRESS_LOAD_MAX 다시 읽어 비교 → L3 이 rc 1 로 빨강
mutate m2 '[ -z "${FT_PRESS_LOAD_MAX:-}" ] || say "⚠" "FT_PRESS_LOAD_MAX 무시(판정 3927 · 부하 차단 없음)"' '[ -z "${FT_PRESS_LOAD_MAX:-}" ] || { awk -v a="$(_load5)" -v b="$FT_PRESS_LOAD_MAX" "BEGIN{exit !(a>=b)}" && FAIL=1; }'
mkworld m2
SUTX="$T/mutbin/ft-press-gate.sh"; gate m2 FAKE_LOADAVG='10.0 100.0 10.0' FT_PRESS_LOAD_MAX=30; SUTX="$GATE"
n=$((n+1)); [ "$RC" = 1 ] && lacks '⚠ FT_PRESS_LOAD_MAX 무시' \
  && ok "$n. 변이 2(FT_PRESS_LOAD_MAX 다시 읽어 비교) → L3 세계에서 rc=1 · 무시 줄 없음 ⇒ L3 단언이 이 변이를 죽인다" \
  || { bad "$n. 변이 2 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

echo
[ "$fail" = 0 ] && { echo "ALL PASS ($n)"; exit 0; }
echo "FAILED $fail / $n"; exit 1
