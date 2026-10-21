#!/usr/bin/env bash
# test_spawn_proxy_probe_r669.sh — r669: 나노 spawn 의 추론 프록시 사전 확인이 시도당 3초라 부하 때 첫 응답 7.0초인 프록시를 «두 번 다 실패» 로 오판 → 거짓 REJECT(v65 3회)
#   ⓐ 5초 지연 프록시: 옛 판(-m 3 ×2) = REJECT / 새 판(상한 7초) = rc0 · 첫 시도에 성공(재시도 0)
#   ⓑ 시도당 상한 = FT_PROXY_PROBE_MAX(기본 7) · 7 초과 주입 = 7 로 제한 + WARN · 3 주입 = 옛 값 그대로 실패(숫자가 실제로 문턱이라는 증거)
#   ⓒ HTTP 응답이 왔는데 비정상(500) = 재시도 0 즉시 실패(«첫 바이트 전 실패» 만 재시도)
#   ⓓ 총 마감 = 7 + 2 + 7 = 16초 이하(실제 경과 단언 · 하드 룰 12)
#   ⓔ 둘 다 실패 = 진짜 장애 → ft-nano-spawn 이 exit 1 대신 순번 큐(exit 7 · 큐 1줄 · 사유 proxy · 좌석 0)
# 실 tmux·실 명부·실 좌석·실 프록시 호출 0 — 가짜 프록시(임시 포트 python) · 가짜 route status · 가짜 자원 센서 · 임시 리포.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
KIT="$REPO/feature-pack/fable-team/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; PIDS=()
trap 'for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
RDY="$KIT/ft-agent-ready.sh"

# 가짜 프록시 — 요청 1건당 delay 초 뒤 응답(단일 스레드 = 큐 적체가 그대로 재현된다) · code=500 이면 즉시 비정상 응답
cat > "$T/proxy.py" <<'PY'
import socket, sys, time
port = int(sys.argv[1]); delay = float(sys.argv[2]); code = int(sys.argv[3])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(16)
while True:
    c, _ = s.accept()
    try:
        c.recv(65536)
        if delay:
            time.sleep(delay)
        line = b"200 OK" if code == 200 else b"500 Internal Server Error"
        c.sendall(b"HTTP/1.1 " + line + b"\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
    except Exception:
        pass
    finally:
        c.close()
PY
freeport() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
start_proxy() { # <delay> <code> → $PURL
  local p; p="$(freeport)"
  python3 "$T/proxy.py" "$p" "$1" "$2" & PIDS+=("$!"); sleep 0.4
  PURL="http://127.0.0.1:$p/v1/models"
}
ROUTE='printf "  headroom : off\n  cliproxy : on\n"'
probe() { # <url> [env...] → stdout · PROBE_RC · PROBE_SECS
  local u="$1"; shift
  local s=$SECONDS
  PROBE_OUT="$(env FT_ROUTE_STATUS_CMD="$ROUTE" FT_PROXY_PROBE_URL="$u" "$@" bash "$RDY" --proxy "$T" --agent claude 2>"$T/err")"; PROBE_RC=$?
  PROBE_SECS=$((SECONDS - s)); PROBE_ERR="$(cat "$T/err")"
}
retries() { printf '%s\n' "${PROBE_ERR:-}" | grep -c '^INFO 프록시 확인 시도' ; }

echo "== ⓐ 5초 지연 프록시 — 옛 판은 두 번 다 실패(3초 상한) 했다"
start_proxy 5 200
probe "$PURL"
[ "$PROBE_RC" -eq 0 ] && ok "ⓐ 첫 응답 5초 프록시 → rc0 (옛 판: REJECT 프록시 2회 실패)" || bad "ⓐ rc=$PROBE_RC ← $PROBE_OUT $PROBE_ERR"
[ "$(retries)" -eq 0 ] && ok "ⓐ 첫 시도에서 성공 — 재시도 0" || bad "ⓐ 재시도 $(retries)회"
[ "$PROBE_SECS" -le 16 ] && ok "ⓐ 경과 ≤ 16 s ($PROBE_SECS s)" || bad "ⓐ 경과 $PROBE_SECS s"
[ -s "$T/err" ] && bad "ⓐ 정상 경로가 stderr 에 줄을 남김: $(head -1 "$T/err")" || ok "ⓐ 정상 경로 = stderr 0줄"

echo "== ⓑ 시도당 상한 = FT_PROXY_PROBE_MAX (기본 7 · 7 초과 = 7 로 제한 · WARN)"
probe "$PURL" FT_PROXY_PROBE_MAX=99
[ "$PROBE_RC" -eq 0 ] && ok "ⓑ 상한 99 주입 → 7 로 제한돼 rc0" || bad "ⓑ rc=$PROBE_RC ← $PROBE_OUT $PROBE_ERR"
case "$PROBE_ERR" in *"7 로 제한"*) ok "ⓑ 7 초과 주입 = WARN «7 로 제한»";; *) bad "ⓑ WARN 없음 ← $PROBE_ERR";; esac
probe "$PURL" FT_PROXY_PROBE_MAX=3
{ [ "$PROBE_RC" -ne 0 ] && has "$PROBE_OUT" "REJECT 프록시" "ⓑ 상한 3(옛 값) → 같은 프록시가 REJECT = 숫자가 실제 문턱"; } || true
[ "$PROBE_SECS" -le 9 ] && ok "ⓑ 상한 3 경과 ≤ 9 s ($PROBE_SECS s — 3+2+3)" || bad "ⓑ 경과 $PROBE_SECS s"

