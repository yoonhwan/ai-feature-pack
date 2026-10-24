#!/usr/bin/env bash
# h-mini-satellite-nano-test.sh — «위성 나노» 실험: 이 맥에서 ssh 로 mini 에 pi 나노 1개를 열고 → 작업 1건 시키고 → 결과 회수 → 닫는다. 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   2026-10-25 · aifp-multihost-master-claude#4 · 오빠 «이슈팀 팀장이 나노워커를 mini에 열어서 위성으로 ssh로 열어 사용하고 닫는 실험부터»
#   열기=tmuxc open(pi · deepseek flash) · 작업=mini 작업 폴더의 TASK.md 1장(요약 3줄+완료 표지) · 회수=scp · 닫기=이 스크립트가 연 세션만 kill-session(오빠 지시 «열어서 사용하고 닫는»)
#   쓰는 곳: mini ~/Project/satellite-nano/<RUN>/ (새 폴더만) · tmux 세션 1개(이 스크립트가 연 것) · 이 맥 docs/multihost/satellite/<RUN>-out.md
#   하지 않는 일: BYZ 소스·서버·Redis·settings 접촉 0 · 다른 세션 kill 0 · 폴더 삭제 0
# 사용: bash /tmp/h<N>        → 실험 실행
#       DRY=1 bash /tmp/h<N>  → 사전점검만(쓰기 0)
# rc: 0 성공 · 2 전제 실패 · 3 세션 열기 실패 · 4 작업 전달 실패 · 5 결과 시간 초과 · 6 닫기 실패(남은 프로세스 있음)
set -uo pipefail
MINI="${MINI:-mini}"; DRY="${DRY:-0}"; RUN="${RUN:-test-1}"
NAME="aifp-sat-nano-pi#0"; MODEL="opengateway/deepseek/deepseek-v4.1-flash-ultrafast"
RDIR="Project/satellite-nano/$RUN"; WAIT_S="${WAIT_S:-240}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; OUTD="$HERE/../satellite"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-sat] %s\n' "$*"; }
die() { printf '[h-sat] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }
OPENED=0
closeit() {
  [ "$OPENED" = "1" ] || return 0
  say "닫기 — 이 스크립트가 연 세션 $NAME 만"
  ms 15 "tmux kill-session -t '=$NAME' 2>&1; sleep 2; left=\$(for p in \$(pgrep -x pi 2>/dev/null); do c=\$(lsof -a -p \$p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); case \"\$c\" in \"\$HOME/$RDIR\"*) echo \$p;; esac; done | wc -l | tr -d ' '); s=\$(tmux has-session -t '=$NAME' 2>/dev/null && echo alive || echo gone); echo session=\$s pi_left=\$left" 2>&1 | sed 's/^/        /' | tee /tmp/.h-sat-close.$$
  grep -q "session=gone pi_left=0" /tmp/.h-sat-close.$$ || { rm -f /tmp/.h-sat-close.$$; say "⚠ 닫기 확인 실패 — 세션/프로세스가 남았다(위 출력). 강제 kill 은 하지 않는다 — 보고만"; CLOSE_FAIL=1; return 0; }
  rm -f /tmp/.h-sat-close.$$; say "닫힘 확인 — 세션 없음 · 이 폴더에서 도는 pi 0"
}
CLOSE_FAIL=0
trap 'closeit' EXIT

PRE="$(ms 20 'echo tmuxc=$(command -v tmuxc >/dev/null && echo ok || echo MISSING); echo pi=$(command -v pi >/dev/null && echo ok || echo MISSING); echo sess=$(tmux has-session -t "='"$NAME"'" 2>/dev/null && echo EXISTS || echo absent); echo dir=$([ -e $HOME/'"$RDIR"' ] && echo EXISTS || echo absent); echo keyfile=$([ -s $HOME/.pi/agent/opengateway.key ] && echo ok || echo MISSING); echo mem_free_pct=$(memory_pressure 2>/dev/null | sed -n "s/.*free percentage: //p" | head -1)' 2>&1)" || die 2 "mini 접속 실패: ${PRE}"
printf '%s\n' "$PRE" | sed 's/^/        /'
case "$PRE" in *MISSING*) die 2 "mini 에 필요한 것이 없다(위 MISSING)";; esac
case "$PRE" in *"sess=EXISTS"*) die 2 "이미 같은 이름 세션이 있다 — 남의 세션이라 건드리지 않는다";; esac
case "$PRE" in *"dir=EXISTS"*) die 2 "작업 폴더 $RDIR 가 이미 있다 — RUN=<다른이름> 으로 다시";; esac
if [ "$DRY" = "1" ]; then OPENED=0; say "DRY — 쓰기 0. 조건 OK: ① 폴더 생성+TASK.md ② tmuxc open(pi) ③ 작업 전달 ④ 결과 대기(최대 ${WAIT_S}s) ⑤ scp 회수 ⑥ 세션 닫기"; exit 0; fi

