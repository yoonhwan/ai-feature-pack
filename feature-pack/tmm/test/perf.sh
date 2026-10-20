#!/usr/bin/env bash
# tmm 갱신·탭 전환 성능·정합 시험 (0.8.1) — 임시 tmux 서버(TMUX_TMPDIR 격리)만. 실 서버·남의 세션·~/.tmm 0.
#   (a) 카테고리 결과가 수정 전과 바이트 동일 — 골든(test/golden/cat-N<세션수>.tsv = 0.8.0 출력) 대조
#   (b) 탭 전환(tabgo) 경로의 tmux 호출 0 — PATH 맨 앞 tmux 래퍼가 호출을 센다
#   (c) 자동 갱신은 공용 캐시를 지우지 않는다(auto_loop 가 fresh 를 안 쓴다) · 동시 2 인스턴스에서 seat-scan 1회
#   (d) 분류 칸 focus 3연타 → 마지막 카테고리만 반영(요청 번호 tabreq)
# 모든 시험을 돌고 실패를 모아 마지막에 rc 로 낸다(RED 시 어느 축이 빨간지 한 번에 보인다). 시각(ms)은 TIME 줄로 찍는다.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMM="${PERF_TMM:-$ROOT/core/bin/tmm}"   # PERF_TMM = 비교용 옛 사본(A/B 시각)
GOLD="$ROOT/test/golden"
REAL_TMUX="$(command -v tmux)"
SIZES="${PERF_SIZES:-30 120}"
FAILS=0
fail() { echo "FAIL: $*"; FAILS=$((FAILS+1)); }
ms() { python3 -c 'import time;print(int(time.time()*1000))'; }

SOCK_DIR="$(mktemp -d)"
H="$SOCK_DIR/home"; mkdir -p "$H/.local/bin" "$SOCK_DIR/tmm-$(id -u)"   # STATE 디렉터리(TMM_RUN 을 따로 주면 tmm 이 만들지 않는다)
CALLS="$SOCK_DIR/tmux.calls"
# tmux 래퍼 — HOME/.local/bin 은 tmm 이 PATH 맨 앞에 넣는 곳이다. TMUX_CALL_LOG 가 있을 때만 호출 한 줄씩 남긴다.
cat > "$H/.local/bin/tmux" <<EOF
#!/bin/sh
[ -n "\${TMUX_CALL_LOG:-}" ] && printf '%s\n' "\$*" >> "\$TMUX_CALL_LOG"
exec "$REAL_TMUX" "\$@"
EOF
chmod +x "$H/.local/bin/tmux"
# seat-scan 대역 — 호출 때마다 SCAN_COUNT 에 한 줄, SCAN_SLEEP 초 뒤 전 세션 IDLE
cat > "$SOCK_DIR/scan-stub.sh" <<'EOF'
#!/bin/bash
[ -n "${SCAN_COUNT:-}" ] && echo x >> "$SCAN_COUNT"
[ -n "${SCAN_SLEEP:-}" ] && sleep "$SCAN_SLEEP"
tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r s; do printf '%s IDLE x\n' "$s"; done
EOF
# fzf --listen 소켓 대역 — POST 본문을 파일에 한 줄씩 쌓는다
cat > "$SOCK_DIR/fakefzf.py" <<'EOF'
import os, socketserver, sys
sock, out = sys.argv[1], sys.argv[2]
class H(socketserver.BaseRequestHandler):
    def handle(self):
        data = b''
        while b'\r\n\r\n' not in data:
            c = self.request.recv(4096)
            if not c: break
            data += c
        head, _, body = data.partition(b'\r\n\r\n')
        cl = 0
        for l in head.split(b'\r\n'):
            if l.lower().startswith(b'content-length:'): cl = int(l.split(b':')[1])
        while len(body) < cl: body += self.request.recv(4096)
        with open(out, 'ab') as f: f.write(body + b'\n')
        self.request.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
if os.path.exists(sock): os.unlink(sock)
socketserver.UnixStreamServer(sock, H).serve_forever()
EOF

