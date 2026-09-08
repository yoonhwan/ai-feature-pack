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

# (g) ^U 는 «미리보기» 주기만 순환: 5 → 10 → 15 → 5 (off 없음). 전좌석 주기는 20 고정, 헤더에 둘 다 표시
rm -f "$STATE/auto"
tmm header | grep -q 'pane:5s all:20s' || { echo "FAIL: 기본 헤더가 pane:5s all:20s 아님"; tmm header; exit 1; }
[ "$(tmm auto-cycle)" = 10 ] || { echo "FAIL: auto-cycle 5→10 아님"; exit 1; }
[ "$(tmm auto-cycle)" = 15 ] || { echo "FAIL: auto-cycle 10→15 아님"; exit 1; }
[ "$(tmm auto-cycle)" = 5 ]  || { echo "FAIL: auto-cycle 15→5 아님 (off 가 끼어들었나)"; exit 1; }
tmm header | grep -q 'pane:5s' || { echo "FAIL: 순환 후 헤더에 pane:5s 없음"; tmm header; exit 1; }
[ "$(TMM_AUTO=30 tmm header | grep -o 'all:[0-9]*s')" = 'all:30s' ] || { echo "FAIL: TMM_AUTO 가 all: 에 반영 안 됨"; exit 1; }
rm -f "$STATE/auto"   # 상태 파일이 env 보다 우선 — TUI 진입 시 env 로 다시 쓰므로 여기선 지우고 잰다
[ "$(TMM_AUTO_PREVIEW=0 tmm header | grep -o 'pane:[a-z0-9]*')" = 'pane:off' ] || { echo "FAIL: TMM_AUTO_PREVIEW=0 인데 pane:off 아님"; exit 1; }

# (j) 헤더는 폰 60열에서 잘리지 않아야 한다 — fzf 는 헤더를 줄바꿈 없이 자르므로 각 줄 표시폭(동아시아 W/F=2) ≤ 60
for a in 0 15; do
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

# (k) 미리보기 렌더러 골든 — Claude 입력박스(구분선+❯)·statusline 제거, Codex 프롬프트 제거, 본문 표 구분선 보존, 색 유지, 연속 빈줄 1줄
SEP="$(printf '─%.0s' $(seq 1 60))"
render_in="$(printf '%b\n' \
  '⏺ 첫 응답' '' '' '  Ran 1 shell command' "$SEP" '  표 아래 본문 — 구분선 뒤에 프롬프트가 없으니 자르면 안 됨' \
  '\033[1m⏺ 굵은 응답\033[0m' '✻ Cooked for 3s · done 오후 10:41' \
  "\033[38;2;136;136;136m${SEP} sess#1 ${SEP}\033[39m" '\033[38;2;153;153;153m❯ \033[39m' "$SEP" \
  '  branch:main | !1' '  [OMC#5.3.0L] | Model: X' '  ⏵⏵ auto mode on')"
render_out="$(printf '%s\n' "$render_in" | env -u TMUX "$TMM" __render)"
plain="$(printf '%s\n' "$render_out" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g')"
printf '%s\n' "$plain" | grep -q '표 아래 본문' || { echo 'FAIL: 본문 속 표 구분선에서 잘림'; printf '%s\n' "$plain"; exit 1; }
printf '%s\n' "$plain" | grep -qE '❯|branch:main|OMC#|auto mode' && { echo 'FAIL: 입력박스/statusline 이 남음'; printf '%s\n' "$plain"; exit 1; }
[ "$(printf '%s\n' "$plain" | tail -1)" = '✻ Cooked for 3s · done 오후 10:41' ] || { echo 'FAIL: 마지막 줄이 완료 마커가 아님'; printf '%s\n' "$plain"; exit 1; }
blank_n="$(printf '%s\n' "$render_in" | env -u TMUX "$TMM" __render | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -c '^$')"
[ "$blank_n" -eq 1 ] || { echo "FAIL: 연속 빈 줄이 1줄로 안 눌림 (blank=$blank_n)"; printf '%s\n' "$plain"; exit 1; }
printf '%s\n' "$render_out" | LC_ALL=C grep -aq $'\x1b\[1m' || { echo 'FAIL: SGR 색 코드가 사라짐'; exit 1; }
codex_out="$(printf '%s\n' '• Ran rg foo' '' '› Ask Codex to do anything' '' '  gpt-6 high · main · Context 31% left' | env -u TMUX "$TMM" __render)"
[ "$codex_out" = '• Ran rg foo' ] || { echo 'FAIL: Codex 프롬프트 이하가 안 잘림'; printf '%s\n' "$codex_out"; exit 1; }

echo "✅ tmm verify OK"