echo "== ⓒ HTTP 응답이 왔는데 비정상(500) = 재시도 0 즉시 실패"
start_proxy 0 500
probe "$PURL"
{ [ "$PROBE_RC" -ne 0 ] && has "$PROBE_OUT" "HTTP 응답 비정상" "ⓒ 500 → 즉시 실패(재시도 0)"; } || true
[ "$(retries)" -eq 0 ] && ok "ⓒ 재시도 줄 0 (첫 바이트 전 실패만 재시도)" || bad "ⓒ 재시도 $(retries)회"
[ "$PROBE_SECS" -le 2 ] && ok "ⓒ 경과 ≤ 2 s ($PROBE_SECS s — 사이 대기 2초도 안 씀)" || bad "ⓒ 경과 $PROBE_SECS s"

echo "== ⓓ 총 마감 = 7 + 2 + 7 = 16초 이하 (응답 없는 프록시 · 첫 바이트 전 실패 2회)"
start_proxy 60 200
probe "$PURL"
{ [ "$PROBE_RC" -ne 0 ] && has "$PROBE_OUT" "REJECT 프록시" "ⓓ 2회 실패 → REJECT 프록시"; } || true
[ "$(retries)" -eq 2 ] && ok "ⓓ 실패 시도 2회" || bad "ⓓ 시도 줄 $(retries)"
{ [ "$PROBE_SECS" -ge 14 ] && [ "$PROBE_SECS" -le 17 ]; } && ok "ⓓ 경과 14~17 s ($PROBE_SECS s = 7+2+7)" || bad "ⓓ 경과 $PROBE_SECS s"

