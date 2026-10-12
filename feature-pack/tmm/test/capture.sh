#!/usr/bin/env bash
# tmm 0.8.0 분할 화면 «실측 캡처» — 격리 tmux 서버(mktemp 소켓 · set-environment TMPDIR 격리)에 가짜 좌석 8개를 만들고
#   python pty 클라이언트로 tmm 을 띄워 70열/120열 화면과 키(Esc·↓↓·Enter·↓·^X) 동작을 텍스트로 남긴다. 기본 서버·남의 좌석 무접촉. 결과 예 = test/capture-0.8.0-*.txt
# 사용: bash capture.sh <cols> <rows> <출력파일>
set -uo pipefail
COLS="$1"; ROWS="$2"; OUT="$3"
TMM="$(cd "$(dirname "$0")/.." && pwd)/core/bin/tmm"
SOCK="$(mktemp -d "${TMPDIR:-/tmp}/tmmcap.XXXXXX")"
tm() { env -u TMUX TMUX_TMPDIR="$SOCK" tmux "$@"; }
cleanup() { env -u TMUX TMUX_TMPDIR="$SOCK" tmux kill-server 2>/dev/null || true; rm -rf "$SOCK"; }
trap cleanup EXIT
# 가짜 좌석(셸만) — 카테고리가 여럿 생기게
for n in 'byz-harness-master-claude#32' 'byz-harness-nano-tmm-split-ui-claude#0' 'byz-harness-arch-claude#35' 'byz-v65-master-claude#90' 'byz-v65-tester-claude#3' 'byz-cfo-master-claude#61' 'loom_a#1' 'byz-graphics-nano-g12-claude#0'; do
  tm new-session -d -s "$n" -x 120 -y 30 -c "$HOME"
done
sleep 0.3
tm set-environment -g TMPDIR "$SOCK"   # 피커 안의 tmm 이 격리 STATE 를 보게(실제 rows.snap·ep.cache 무접촉)
# pty 클라이언트로 tmm 실행(tui_wrap 이 격리 서버 안에 피커 세션을 만든다). 35초 뒤 스스로 끝.
python3 - "$SOCK" "$TMM" "$COLS" "$ROWS" "$OUT.raw" <<'PYC' &
import os, pty, sys, time, fcntl, termios, struct, select
sock, tmm, cols, rows, raw = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
env = dict(os.environ, TMUX_TMPDIR=sock, TMPDIR=sock, TERM="xterm-256color", TMM_CACHE_TTL="0", TMM_CATEGORIES="/dev/null", LANG="ko_KR.UTF-8", LC_ALL="ko_KR.UTF-8")
env.pop("TMUX", None); env.pop("TMUX_PANE", None); env.pop("TMM_RUN", None)
pid, fd = pty.fork()
if pid == 0:
    os.execvpe("bash", ["bash", tmm], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
end = time.time() + 35
with open(raw, "wb") as f:
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.5)
        if fd in r:
            try:
                d = os.read(fd, 65536)
            except OSError:
                break
            if not d: break
            f.write(d)
PYC
PTY=$!
# 피커 세션이 뜨고 pane 이 2개 될 때까지
for _ in $(seq 1 60); do [ "$(tm list-panes -t '=tmm:' 2>/dev/null | wc -l | tr -d ' ')" = 2 ] && break; sleep 0.25; done
sleep 4   # 첫 목록·분류 칸 채우기
snap() {  # <라벨> — 두 pane 을 가로로 붙여 저장
  local lab="$1" cp mp
  cp="$(tm list-panes -t '=tmm:' -F '#{pane_id} #{pane_left} #{pane_width}' | sort -k2 -n | head -1 | cut -d' ' -f1)"
  mp="$(tm list-panes -t '=tmm:' -F '#{pane_id} #{pane_left}' | sort -k2 -n | tail -1 | cut -d' ' -f1)"
  local act; act="$(tm display -p -t '=tmm:' '#{pane_id}')"
  {
    printf '=== %s · %sx%s · 활성 pane=%s(%s) ===\n' "$lab" "$COLS" "$ROWS" "$act" "$([ "$act" = "$cp" ] && echo 분류칸 || echo 목록칸)"
    paste -d'│' <(tm capture-pane -p -t "$cp" | python3 -c '
import sys,unicodedata
w=int(sys.argv[1])
for l in sys.stdin.read().split("\n"):
    cw=sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l)
    print(l + " "*max(0,w-cw))' "$(tm display -p -t "$cp" '#{pane_width}')") <(tm capture-pane -p -t "$mp")
    echo
  } >> "$OUT"
}
: > "$OUT"
snap "부팅 직후(분류 칸=첫 카테고리)"
CP="$(tm list-panes -t '=tmm:' -F '#{pane_id} #{pane_left}' | sort -k2 -n | head -1 | cut -d' ' -f1)"
MP="$(tm list-panes -t '=tmm:' -F '#{pane_id} #{pane_left}' | sort -k2 -n | tail -1 | cut -d' ' -f1)"
# 목록 칸에서 Esc → 분류 칸으로
tm send-keys -t "$MP" Escape; sleep 1
snap "목록 칸에서 Esc → 분류 칸 활성"
# 분류 칸 ↓ ↓ → 목록이 그 카테고리로
tm send-keys -t "$CP" Down; sleep 1.5; tm send-keys -t "$CP" Down; sleep 2
snap "분류 칸 ↓↓ → 목록이 세 번째 카테고리로 바뀜"
# 분류 칸 Enter → 목록 칸으로
tm send-keys -t "$CP" Enter; sleep 1
snap "분류 칸 Enter → 목록 칸 활성"
# 목록 칸 ↓ → 커서 이동(분류 칸 그대로)
tm send-keys -t "$MP" Down; sleep 1
snap "목록 칸 ↓ → 목록 커서만 이동"
# ^X 끝
tm send-keys -t "$MP" C-x; sleep 1.5
printf '=== ^X 뒤 피커 세션 존재? %s · 분류 pane 남음? %s ===\n' "$(tm has-session -t '=tmm' 2>/dev/null && echo yes || echo no)" "$(tm list-panes -a 2>/dev/null | grep -c catpane)" >> "$OUT"
kill "$PTY" 2>/dev/null; wait "$PTY" 2>/dev/null
echo "saved: $OUT"
