#!/usr/bin/env bash
# test_press_gate_fe_bubble_debug_r1196.sh — r1196: press 게이트 local 갈래 «④-b 화면 env» 가 FE 리스너 부모 env 의
#   NEXT_PUBLIC_BUBBLE_DEBUG=true 를 발사 전에 확인한다(poller 화면 축 data-dbg-* 가 빈 회차를 막음 · #8 RULE).
#   ★세계 = «④-b 말고 전부 통과» 하는 local 갈래★ — 그래야 rc 1 이 ④-b 때문인지 가른다. 옛 판(④-b 이전)은 같은 세계에서 PASS.
#   가짜 lsof·ps·curl·sysctl·tmux·gcloud + 세트 축 stub(ft-press-set-check.sh) · 실 포트·실 서버·실 press 0 · 자기 재호출 0.
#   R1 없음 ✗ · R2 false·빈 값·1 ✗ · R3 true ✓(나머지 줄 옛 판과 같음) · R4 FE 리스너 없음 = 판정 불가 ✗ · R5 dev 갈래 ④-b 0 · 변이(블록 삭제)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${R1196_SUT:-$HERE/../../harness/bin/ft-press-gate.sh}"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)" || { echo "리포 루트 못 찾음" >&2; exit 1; }
REL="feature-pack/fable-team/harness/bin/ft-press-gate.sh"
fail=0; n=0
ok(){ echo "PASS $1"; }
bad(){ echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$GATE" && /bin/bash -n "$GATE" && ok "bash -n gate(bash5·3.2)" || bad "bash -n gate"
cmp -s "$GATE" "$HERE/../kit/fable-team/bin/ft-press-gate.sh" && ok "kit 짝 cmp0" || bad "kit 짝 cmp0"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
binof(){ # $1 폴더 · $2 게이트 원본 — 형제는 실물 링크 · 세트 축(⑤)만 stub(통과)
  mkdir -p "$1"
  for f in "$HERE/../bin"/*; do ln -sf "$f" "$1/$(basename "$f")"; done
  rm -f "$1/ft-press-gate.sh" "$1/ft-press-set-check.sh"
  cp "$2" "$1/ft-press-gate.sh" && chmod +x "$1/ft-press-gate.sh"
  printf '#!/bin/sh\necho "✓ 세트 축 stub"\n' > "$1/ft-press-set-check.sh"; chmod +x "$1/ft-press-set-check.sh"
}
binof "$T/new" "$GATE"
OLD_SHA=""
for sha in $(git -C "$ROOT" log --format=%H -30 -- "$REL" 2>/dev/null); do
  git -C "$ROOT" show "$sha:$REL" 2>/dev/null | grep -q '④-b 화면 env' || { OLD_SHA="$sha"; break; }
done
[ -n "$OLD_SHA" ] && git -C "$ROOT" show "$OLD_SHA:$REL" > "$T/old.sh" && binof "$T/old" "$T/old.sh" \
  && ok "기준판(④-b 이전 ${OLD_SHA:0:9}) 확보" || { bad "기준판 확보"; exit 1; }

FB="$T/fb"; mkdir -p "$FB"
printf '#!/bin/sh\nprintf "{ 0.10 0.20 0.30 }\\n"\n' > "$FB/sysctl"
cat > "$FB/lsof" <<'L'
#!/bin/sh
echo "lsof $*" >> "${STUB_LOG:-/dev/null}"
case "$*" in
  *-ti:8081*) echo 1081 ;;
  *-ti:8080*) echo 1080 ;;
  *-ti:3001*) [ "${FAKE_FE_NONE:-0}" = 1 ] && exit 1; echo 1301 ;;
  *"-d cwd"*) printf 'n%s\n' "$FAKE_CWD" ;;
  *) exit 1 ;;
esac
L
cat > "$FB/ps" <<'P'
#!/bin/sh
echo "ps $*" >> "${STUB_LOG:-/dev/null}"
case "$1 $2" in
  "-o lstart=") echo "Sat Jan  1 00:00:00 2033" ;;
  "-o ppid=") [ "$4" = 1301 ] && echo " 1300" || echo " 1" ;;
  "eww 1081") echo "1081 ?? 0:00 python worker WORKER_KEY_A=1 WORKER_KEY_B=2" ;;
  "eww 1300") echo "1300 ?? 0:00 bash run.command PATH=/bin ${FAKE_FE_ENV:-}" ;;
esac
P
EXP_WEB=https://byz-agents-web-dev-a3yix5apcq-du.a.run.app
EXP_GW=https://byz-agents-gateway-dev-a3yix5apcq-du.a.run.app
cat > "$FB/curl" <<C
#!/bin/sh
url=""; of=""; w=0
while [ \$# -gt 0 ]; do
  case "\$1" in -o) of=\$2; shift 2 ;; -w) w=1; shift 2 ;; -m) shift 2 ;; http*) url=\$1; shift ;; *) shift ;; esac
done
case "\$url" in
  http://localhost:8081/health) body='{"status":"ok","consumer_ready":true}' ;;
  http://stub-sse/api/v1/health/) body='ok' ;;
  "$EXP_WEB/") body='<!DOCTYPE html><html lang="ko"><head><title>하우투 톡 — 실시간 AI 음성 통역</title><script src="/_next/static/chunks/main.js"></script></head><body><main>하우투 톡 실시간 AI 통역 — 병원 진료 설명도 바로 통역합니다</main></body></html>' ;;
  "$EXP_GW/api/v1/health/") body='{"status":"ok","consumer_ready":true}' ;;
  *) body='not found'; code=404 ;;
esac
[ -n "\$of" ] && printf '%s' "\$body" > "\$of"
[ "\$w" = 1 ] && printf '%s' "\${code:-200}" || printf '%s' "\$body"
C
printf '#!/bin/sh\ncase "$1" in list-sessions) exit 0 ;; display-message) echo "byz-v65-tester-claude#0" ;; esac\n' > "$FB/tmux"
printf '#!/bin/sh\nprintf "r/%%s:%%s\\n" "$4" "$DEV_WANT_SHA"\n' > "$FB/gcloud"
chmod +x "$FB"/*

mkworld(){ # $1 이름 — ④-b 말고 전부 통과하는 세계
  W="$T/w-$1"; R="$W/repo"
  mkdir -p "$R/worker" "$R/shared" "$R/gateway" "$R/clients/web" "$R/scripts/server" "$R/design/v65/baselines/ev" "$W/root/.fable-team/state"
  echo '{}' > "$W/root/.fable-team/seats.json"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$W/root/.fable-team/state/all-stop.log"
  for d in worker shared gateway clients/web; do echo 'x = 1' > "$R/$d/a.py"; done
  printf 'WORKER_ENV_SPEC=(\n  "WORKER_KEY_A=x"\n  "WORKER_KEY_B=y"\n)\n' > "$R/scripts/server/ready-check.sh"
  printf '| key | 기본값 | OFF 값 | 읽는 자리 |\n|---|---|---|---|\n| `V65_TOGGLE_A` | `1` | `0` | worker/a.py:1 |\n' > "$R/design/v65/baselines/FLAGS.md"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | v | 현역 |\n' > "$R/design/TEAMS.md"
  git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  git -C "$R" add -A >/dev/null; git -C "$R" commit -qm base
  SHA="$(git -C "$R" rev-parse HEAD)"
  printf '{"set_sha":"%s","side_lang_at_press":{"right":"ko","left":"en"},"session_id":"run-1","failed":false}\n' "$SHA" > "$R/design/v65/baselines/ev/RESULT-ok.json"
  { echo "set_sha: $SHA"; echo "control: lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=PRESS_SIDE_LANG_CLICK:1 flags=V65_TOGGLE_A=1"
    echo "side_lang: right=ko left=en"; echo "server_ready: 2026-10-07T03:00:00Z"; echo "visible_at_settle: yes"
    echo "evidence: design/v65/baselines/ev/RESULT-ok.json"; echo "run_id: run-1"; printf '\n| 칸 | 값 |\n|---|---|\n| 빈 칸 | 0 |\n'; } > "$R/design/v65/baselines/ok.md"
  printf '# 카드 c-ok\n기준선: design/v65/baselines/ok.md\n실험: 없음\n' > "$R/card.md"
  git -C "$R" add -A >/dev/null; git -C "$R" commit -qm card
  DEV_WANT_SHA="$(git -C "$R" rev-parse HEAD)"
  printf 'activation bundle established\nWorker Starting - Warming up services\nselfhost prewarm SUMMARY: 5 ok / 0 FAILED\n' > "$W/worker.log"
}
gate(){ # $1 판(new|old) · $2 태그 [env…] → OUT · RC
  local sut="$T/$1/ft-press-gate.sh" tag="$2"; shift 2
  OUT="$(env -u FT_PRESS_LOAD_MAX -u FT_PRESS_TARGET -u FT_PRESS_PORTS -u FT_PRESS_PORT_BASE -u FT_PORT_BASE \
    -u FT_PRESS_SEAT -u FT_PRESS_GATE_SELFTEST -u TMUX -u TMUX_PANE -u FT_NANO_FEAT -u NEXT_PUBLIC_BUBBLE_DEBUG \
    FT_PRESS_WORKER_LOG="$W/worker.log" FT_PRESS_SSE_HEALTH_URL=http://stub-sse/api/v1/health/ FAKE_CWD="$R" \
    FT_PRESS_DEV_WANT="$DEV_WANT_SHA" BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" DEV_WANT_SHA="$DEV_WANT_SHA" \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$W/root" FT_PRESS_CARD="$R/card.md" \
    FT_PRESS_EVID="$W/ev-$tag" FT_PRESS_PERMIT_DIR="$W/permits-$tag" \
    TMUX_PANE=%1 STUB_LOG="$W/stub-$tag.log" PATH="$FB:$PATH" "$@" bash "$sut" 2>&1)"; RC=$?
}
has(){ printf '%s' "$OUT" | grep -q -- "$1"; }
lacks(){ ! printf '%s' "$OUT" | grep -q -- "$1"; }
xs(){ printf '%s\n' "$OUT" | grep -c '^✗'; }
dump(){ printf '%s\n' "$OUT" | sed 's/^/    /'; }
permits(){ find "$W/permits-$1" -type f 2>/dev/null | wc -l | tr -d ' '; }

# ── R1 없음: 기준판 = PASS(지금 통과) · 후판 = ✗ 1개(④-b 만) · BLOCK · 허가 0
mkworld r1
gate old r1old
n=$((n+1)); [ "$RC" = 0 ] && has 'PRESS-GATE PASS' && ok "$n. R1 기준판: env 없음인데 PASS(rc 0) — 지금의 구멍 재현" || { bad "$n. R1 기준판 세계가 통과하지 않음 (rc=$RC)"; dump; }
gate new r1
n=$((n+1)); [ "$RC" = 1 ] && has '✗ ④-b 화면 env NEXT_PUBLIC_BUBBLE_DEBUG=true 없음' && [ "$(xs)" = 1 ] && has 'PRESS-GATE BLOCK' && [ "$(permits r1)" = 0 ] \
  && ok "$n. R1 env 없음 → ✗ ④-b 1개뿐 · BLOCK · 허가 0" || { bad "$n. R1 (rc=$RC ✗=$(xs) permits=$(permits r1))"; dump; }

# ── R2 false · 빈 값 · 1 → ✗
for v in 'NEXT_PUBLIC_BUBBLE_DEBUG=false' 'NEXT_PUBLIC_BUBBLE_DEBUG=' 'NEXT_PUBLIC_BUBBLE_DEBUG=1'; do
  gate new r2 FAKE_FE_ENV="$v"
  n=$((n+1)); [ "$RC" = 1 ] && has '✗ ④-b 화면 env NEXT_PUBLIC_BUBBLE_DEBUG=true 없음' && [ "$(xs)" = 1 ] \
    && ok "$n. R2 «${v}» → ✗(true 만 통과)" || { bad "$n. R2 $v (rc=$RC)"; dump; }
done

# ── R3 true → ✓ · PASS · 나머지 줄은 기준판과 바이트 같음
gate old r3old FAKE_FE_ENV='NEXT_PUBLIC_BUBBLE_DEBUG=true'; OLD_OUT="$(printf '%s\n' "$OUT" | sed 's|r3old|TAG|g')"
gate new r3 FAKE_FE_ENV='NEXT_PUBLIC_BUBBLE_DEBUG=true'
n=$((n+1)); [ "$RC" = 0 ] && has '✓ ④-b 화면 env NEXT_PUBLIC_BUBBLE_DEBUG=true' && has 'PRESS-GATE PASS' && [ "$(permits r3)" -ge 1 ] \
  && ok "$n. R3 true → ✓ ④-b · PASS · 허가 발급" || { bad "$n. R3 (rc=$RC)"; dump; }
NEW_OUT="$(printf '%s\n' "$OUT" | grep -v '④-b' | sed 's|r3|TAG|g')"
n=$((n+1)); [ "$NEW_OUT" = "$OLD_OUT" ] && ok "$n. R3 ④-b 줄 말고 출력 바이트 = 기준판(다른 단계 판정 그대로)" \
  || { bad "$n. R3 바이트"; diff <(printf '%s\n' "$OLD_OUT") <(printf '%s\n' "$NEW_OUT") | sed 's/^/    /'; }

# ── R4 FE 리스너 없음 → ② ✗ + ④-b «판정 불가» ✗ · 허가 0
gate new r4 FAKE_FE_NONE=1
n=$((n+1)); [ "$RC" = 1 ] && has '✗ 화면 리스너 없음(:3001)' && has '✗ ④-b 화면 env 판정 불가 — FE 리스너(:3001) 부모 env 못 읽음' && [ "$(permits r4)" = 0 ] \
  && ok "$n. R4 FE 리스너 없음 → ② ✗ + ④-b 판정 불가 ✗ · 허가 0" || { bad "$n. R4 (rc=$RC)"; dump; }

# ── R5 dev 갈래 → ④-b 줄 0 · :3001 접촉 0 · 결과 기준판과 같음
gate old r5old FT_PRESS_TARGET=dev; ORC=$RC; OLD_OUT="$(printf '%s\n' "$OUT" | sed 's|r5old|TAG|g')"
gate new r5 FT_PRESS_TARGET=dev
n=$((n+1)); lacks '④-b' && ! grep -q ':3001' "$W/stub-r5.log" 2>/dev/null && [ "$RC" = "$ORC" ] && [ "$(printf '%s\n' "$OUT" | sed 's|r5|TAG|g')" = "$OLD_OUT" ] \
  && ok "$n. R5 dev 갈래 → ④-b 줄 0 · :3001 접촉 0 · 출력·rc($RC) 기준판과 같음" || { bad "$n. R5 (rc=$RC old=$ORC)"; dump; }

# ── 변이: ④-b 블록 삭제 → R1 이 PASS 로 바뀐다 ⇒ R1 의 rc 1·✗ 단언이 이 변이를 죽인다
python3 - "$GATE" "$T/mut.sh" <<'PY'
import sys, re
s = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'\n# ④-b 화면 env.*?\nfi\n', s, re.S)
assert m, "변이 원문 없음"
open(sys.argv[2], 'w', encoding='utf-8').write(s[:m.start()] + '\n' + s[m.end():])
PY
binof "$T/mut" "$T/mut.sh" && ok "변이 준비(④-b 블록 삭제)" || bad "변이 준비"
gate mut r1m
n=$((n+1)); [ "$RC" = 0 ] && lacks '④-b' && ok "$n. 변이 → env 없음인데 rc 0 · ④-b 0 ⇒ R1 단언이 FAIL(변이 사망)" || { bad "$n. 변이가 안 잡힘 (rc=$RC)"; dump; }

echo
[ "$fail" = 0 ] && { echo "ALL PASS ($n)"; exit 0; }
echo "FAILED $fail / $n"; exit 1