echo "== ⓔ 둘 다 실패 = 진짜 장애 → spawn exit 7 · 순번 큐 1줄(사유 proxy) · 좌석 0"
B="$T/bin"; mkdir -p "$B"
cp "$KIT/ft-nano-spawn.sh" "$KIT/ft-agent-ready.sh" "$KIT/ft_spawn_queue.py" "$KIT/ft_teamset.py" "$B/"
printf '#!/bin/bash\nexit 0\n' > "$B/ft-index-lint.sh"                       # 카드 lint = 이 카드 소관 아님
printf '#!/bin/bash\necho "INFO 제안서 승인 확인 OK"\n' > "$B/ft-proposal-gate.sh"
printf '#!/bin/bash\nexit 0\n' > "$B/ft-resource-gate.sh"                    # 자원 문지기 = 가짜 센서 대신 통과(이 카드 소관 아님)
printf '#!/bin/bash\nexit 0\n' > "$B/ft-all-stop.sh"
printf '#!/bin/bash\necho "SENT stub"\n' > "$B/ft-send-verified.sh"
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n' > "$B/ft_raised.py"   # 상향 모델 아님
cat > "$B/ft-team-lib.sh" <<'SH'
ft_team_has_ref() { return 1; }
ft_card_location_ok() { return 0; }
ft_index_twin() { return 1; }
SH
chmod 755 "$B"/*
mkdir -p "$T/repo/.fable-team/state" "$T/repo/.fable-team/comm" "$T/repo/design/harness/indices/대기"
env -u GIT_DIR -u GIT_WORK_TREE git init -q "$T/repo"
git -C "$T/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
printf '{"_parent":null}\n' > "$T/repo/.fable-team/seats.json"
printf '{"_parent":null}\n' > "$T/repo/.fable-team/seats-harness.json"   # 순번 큐가 그 팀 명부를 읽는다
printf '2026-10-22T00:00:00\toff\tinstall\tinit\n' > "$T/repo/.fable-team/state/all-stop.log"
printf '#!/bin/sh\necho "SENT stub"\n' > "$T/repo/.fable-team/comm/mbox.sh"; chmod 755 "$T/repo/.fable-team/comm/mbox.sh"
CARD="$T/repo/design/harness/indices/대기/x.md"; echo '# 카드' > "$CARD"
Q="$T/repo/.fable-team/state/spawn-queue-harness.tsv"
spawn() { ( cd "$T/repo" && FT_SEATS_JSON="$T/repo/.fable-team/seats.json" FT_NANO_PREFIX=byz-harness-nano- \
  FT_TEAMSET=0 FT_ROUTE_STATUS_CMD="$ROUTE" FT_PROXY_PROBE_URL="$1" \
  env -u FT_PROXY_PROBE_MAX bash "$B/ft-nano-spawn.sh" "$CARD" --from dispatch 2>&1 ); }
S=$SECONDS; o="$(spawn "$PURL")"; rc=$?; el=$((SECONDS - S))
{ [ "$rc" = 7 ] && ok "ⓔ 진짜 장애 → exit 7 (옛 판: exit 1 · 큐 0)"; } || bad "ⓔ exit=$rc (옛 판 1) ← $(printf '%s' "$o" | tail -2 | tr '\n' '|')"
has "$o" "QUEUED" "ⓔ 순번 큐에 남는다(QUEUED)"
has "$o" "사유 proxy" "ⓔ 출력에 사유 proxy 1줄"
[ -f "$Q" ] && [ "$(grep -c . "$Q")" = 1 ] && grep -q 'x.md' "$Q" && ok "ⓔ 큐 파일 1줄(카드 경로): $(cut -f1 "$Q")" || bad "ⓔ 큐 파일=$(cat "$Q" 2>/dev/null)"
[ "$(git -C "$T/repo" worktree list | grep -c .)" = 1 ] && ok "ⓔ 워크트리 0 (프록시 확인은 부작용 전 지점)" || bad "ⓔ 워크트리 생김"
[ "$el" -le 20 ] && ok "ⓔ 경과 ≤ 20 s ($el s)" || bad "ⓔ 경과 $el s"

echo "== ⓕ 키트↔추적 짝 (설치 cmp0 의 근거)"
BIN="$REPO/feature-pack/fable-team/harness/bin"
for s in ft-agent-ready.sh ft-nano-spawn.sh; do cmp -s "$KIT/$s" "$BIN/$s" && ok "cmp0 $s" || bad "짝 불일치 $s"; done

echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED ($fail)"; exit "$fail"
