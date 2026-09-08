#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMM="$ROOT/core/bin/tmm"
SCAN="$ROOT/core/libexec/seat-scan.sh"

# (a) --help 는 exit 0 이고 출력에 tmm 이 있어야 한다
help_out="$("$TMM" --help)"
printf '%s\n' "$help_out" | grep -q 'tmm' || { echo 'FAIL: --help 출력에 tmm 없음'; exit 1; }

# (b) 문법 검사 (4개 스크립트)
bash -n "$TMM" "$SCAN" "$ROOT/install.sh" "$ROOT/uninstall.sh"

# ---------- 격리 tmux 서버 (기본 소켓 절대 미접촉) ----------
# tmm 은 tmux 를 PATH 에서 부르므로 격리는 TMUX_TMPDIR 환경변수로만 한다.
# tmm 안에서 부르는 tmux 도 같은 env 를 상속해야 하니 매 호출을 env 로 감싼다.
SOCK_DIR="$(mktemp -d)"
tm()  { env -u TMUX TMUX_TMPDIR="$SOCK_DIR" tmux "$@"; }
# TMPDIR 도 격리 — tmm 의 상태 파일(mode/auto/waitset/bell)과 캐시가 실사용본과 섞이지 않게
tmm() { env -u TMUX TMUX_TMPDIR="$SOCK_DIR" TMPDIR="$SOCK_DIR" TMM_SCAN="${TMM_SCAN_OVERRIDE:-$SCAN}" TMM_CACHE_TTL=0 TMM_CATEGORIES=/dev/null "$TMM" "$@"; }
STATE="$SOCK_DIR/tmm-$(id -u)"
cleanup() {
  env -u TMUX TMUX_TMPDIR="$SOCK_DIR" tmux kill-server 2>/dev/null || true
  rm -rf "$SOCK_DIR"
}
trap cleanup EXIT

tm new-session -d -s TMM_VERIFY_A -x 80 -y 24
# 셸 프롬프트가 자리잡을 시간
sleep 0.5

# (c) rows 출력에 TMM_VERIFY_A + 필드 3개(탭 구분)
rows_out="$(tmm rows time)"
printf '%s\n' "$rows_out" | grep -q 'TMM_VERIFY_A' || {
  echo 'FAIL: rows 출력에 TMM_VERIFY_A 없음'; printf '%s\n' "$rows_out"; exit 1; }
printf '%s\n' "$rows_out" | awk -F'\t' '/TMM_VERIFY_A/ && NF==3' | grep -q . || {
  echo 'FAIL: TMM_VERIFY_A 행이 탭 3필드가 아님'
  printf '%s\n' "$rows_out" | awk -F'\t' '/TMM_VERIFY_A/{print "NF="NF}'; exit 1; }

# (d) ls VERIFY 는 한 줄 매치
ls_out="$(tmm ls VERIFY)"
[ "$(printf '%s\n' "$ls_out" | grep -c 'TMM_VERIFY_A')" -eq 1 ] || {
  echo 'FAIL: ls VERIFY 매치가 1줄이 아님'; printf '%s\n' "$ls_out"; exit 1; }

# (e) s TMM_VERIFY_A ping — 셸-only 좌석이라 차단(exit 1) + "차단" 문구,
#     그리고 pane 에 ping 이 타이핑되지 않아야 한다.
set +e
send_out="$(tmm s TMM_VERIFY_A ping 2>&1)"; send_rc=$?
set -e
[ "$send_rc" -eq 1 ] || { echo "FAIL: send 가 exit 1 이 아님 (rc=$send_rc)"; printf '%s\n' "$send_out"; exit 1; }
printf '%s\n' "$send_out" | grep -q '차단' || { echo 'FAIL: send 출력에 "차단" 문구 없음'; printf '%s\n' "$send_out"; exit 1; }
pane="$(tm capture-pane -t '=TMM_VERIFY_A:' -p)"
printf '%s\n' "$pane" | grep -q 'ping' && {
  echo 'FAIL: 차단됐는데 pane 에 ping 이 타이핑됨'; printf '%s\n' "$pane"; exit 1; }

