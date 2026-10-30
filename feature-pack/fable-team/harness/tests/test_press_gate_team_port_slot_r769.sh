#!/usr/bin/env bash
# test_press_gate_team_port_slot_r769.sh — r769: press 게이트 «로컬 갈래» 가 팀이 선언한 포트 슬롯을 따른다.
#   FT_PRESS_PORTS("gw,worker,fe") > FT_PRESS_PORT_BASE(+0/+1/+2) > 기본 8080·8081·3001 · 기본이 아닌 갈래는 로그·SSE 주소도 필수.
#   ★일반 FT_PORT_BASE 는 «읽지 않는다»(팀 env 가 export 해도 press 갈래 불변 — lecture 꼴 회귀)★
#   가짜 lsof·curl·tmux 만(그 밖의 실행은 실물) · 실 8080/8081/3001/8443 접촉 0 · 리포 파일 쓰기 0.
#   ⓐ 빨강(옛 판 HEAD) ⓑ 슬롯 리스너를 찾음 ⓒ PORTS 우선 ⓓ 기본 바이트 불변 ⓔ 반쪽 선언 ⓕ 잘못된 값 ⓖ 변이 ⓘ 실 접촉 0
#   r1134: 옛 ⓗ(r634 전부를 이 안에서 다시 돌림 · 그것만 ~130초)는 뺐다 — 기본 실행에선 r634 와 같은 판을 한 번 더 도는 중복이었다(하드 룰 22).
#   R769_SUT 로 다른 판을 볼 땐 R634_SUT=<같은 판> 으로 test_press_gate_dev_target_r634_a.sh·_b.sh·_c.sh 를 각각 돌린다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${R769_SUT:-$HERE/../../harness/bin/ft-press-gate.sh}"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)" || { echo "리포 루트 못 찾음" >&2; exit 1; }
OLDREL="feature-pack/fable-team/harness/bin/ft-press-gate.sh"   # 이 카드의 추적 정본 경로(harness/bin == kit 짝)
fail=0; n=0
ok(){ echo "PASS $1"; }
bad(){ echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$GATE" && /bin/bash -n "$GATE" && ok "bash -n gate(bash5·3.2)" || bad "bash -n gate"
cmp -s "$GATE" "$HERE/../kit/fable-team/bin/ft-press-gate.sh" && ok "kit 짝 cmp0" || bad "kit 짝 cmp0 (kit 사본과 다름)"

T="$(mktemp -d)"; SRV=(); trap 'for p in "${SRV[@]:-}"; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
siblings(){ # $1 임시 폴더 — 게이트가 형제(ft-all-stop.sh 등)를 $HERE 에서 찾으므로 «같은 폴더» 를 만든다
  mkdir -p "$1"
  for f in "$HERE/../bin"/*; do [ "$(basename "$f")" = ft-press-gate.sh ] && continue; ln -sf "$f" "$1/$(basename "$f")"; done
}
OLD="$T/oldbin/ft-press-gate.sh"
siblings "$T/oldbin"
# «옛 판» = 이 카드(포트 갈래) 를 아직 안 가진 최신 커밋의 파일 — HEAD 를 쓰면 커밋 뒤엔 빨강 대조가 무의미해진다
OLD_SHA=""
for sha in $(git -C "$ROOT" log --format=%H -30 -- "$OLDREL" 2>/dev/null); do
  git -C "$ROOT" show "$sha:$OLDREL" 2>/dev/null | grep -q '_ports(){' || { OLD_SHA="$sha"; break; }
done
[ -n "$OLD_SHA" ] || { echo "옛 판(포트 갈래 이전 커밋) 못 찾음" >&2; exit 1; }
git -C "$ROOT" show "$OLD_SHA:$OLDREL" > "$OLD.raw" 2>/dev/null || { echo "옛 판 내용 못 꺼냄($OLD_SHA)" >&2; exit 1; }
rm -f "$OLD" && cp "$OLD.raw" "$OLD" && chmod +x "$OLD"
[ -s "$OLD" ] && ok "빨강 대조용 옛 판(${OLD_SHA:0:9} · 포트 갈래 이전) 확보" || bad "옛 판 확보"

# ── 가짜 도구(엄격 · 호출 전량 기록)
FB="$T/fb"; mkdir -p "$FB"
cat > "$FB/sysctl" <<'S'
#!/bin/sh
printf '{ 0.50 0.50 0.50 }\n'   # r769b 부하 게이트 — 이 시험은 포트 갈래만 본다(호스트 부하 무관)
S
cat > "$FB/lsof" <<'L'
#!/bin/sh
echo "lsof $*" >> "${STUB_LOG:-/dev/null}"
exit 1   # 리스너 0 — 이 머신의 실제 포트에 좌우되지 않게
L
cat > "$FB/curl" <<'C'
#!/bin/sh
echo "curl $*" >> "${STUB_LOG:-/dev/null}"
printf '000'; exit 7
C
cat > "$FB/tmux" <<'X'
#!/bin/sh
case "$1" in
  list-sessions) exit 0 ;;
  display-message) echo 'byz-v65-tester-claude#0' ;;
esac
X
chmod +x "$FB"/*

# ── 세계: 임시 리포 + 명부 + 워커 로그(③ 이 읽는 3줄). 가짜 도구는 «칸마다 새 복사».
mkworld(){ # $1 이름 · $2 = stub(기본) | real(가짜 도구 없이 = 실제 lsof·curl)
  W="$T/w-$1"; rm -rf "$W"
  R="$W/repo"; mkdir -p "$R/worker" "$R/shared" "$R/gateway" "$R/clients/web" "$W/root/.fable-team" "$W/fb"
  [ "${2:-stub}" = real ] && { cp "$FB/tmux" "$FB/sysctl" "$W/fb"/; } || cp "$FB"/* "$W/fb"/
  echo '{}' > "$W/root/.fable-team/seats.json"
  mkdir -p "$W/root/.fable-team/state"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$W/root/.fable-team/state/all-stop.log"   # ⓪ 전팀 정지 아님
  echo 'x = 1' > "$R/worker/a.py"
  git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  git -C "$R" add -A >/dev/null; git -C "$R" commit -qm base
  printf 'activation bundle established\nWorker Starting - Warming up services\nselfhost prewarm SUMMARY: 5 ok / 0 FAILED\n' > "$W/worker.log"
}
gate(){ # $1 판 · $2 태그 [env…] → OUT · RC
  local sut="$1" tag="$2"; shift 2
  OUT="$(env -u FT_PRESS_TARGET -u FT_PRESS_PORT_BASE -u FT_PORT_BASE -u FT_PRESS_PORTS -u FT_PRESS_WORKER_LOG -u FT_PRESS_SSE_HEALTH_URL \
    -u FT_PRESS_SEAT -u FT_PRESS_GATE_SELFTEST -u TMUX_PANE \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$W/root" FT_PRESS_EVID="$W/ev-$tag" FT_PRESS_PERMIT_DIR="$W/permits-$tag" \
    TMUX_PANE=%1 STUB_LOG="$W/stub-$tag.log" PATH="$W/fb:$PATH" "$@" bash "$sut" 2>&1)"; RC=$?
}
has(){ printf '%s' "$OUT" | grep -q -- "$1"; }
hasnt(){ ! printf '%s' "$OUT" | grep -q -- "$1"; }

# ══ ⓐ 빨강: 옛 판(HEAD)에 슬롯을 선언해도 8081 을 본다
mkworld a
gate "$OLD" a FT_PRESS_PORT_BASE=38331 FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:38333/api/v1/health/"
n=$((n+1)); has '리스너 없음(:8081)' && ok "$n. ⓐ 옛 판 = 슬롯 선언에도 «worker 리스너 없음(:8081)» 막힘(RED 재현)" || bad "$n. ⓐ 옛 판이 슬롯을 못 본다"

# ══ ⓑ 후판: FT_PRESS_PORT_BASE 슬롯에 실제 리스너 3개 → 게이트가 슬롯 포트를 본다
BASE="$(python3 - <<'PY'
import socket
for base in range(39100, 39300):
    ss, ok = [], True
    for p in (base, base+1, base+2):
        s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try: s.bind(('127.0.0.1', p))
        except OSError: ok = False; s.close(); break
        ss.append(s)
    if ok:
        print(base)
        for s in ss: s.close()
        break
PY
)"
[ -n "$BASE" ] && ok "임시 포트 슬롯 확보 base=$BASE" || bad "임시 포트 슬롯 확보"
for i in 0 1 2; do
  ( cd "$T" && exec python3 -m http.server "$((BASE+i))" --bind 127.0.0.1 >/dev/null 2>&1 ) & SRV+=($!)
done
sleep 1
mkworld b real
gate "$GATE" b FT_PRESS_PORT_BASE="$BASE" FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:$((BASE+2))/api/v1/health/"
n=$((n+1))
printf '%s' "$OUT" | awk -v pat="포트 갈래: FT_PRESS_PORT_BASE=$BASE → gateway $BASE · worker $((BASE+1)) · 화면 $((BASE+2))" \
  '$0==pat { getline nxt; if (nxt ~ /worker (pid=|리스너 없음)/) found=1 } END{ exit !found }' \
  && has 'worker pid=' && has 'gateway pid=' && has '화면 pid=' && hasnt '리스너 없음' \
  && ok "$n. ⓑ 슬롯 포트 3개를 찾음(갈래 줄 첫 줄 · chk 3/3 pid)" \
  || { bad "$n. ⓑ 슬롯 포트 인식"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
n=$((n+1)); hasnt ':8081' && hasnt ':8080' && hasnt ':3001' && ok "$n. ⓘ1 슬롯 회차가 기본 포트를 «보지 않는다»(출력에 :8080/:8081/:3001 0)" || bad "$n. ⓘ1 기본 포트 흔적"

# ══ ⓒ FT_PRESS_PORTS > FT_PRESS_PORT_BASE
mkworld c
gate "$GATE" c FT_PRESS_PORT_BASE=41000 FT_PRESS_PORTS="42001,42002,42003" FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:42003/api/v1/health/"
n=$((n+1)); has '포트 갈래: FT_PRESS_PORTS=42001,42002,42003 → gateway 42001 · worker 42002 · 화면 42003' \
  && grep -q ':42002' "$W/stub-c.log" && grep -q ':42001' "$W/stub-c.log" \
  && ! grep -q ':41000\|:41001' "$W/stub-c.log" \
  && ok "$n. ⓒ FT_PRESS_PORTS 가 FT_PRESS_PORT_BASE 보다 우선" \
  || { bad "$n. ⓒ PORTS 우선"; printf '%s\n' "$OUT" | sed 's/^/    /'; cat "$W/stub-c.log" 2>/dev/null | sed 's/^/    /'; }

# ══ ⓓ 선언 없음 = 기본 갈래 · 기존 출력 바이트 불변(갈래 줄 1줄 추가 외)
#   ★lecture 꼴 회귀★: 팀 env 가 일반 FT_PORT_BASE=38341 을 «export 한 채» 돌려도 기본 갈래여야 한다(arch r1 3)
mkworld d
gate "$OLD" old
OLD_OUT="$OUT"
gate "$GATE" new FT_PORT_BASE=38341
NEW_OUT="$(printf '%s\n' "$OUT" | grep -v '^포트 갈래: 기본$' | grep -v '^[✓✗⚠] 부하 5분 평균' | grep -v '^[✓✗] ④-b 화면 env')"   # 갈래 줄 + r769b 부하 줄 + r1196 ④-b 줄은 뺀다
n=$((n+1)); has '포트 갈래: 기본' \
  && [ "$(printf '%s\n' "$OUT" | grep -c '^포트 갈래:')" = "1" ] \
  && grep -q ':8081' "$W/stub-new.log" && grep -q ':8080' "$W/stub-new.log" && grep -q ':3001' "$W/stub-new.log" \
  && grep -q 'localhost:8443/api/v1/health/' "$W/stub-new.log" \
  && ! grep -q '38341\|38342\|38343' "$W/stub-new.log" \
  && ok "$n. ⓓ FT_PORT_BASE=38341 export 된 채여도 기본 갈래(기본 포트·로그·SSE 만 접촉)" \
  || { bad "$n. ⓓ 기본 갈래(lecture 꼴)"; printf '%s\n' "$OUT" | sed 's/^/    /'; cat "$W/stub-new.log" 2>/dev/null | sed 's/^/    /'; }
OLD_OUT="$(printf '%s\n' "$OLD_OUT" | sed 's|/ev-old/|/ev-TAG/|g')"; NEW_OUT="$(printf '%s\n' "$NEW_OUT" | sed 's|/ev-new/|/ev-TAG/|g')"
n=$((n+1)); [ "$NEW_OUT" = "$OLD_OUT" ] && ok "$n. ⓓ 기존 출력 바이트 불변(갈래 줄 1줄 빼고 포트 갈래 이전 판과 같음)" \
  || { bad "$n. ⓓ 바이트 불변"; diff <(printf '%s\n' "$OLD_OUT") <(printf '%s\n' "$NEW_OUT") | sed 's/^/    /'; }

# ══ ⓔ 선언 반쪽 = 막힘
mkworld e
gate "$GATE" e FT_PRESS_PORT_BASE=38331 FT_PRESS_WORKER_LOG="$W/worker.log"
n=$((n+1)); [ "$RC" = 1 ] && has '슬롯 선언 회차는 worker 로그·SSE health 주소도 지정' && ok "$n. ⓔ1 로그만 선언 → 막힘(exit $RC)" \
  || { bad "$n. ⓔ1 반쪽 선언(로그만) (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
gate "$GATE" e2 FT_PRESS_PORT_BASE=38331 FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:38333/api/v1/health/"
n=$((n+1)); [ "$RC" = 1 ] && has '슬롯 선언 회차는 worker 로그·SSE health 주소도 지정' && ok "$n. ⓔ2 SSE 만 선언 → 막힘(exit $RC)" \
  || { bad "$n. ⓔ2 반쪽 선언(SSE 만) (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ══ ⓕ 잘못된 값 = 막힘(리스너 접촉 0)
for pair in "abc|FT_PRESS_PORT_BASE 가 숫자" "80|FT_PRESS_PORT_BASE 가 숫자|" "70000|FT_PRESS_PORT_BASE 가 숫자"; do
  v="${pair%%|*}"; pat="FT_PRESS_PORT_BASE 가 숫자"
  mkworld "f$v"
  gate "$GATE" "f$v" FT_PRESS_PORT_BASE="$v" FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:38333/api/v1/health/"
  n=$((n+1)); [ "$RC" = 1 ] && has "$pat" && [ ! -s "$W/stub-f$v.log" ] \
    && ok "$n. ⓕ FT_PRESS_PORT_BASE=$v → 막힘 · 리스너 접촉 0(exit $RC)" \
    || { bad "$n. ⓕ FT_PRESS_PORT_BASE=$v (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
done
for v in "a,b" "1,2,3,4" "42001,42002,abc"; do
  mkworld "p$(printf '%s' "$v" | tr -d ,)"
  gate "$GATE" "p$(printf '%s' "$v" | tr -d ,)" FT_PRESS_PORTS="$v" FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:38333/api/v1/health/"
  n=$((n+1)); [ "$RC" = 1 ] && has 'FT_PRESS_PORTS' && [ ! -s "$W/stub-p$(printf '%s' "$v" | tr -d ,).log" ] \
    && ok "$n. ⓕ FT_PRESS_PORTS=$v → 막힘 · 리스너 접촉 0(exit $RC)" \
    || { bad "$n. ⓕ FT_PRESS_PORTS=$v (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
done
mkworld f65534
gate "$GATE" f65534 FT_PRESS_PORT_BASE=65534 FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:65536/api/v1/health/"
n=$((n+1)); [ "$RC" = 1 ] && has '65535 밖' && ok "$n. ⓕ FT_PRESS_PORT_BASE=65534(+2=65536) → 막힘(exit $RC)" \
  || { bad "$n. ⓕ 포트 상한 (exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ══ ⓖ 변이 — 시험이 실제로 잡는지
mut(){ # $1 이름 · $2 원문 · $3 바꾼문
  siblings "$T/mut-$1"
  python3 - "$GATE" "$T/mut-$1/ft-press-gate.sh" "$2" "$3" <<'PY' || return 1
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding='utf-8').read()
if a not in s: sys.exit("mut: 원문 없음")
open(dst, 'w', encoding='utf-8').write(s.replace(a, b, 1))
PY
  chmod +x "$T/mut-$1/ft-press-gate.sh"; }
mkworld g1
mut g1 'chk worker "$WK_PORT"' 'chk worker 8081' && ok "변이 g1 준비(worker chk 를 8081 고정)" || bad "변이 g1 준비"
gate "$T/mut-g1/ft-press-gate.sh" g1 FT_PRESS_PORT_BASE="$BASE" FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL="http://127.0.0.1:$((BASE+2))/api/v1/health/"
n=$((n+1)); has '리스너 없음(:8081)' && ok "$n. ⓖ1 변이(worker chk 8081 고정) → ⓑ 가 FAIL 할 모습 재현" \
  || bad "$n. ⓖ1 변이 g1 이 안 잡힘"
mkworld g2
mut g2 'if [ -z "${FT_PRESS_WORKER_LOG:-}" ] || [ -z "${FT_PRESS_SSE_HEALTH_URL:-}" ]; then' 'if false; then' && ok "변이 g2 준비(반쪽 선언 검사 삭제)" || bad "변이 g2 준비"
gate "$T/mut-g2/ft-press-gate.sh" g2 FT_PRESS_PORT_BASE=38331 FT_PRESS_WORKER_LOG="$W/worker.log"
n=$((n+1)); hasnt '슬롯 선언 회차는 worker 로그·SSE health 주소도 지정' && ok "$n. ⓖ2 변이(검사 삭제) → ⓔ 가 FAIL 할 모습 재현" \
  || bad "$n. ⓖ2 변이 g2 가 안 잡힘"

echo
[ "$fail" = 0 ] && { echo "ALL PASS ($n)"; exit 0; }
echo "FAILED $fail / $n"; exit 1
