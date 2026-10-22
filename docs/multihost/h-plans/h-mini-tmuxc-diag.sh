#!/usr/bin/env bash
# h-mini-tmuxc-diag.sh — mini 에서 «tmuxc open 경유 claude 가 안 뜨는 원인» 을 가르는 진단(좌석 2개 열고 화면 캡처 뒤 전부 닫음)
#   초안(2026-10-22 · aifp-multihost-master-claude#1) · 실행은 오빠가 `! bash /tmp/h<N>` 로만. 하네스 파일(tmuxc) 편집 0.
#   배경: h375 설치는 OK 인데 `tmuxc open --model claude-sonnet-5-5` 가 세션은 만들지만 2·4·6초에 pane 자식 0 · probe «no known agent process».
#   같은 명령을 tmux new-session 에 직접 주면 claude 가 산다(상위 진단). → 가설: tmuxc 는 «빈 셸을 만든 뒤 send-keys 로 명령을 타이핑» 한다
#   (core/bin/tmuxc:62 create_tmux_session → :706 inject_message). 셸이 입력 준비되기 전에 타이핑이 들어가 유실되는 경쟁이면 B(준비 대기 뒤 타이핑)는 산다.
# 가르는 법: A = tmuxc open 그대로 → 캡처. B = 같은 명령을 «셸 프롬프트가 나온 뒤» 타이핑 → 캡처. A 죽음 + B 삶 = 타이핑 경쟁(tmuxc 카드 · 하네스).
#   A·B 모두 죽음 = mini 쪽 환경(zsh 초기화·권한). 둘 다 삶 = 간헐(재현 횟수 늘림).
# 소리·API 호출 없음: claude 가 뜨면 첫 화면(폴더 신뢰 질문)에서 멈춘다 — 입력을 보내지 않고 캡처만 한다. 비밀 0.
# rc: 0 진단 완료(결과는 출력 읽기) · 2 사전점검 · 3 원격 실패
set -uo pipefail
MINI="${MINI:-mini}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-diag] %s\n' "$*"; }
die() { printf '[h-diag] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }

say "0/4 사전점검"
ms 20 'test "$(id -un)" = byz && command -v tmuxc tmux >/dev/null && test -x $HOME/.headroom/claude-hr.sh && echo pre=ok' 2>&1 | grep -q pre=ok || die 2 "mini 사전점검 실패(byz·tmuxc·tmux·claude-hr.sh)"
ms 15 'tmux has-session -t diag-a 2>/dev/null && echo busy-a; tmux has-session -t diag-b 2>/dev/null && echo busy-b; true' | grep -q busy && die 2 "diag-a/diag-b 세션이 이미 있다 — 남의 것일 수 있어 건드리지 않는다"

say "1/4 A — tmuxc open 그대로 (diag-a)"
ms 60 'cd $HOME && tmuxc open . --name diag-a --agent claude --model claude-sonnet-5-5 --role worker 2>&1 | head -3; for s in 2 2 2; do sleep $s; p=$(tmux list-panes -t =diag-a -F "#{pane_pid}" 2>/dev/null | head -1); printf "A t+%ss pane_pid=%s children=%s cmd=%s\n" $s "$p" "$(pgrep -P ${p:-0} 2>/dev/null | wc -l | tr -d " ")" "$(tmux display -p -t =diag-a "#{pane_current_command}" 2>/dev/null)"; done; echo "--- A pane 캡처(끝 12줄)"; tmux capture-pane -p -t =diag-a 2>/dev/null | grep -v "^\s*$" | tail -12 | cut -c1-140' 2>&1 | sed 's/^/        /'

say "2/4 B — 셸 프롬프트가 나온 뒤 같은 명령 타이핑 (diag-b)"
ms 60 'cd $HOME && tmux new-session -d -s diag-b -c "$HOME"; for i in 1 2 3 4 5 6 7 8 9 10; do sleep 1; tmux capture-pane -p -t =diag-b 2>/dev/null | grep -q "[%$#❯>] *$" && break; done; echo "B 프롬프트 대기 ${i}초"; tmux send-keys -t =diag-b -l "$HOME/.headroom/claude-hr.sh --dangerously-skip-permissions --model \"claude-sonnet-5-5\" --name diag-b --remote-control diag-b"; sleep 0.3; tmux send-keys -t =diag-b Enter; for s in 2 2 2; do sleep $s; p=$(tmux list-panes -t =diag-b -F "#{pane_pid}" 2>/dev/null | head -1); printf "B t+%ss pane_pid=%s children=%s cmd=%s\n" $s "$p" "$(pgrep -P ${p:-0} 2>/dev/null | wc -l | tr -d " ")" "$(tmux display -p -t =diag-b "#{pane_current_command}" 2>/dev/null)"; done; echo "--- B pane 캡처(끝 12줄)"; tmux capture-pane -p -t =diag-b 2>/dev/null | grep -v "^\s*$" | tail -12 | cut -c1-140' 2>&1 | sed 's/^/        /'

say "3/4 닫기(diag-a·diag-b 만)"
ms 30 'for s in diag-a diag-b; do tmux has-session -t =$s 2>/dev/null && tmux kill-session -t =$s; tmux has-session -t =$s 2>/dev/null && echo "$s=STILL_ALIVE" || echo "$s=closed"; done' 2>&1 | sed 's/^/        /'

say "4/4 끝"
cat <<'EOF'
        판독: A children=0 이고 B children≥1 → tmuxc 의 «빈 셸 생성 직후 타이핑» 경쟁(셸 준비 전 입력 유실) → 하네스 tmuxc 카드(프롬프트 대기 후 주입) 요청.
              A·B 모두 children=0 → capture 화면의 오류 문구가 원인(zsh 초기화·claude-hr.sh 실패) → mini 쪽 설정 h.
              A·B 모두 ≥1 → 간헐 — 같은 h 를 몇 번 더.
        이 h 가 하지 않은 것: 입력 전송(claude 첫 화면에는 아무것도 보내지 않음) · 설치 0 · 파일 쓰기 0 · diag-a/diag-b 외 세션 접촉 0
EOF
exit 0