# (f) 정렬 모드는 상태 파일에 남고 rows-cur 가 그것을 따른다 (^R·자동 갱신이 모드를 잃지 않게)
tmm mode wait h
[ "$(cat "$STATE/mode")" = "wait h" ] || { echo "FAIL: mode 파일이 'wait h' 가 아님: $(cat "$STATE/mode" 2>&1)"; exit 1; }
tmm rows-cur | grep -q 'TMM_VERIFY_A' && { echo 'FAIL: 대기만(h) 모드인데 IDLE 좌석이 rows-cur 에 나옴'; exit 1; }
tmm mode time
tmm rows-cur | grep -q 'TMM_VERIFY_A' || { echo 'FAIL: time 모드 rows-cur 에 TMM_VERIFY_A 없음'; exit 1; }

# (g) ^U 프리셋 순환: 30 → 60 → off(0) → 15, 헤더에 현재값 표시
rm -f "$STATE/auto"
[ "$(TMM_AUTO=30 tmm auto-cycle)" = 60 ] || { echo "FAIL: auto-cycle 30→60 아님"; exit 1; }
[ "$(tmm auto-cycle)" = 0 ]  || { echo "FAIL: auto-cycle 60→0 아님"; exit 1; }
tmm header | grep -q 'auto:off' || { echo "FAIL: auto=0 인데 헤더에 auto:off 없음"; tmm header; exit 1; }
[ "$(tmm auto-cycle)" = 15 ] || { echo "FAIL: auto-cycle 0→15 아님"; exit 1; }
tmm header | grep -q 'auto:15s' || { echo "FAIL: auto=15 인데 헤더에 auto:15s 없음"; tmm header; exit 1; }

# (j) 헤더는 폰 60열에서 잘리지 않아야 한다 — fzf 는 헤더를 줄바꿈 없이 자르므로 각 줄 표시폭(동아시아 W/F=2) ≤ 60
for a in 0 30; do
  printf '%s\n' "$a" > "$STATE/auto"
  tmm header | python3 -c '
import sys, unicodedata
bad = [(len_, l) for l in sys.stdin.read().splitlines()
       for len_ in [sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l)] if len_ > 60]
for w, l in bad: print(f"FAIL: 헤더 {w}열 > 60: {l}")
sys.exit(1 if bad else 0)' || exit 1
done

# (h) 벨 플래그: 직전 스캔 대비 «새로» HUMAN/BLOCK/STUCK 이 된 좌석이 있을 때만 bell 파일 생성
printf '#!/usr/bin/env bash\necho "TMM_VERIFY_A IDLE"\n'  > "$SOCK_DIR/scan-idle.sh"
printf '#!/usr/bin/env bash\necho "TMM_VERIFY_A HUMAN"\n' > "$SOCK_DIR/scan-human.sh"
rm -f "$STATE/waitset" "$STATE/bell"
TMM_SCAN_OVERRIDE="$SOCK_DIR/scan-human.sh" tmm rows time >/dev/null
[ -f "$STATE/bell" ] && { echo 'FAIL: 첫 스캔(비교 대상 없음)인데 bell 생성됨'; exit 1; }
TMM_SCAN_OVERRIDE="$SOCK_DIR/scan-idle.sh" tmm rows time >/dev/null
[ -f "$STATE/bell" ] && { echo 'FAIL: HUMAN→IDLE 인데 bell 생성됨'; exit 1; }
TMM_SCAN_OVERRIDE="$SOCK_DIR/scan-human.sh" tmm rows time >/dev/null
[ -f "$STATE/bell" ] || { echo 'FAIL: IDLE→HUMAN 인데 bell 없음'; exit 1; }

# (i) 소켓 post: 격리 세션 안의 fzf --listen 에 액션을 쏘면 화면이 바뀐다 (핑거가 쓰는 경로)
tm send-keys -t '=TMM_VERIFY_A:' -l "fzf --listen=$SOCK_DIR/t.sock --prompt='P> ' </dev/null"
tm send-keys -t '=TMM_VERIFY_A:' Enter
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$SOCK_DIR/t.sock" ] && break; sleep 0.3; done
[ -S "$SOCK_DIR/t.sock" ] || { echo 'FAIL: fzf --listen 소켓이 안 생김'; exit 1; }
tmm __post "$SOCK_DIR/t.sock" 'change-prompt(ZZ> )'
sleep 0.5
tm capture-pane -t '=TMM_VERIFY_A:' -p | grep -q 'ZZ>' || { echo 'FAIL: post 한 change-prompt 가 화면에 반영 안 됨'; tm capture-pane -t '=TMM_VERIFY_A:' -p; exit 1; }
tm send-keys -t '=TMM_VERIFY_A:' Escape

echo "✅ tmm verify OK"
