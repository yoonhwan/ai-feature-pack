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
tmm() { env -u TMUX TMUX_TMPDIR="$SOCK_DIR" TMM_SCAN="$SCAN" TMM_CACHE_TTL=0 TMM_CATEGORIES=/dev/null "$TMM" "$@"; }
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

echo "✅ tmm verify OK"