tm()  { env -u TMUX TMUX_TMPDIR="$SOCK_DIR" "$REAL_TMUX" "$@"; }
RUNDIR=""
SCANBIN="$SOCK_DIR/scan-stub.sh"; [ "${PERF_REAL_SCAN:-0}" = 1 ] && SCANBIN="$ROOT/core/libexec/seat-scan.sh"
tmmenv() {  # 격리 환경으로 임의 명령을 돌린다(tmm 본체·bash -c 에서 tmm 을 source 하는 시험 공용)
  env -u TMUX -u TMM_RUN HOME="$H" TMUX_TMPDIR="$SOCK_DIR" TMPDIR="$SOCK_DIR" TMM_SCAN="$SCANBIN" TMM_CACHE_TTL="${TTL:-20}" \
      TMM_CATEGORIES=/dev/null TMM_BELL=0 ${RUNDIR:+TMM_RUN=$RUNDIR} "$@"
}
tmm() { tmmenv "$TMM" "$@"; }
FAKE_PID=""
cleanup() {
  [ -n "$FAKE_PID" ] && kill "$FAKE_PID" 2>/dev/null
  tm kill-server 2>/dev/null || true
  rm -rf "$SOCK_DIR"
}
trap cleanup EXIT

# N 개 세션 — 고정 10개(팀·충돌 팀·구 접두·일반) + 나머지는 팀/일반 이름을 번갈아. 이름이 결정적이라 골든이 안정이다.
make_sessions() {  # <N>
  local n="$1" i name
  tm kill-server 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do tm list-sessions >/dev/null 2>&1 || break; sleep 0.25; done   # 서버가 완전히 내려간 뒤에 새로 연다(부하 시 새 서버와 겹쳐 «server exited unexpectedly»)
  local -a names=('byz-v65-master-claude#1' 'byz-v65-arch-claude#2' 'kk-v65-nano-codex' 'ft-v65-temp-1' 'byz-cfo-master-claude#3'
                  'byz-cfo-nano-x' 'FB_CCU#0' 'CCU_ARCH#3' 'plain-shell' 'loom_a#1')
  for ((i=${#names[@]}; i<n; i++)); do
    if [ $((i % 2)) = 0 ]; then names+=("byz-t$((i % 7))-nano-claude#$i"); else names+=("zz$((i % 5))_work#$i"); fi
  done
  for name in "${names[@]:0:$n}"; do tm new-session -d -s "$name" -x 80 -y 24 'sleep 3000'; done
  [ "$(tm list-sessions | wc -l | tr -d ' ')" = "$n" ] || fail "세션 $n 개를 못 만듦"
}

for N in $SIZES; do
  echo "== N=$N =="
  make_sessions "$N"
  RUNDIR="$SOCK_DIR/run-$N"; mkdir -p "$RUNDIR"; rm -f "$SOCK_DIR"/tmm-scan-*.cache "$SOCK_DIR"/tmm-*/ep.cache 2>/dev/null

  # (a) 카테고리 결과 = 골든(0.9.0 — 3열이 «프로젝트/팀»으로 바뀐 의도된 갱신, 세션 집합은 0.8.0 과 동일). 첫 호출은 스캔·좌석별 캐시를 채우고, 둘째가 «캐시 적중» 시각이다.
  tmm rows time > /dev/null
  t0=$(ms); got="$(tmm rows time | cut -f2,3 | sort)"; t1=$(ms)
  echo "TIME N=$N rows(캐시 적중) $((t1-t0)) ms"
  if [ -n "${PERF_WRITE_GOLDEN:-}" ]; then mkdir -p "$GOLD"; printf '%s\n' "$got" > "$GOLD/cat-N$N.tsv"; fi
  if [ -f "$GOLD/cat-N$N.tsv" ]; then
    [ "$got" = "$(cat "$GOLD/cat-N$N.tsv")" ] || { fail "(a) N=$N 카테고리 표가 골든과 다름"; diff <(printf '%s\n' "$got") "$GOLD/cat-N$N.tsv" | head -10; }
  else fail "(a) 골든 없음: $GOLD/cat-N$N.tsv"; fi

  # (b) 탭 전환 — tmux 호출 0
  : > "$RUNDIR/tab"; tmm mode time; tmm rows-cur > /dev/null
  cats=(); while IFS=$'\t' read -r c _; do cats+=("$c"); done < "$RUNDIR/tabs"
  [ "${#cats[@]}" -ge 5 ] || { fail "(b) N=$N 탭이 5개 미만(${#cats[@]}) — 이후 시험 건너뜀"; continue; }
  here="$(tmm rows-cur | cut -f2 | sed -n 1p)"
  : > "$CALLS"; t0=$(ms)
  go="$(TMUX_CALL_LOG="$CALLS" tmm tabgo "${cats[1]}" "$here")"
  t1=$(ms); echo "TIME N=$N tabgo(탭 전환 1회) $((t1-t0)) ms"
  printf '%s\n' "$go" | grep -q '^reload(cat ' || fail "(b) N=$N tabgo 출력이 reload(cat …) 아님: $go"
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 0 ] || { fail "(b) N=$N 탭 전환에 tmux 호출 $(wc -l < "$CALLS" | tr -d ' ')회: $(head -3 "$CALLS" | tr '\n' '|')"; }
  [ "$(cat "$RUNDIR/tabsel")" = "${cats[1]}" ] || fail "(b) N=$N tabgo 뒤 tabsel≠${cats[1]}"
  # 전환 뒤 목록 = 그 카테고리만(골든의 같은 카테고리 세션 집합과 일치)
  want="$(awk -F'\t' -v c="${cats[1]}" '$2==c || index($2, c "/")==1{print $1}' "$GOLD/cat-N$N.tsv" 2>/dev/null | sort)"
  have="$(cut -f2 "$RUNDIR/tabrows" | sort)"
  [ "$want" = "$have" ] || fail "(b) N=$N tabrows 의 세션 집합이 카테고리 ${cats[1]} 와 다름"

  # (c) 자동 갱신 — fresh 를 안 쓴다 · 캐시를 안 지운다 · 동시 2 인스턴스 스캔 1회
  # 소켓 파일이 생긴 것만으로는 부족하다(부하 시 listen 전에 연결이 거절돼 요청이 사라짐 — /bin/bash 하네스에서 'ignore reload' 로 한 번 실패) → 실제로 POST 가 닿을 때까지 탐침한다
  fake_start() {
    python3 "$SOCK_DIR/fakefzf.py" "$1" "$2" & FAKE_PID=$!
    for _ in $(seq 1 50); do curl -s -o /dev/null --unix-socket "$1" -X POST http://localhost/ -d probe 2>/dev/null && break; sleep 0.1; done
    : > "$2"
  }
  fake_stop()  { kill "$FAKE_PID" 2>/dev/null; wait "$FAKE_PID" 2>/dev/null; FAKE_PID=""; }
  POSTS="$SOCK_DIR/posts-$N"; : > "$POSTS"
  fake_start "$RUNDIR/fzf.sock" "$POSTS"
  ( export TMM_AUTO=1 TMM_AUTO_PREVIEW=0 TMM_RUN="$RUNDIR" TMPDIR="$SOCK_DIR" HOME="$H" TMUX_TMPDIR="$SOCK_DIR"
    exec bash -c 'source "$1" __lib; auto_loop "$2"' _ "$TMM" "$RUNDIR/fzf.sock" ) &
  AL=$!; sleep 3.5; kill "$AL" 2>/dev/null; wait "$AL" 2>/dev/null; fake_stop
  grep -q '^reload(' "$POSTS" || fail "(c) N=$N 자동 갱신 reload 가 한 번도 안 옴(시험 장치 점검)"
  grep '^reload(' "$POSTS" | grep -q 'rows-cur fresh' && fail "(c) N=$N 자동 갱신이 fresh 로 공용 캐시를 지움: $(grep '^reload(' "$POSTS" | head -1)"

  cache="$(ls "$SOCK_DIR"/tmm-scan-*.cache 2>/dev/null | head -1)"
  [ -n "$cache" ] || fail "(c) N=$N 캐시 파일이 없음"
  # c2: 캐시가 «신선»하면 재스캔 0 · 캐시 파일 그대로
  CNT="$SOCK_DIR/scan-count"; : > "$CNT"; touch "$cache"; m0="$(stat -f %m "$cache")"
  SCAN_COUNT="$CNT" tmm rows-cur > /dev/null
  [ "$(wc -l < "$CNT" | tr -d ' ')" = 0 ] || fail "(c) N=$N 신선한 캐시인데 재스캔함"
  # c3: 캐시가 낡았을 때 두 인스턴스가 동시에 갱신 → seat-scan 1회, 캐시는 남는다
  touch -t 200001010000 "$cache"; : > "$CNT"
  R1="$SOCK_DIR/run-$N-a"; R2="$SOCK_DIR/run-$N-b"; mkdir -p "$R1" "$R2"
  ( RUNDIR="$R1" SCAN_COUNT="$CNT" SCAN_SLEEP=1 tmm rows-cur > /dev/null ) &
  ( RUNDIR="$R2" SCAN_COUNT="$CNT" SCAN_SLEEP=1 tmm rows-cur > /dev/null ) &
  wait
  [ "$(wc -l < "$CNT" | tr -d ' ')" = 1 ] || fail "(c) N=$N 동시 2 인스턴스 갱신에 seat-scan $(wc -l < "$CNT" | tr -d ' ')회(기대 1)"
  [ -s "$cache" ] || fail "(c) N=$N 갱신 뒤 캐시가 비었거나 없음"

  # (d) focus 3연타 — 분류 칸이 쏜 요청을 순서대로 목록 fzf 가 처리해도 마지막 카테고리만 남는다
  tmm rows-cur > /dev/null     # 현재 탭을 최신 목록·탭 수로
  printf '%s\n' "${cats[0]}" > "$RUNDIR/tabsel"; tmm rows-cur > /dev/null
  rm -f "$RUNDIR/tabreq" "$RUNDIR/tabcur"; : > "$POSTS"
  fake_start "$RUNDIR/fzf.sock" "$POSTS"
  for c in "${cats[1]}" "${cats[2]}" "${cats[3]}"; do tmm catfocus "$c"; done
  fake_stop
  replay() {  # POSTS 의 tabgo 요청을 순서대로 목록 fzf 처럼 실행 → 각 출력(첫 단어)을 한 줄씩
    local line cat req
    while IFS= read -r line; do
      case "$line" in *" tabgo "*) ;; *) continue;; esac
      cat="$(printf '%s' "$line" | sed -n "s/.* tabgo '\\([^']*\\)' .*/\\1/p")"
      req="$(printf '%s' "$line" | sed -n "s/.*{2} '\\([^']*\\)')\$/\\1/p")"
      tmm tabgo "$cat" "$here" "$req" | cut -c1-6
    done < "$POSTS"
  }
  out="$(replay | tr '\n' ' ')"
  [ "$out" = "ignore ignore reload " ] || fail "(d) N=$N 3연타 재생 결과가 'ignore ignore reload' 아님: '$out'"
  [ "$(cat "$RUNDIR/tabsel")" = "${cats[3]}" ] || fail "(d) N=$N 3연타 뒤 탭=${cats[3]} 이어야 함(실제 $(cat "$RUNDIR/tabsel"))"
  # d2: B 로 갔다가 «원래 탭»으로 돌아오는 연타 — 앞선 B 요청은 버려지고 탭은 그대로
  printf '%s\n' "${cats[0]}" > "$RUNDIR/tabsel"; tmm rows-cur > /dev/null; rm -f "$RUNDIR/tabreq"; : > "$POSTS"
  fake_start "$RUNDIR/fzf.sock" "$POSTS"
  tmm catfocus "${cats[1]}"; tmm catfocus "${cats[0]}"
  fake_stop
  replay > /dev/null
  [ "$(cat "$RUNDIR/tabsel")" = "${cats[0]}" ] || fail "(d) N=$N 떠났다 돌아온 연타 뒤 탭이 ${cats[0]} 이어야 함(실제 $(cat "$RUNDIR/tabsel"))"

  # d3: 검사를 «통과한» 낡은 요청이 탭을 적용하려는 사이(tabsel 쓰기 전)에 «원래 탭으로 돌아온» focus 가 끼어드는 결정적 스케줄 — DA⑥ H1.
  #   b 요청이 tabreq 검사를 통과한 직후 tab_switch_to 안(tabcur_set 호출 시점)에서 catfocus(a) 를 실행한다. 이때 현재 탭은 아직 a 라 «같은 탭이라 안 쏘는» 구현이면
  #   낡은 b 가 tabsel=b 를 남긴다. 최신 focus(a) 의 요청까지 순서대로 처리하고 나면 탭은 a 여야 한다.
  printf '%s\n' "${cats[0]}" > "$RUNDIR/tabsel"; tmm rows-cur > /dev/null; rm -f "$RUNDIR/tabreq" "$RUNDIR/tabcur"; : > "$POSTS"
  fake_start "$RUNDIR/fzf.sock" "$POSTS"
  tmmenv env CAT_A="${cats[0]}" CAT_B="${cats[1]}" bash -c 'source "$1" __lib
    eval "orig_$(declare -f tabcur_set)"
    tabcur_set() { cmd_catfocus "$CAT_A"; orig_tabcur_set "$@"; }
    cmd_catfocus "$CAT_B"
    cmd_tabgo "$CAT_B" "" "$(cat "$RUN/tabreq")" > /dev/null' _ "$TMM" 2>/dev/null || true
  fake_stop
  replay > /dev/null
  [ "$(cat "$RUNDIR/tabsel")" = "${cats[0]}" ] || fail "(d) N=$N 검사 통과 뒤 원래 탭으로 돌아온 focus 가 끼면 탭이 ${cats[0]} 이어야 함(실제 $(cat "$RUNDIR/tabsel"))"
done

if [ "$FAILS" -gt 0 ]; then echo "❌ tmm perf: 실패 ${FAILS}건"; exit 1; fi
echo "✅ tmm perf OK"