say "1/6 작업 폴더·TASK.md (mini 새 폴더)"
{
  printf '%s\n' "# 위성 나노 실험 작업 ($RUN)" "" "아래 «입력» 을 읽고 한국어 3줄로 요약해서 같은 폴더의 out.md 에 쓴다. 그 다음 out.md 맨 끝 줄에 정확히 이 형식으로 한 줄 추가한다:" "SAT-DONE host=\$(hostname 의 실제 출력값)" "다른 파일·폴더는 건드리지 않는다. 쓰기는 이 폴더 안 out.md 뿐이다. 끝나면 더 하지 않는다." "" "## 입력"
  sed -n 1,40p "$HERE/../BUG-seam-store-release-20261025.md" 2>/dev/null || echo "(입력 문서 없음)"
} | ms 15 "mkdir -p \$HOME/$RDIR && cat > \$HOME/$RDIR/TASK.md && wc -l \$HOME/$RDIR/TASK.md" 2>&1 | sed 's/^/        /'
[ "${PIPESTATUS[1]}" = "0" ] || die 4 "TASK.md 쓰기 실패"

say "2/6 pi 나노 열기 (tmuxc open · $MODEL)"
OP="$(ms 40 "tmuxc open \$HOME/$RDIR --name '$NAME' --agent pi --role worker --model '$MODEL' --effort medium 2>&1" 2>&1)" || die 3 "tmuxc open 실패: $(printf '%s' "$OP" | tail -3)"
printf '%s\n' "$OP" | tail -6 | sed 's/^/        /'
OPENED=1
say "        pi 프로세스 기동 대기(최대 30초)"
UP=0; for i in 1 2 3 4 5 6; do
  N="$(ms 12 "pp=\$(tmux display -p -t '=$NAME' '#{pane_pid}' 2>/dev/null); [ -n \"\$pp\" ] && pgrep -P \$pp | wc -l | tr -d ' '" 2>/dev/null)"
  [ "${N:-0}" -ge 1 ] 2>/dev/null && { UP=1; break; }; sleep 5
done
[ "$UP" = "1" ] || die 3 "pi 프로세스가 안 떴다(HARD GATE: 자식 0건이라 입력 전송 금지)"
sleep 8

say "3/6 작업 전달 (한 줄 지시문 — -l 과 Enter 별도 호출)"
MSG="[aifp-multihost-master-claude#4->$NAME] 작업이다. ~/$RDIR/TASK.md 를 읽고 그대로 수행해라. 결과는 같은 폴더 out.md."
ms 12 "tmux send-keys -t '=$NAME' -l '$MSG'" || die 4 "send-keys(-l) 실패"
sleep 1
ms 12 "tmux send-keys -t '=$NAME' Enter" || die 4 "send-keys(Enter) 실패"

say "4/6 결과 대기 (최대 ${WAIT_S}초 · 10초마다 확인)"
DONE=0; T0=$(date +%s)
while [ $(( $(date +%s) - T0 )) -lt "$WAIT_S" ]; do
  if ms 12 "grep -q '^SAT-DONE' \$HOME/$RDIR/out.md 2>/dev/null"; then DONE=1; break; fi
  sleep 10
done
if [ "$DONE" != "1" ]; then
  say "시간 초과 — 화면 마지막 줄(진단):"; ms 12 "tmux capture-pane -p -t '=$NAME' | tail -6 | cut -c1-160" 2>&1 | sed 's/^/        /'
  die 5 "out.md 의 SAT-DONE 이 ${WAIT_S}초 안에 안 생겼다"
fi
say "        완료 — 걸린 시간 $(( $(date +%s) - T0 ))초"

say "5/6 결과 회수 (scp)"
mkdir -p "$OUTD"
timeout 20 scp "${SO[@]}" "$MINI:$RDIR/out.md" "$OUTD/$RUN-out.md" >/dev/null 2>&1 || say "⚠ scp 실패 — mini 쪽 파일은 남아 있다: $RDIR/out.md"
[ -f "$OUTD/$RUN-out.md" ] && sed 's/^/        | /' "$OUTD/$RUN-out.md" | head -12

say "6/6 닫기"
closeit
trap - EXIT
[ "$CLOSE_FAIL" = "0" ] || die 6 "닫기 확인 실패"
say "완료 rc=0 — 위성 나노 열기→작업→회수→닫기 1회 성공 (결과 $OUTD/$RUN-out.md)"
exit 0
