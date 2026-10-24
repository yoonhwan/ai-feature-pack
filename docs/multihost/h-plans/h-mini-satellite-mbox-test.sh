#!/usr/bin/env bash
# h-mini-satellite-mbox-test.sh — 위성 쪽지함 왕복 실험: 이 맥 → (ssh push) → mini 나노 쪽지 수신 → 나노 회신(send) → (ssh pull) → 이 맥 쪽지함. 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   2026-10-25 · aifp-multihost-master-claude#4 · 오빠 «ft 의 mbox ssh 지원부터» → 얇은 위성 전용(새 키 0 · 이 맥이 먼저 ssh 로 가져오는 pull)
#   열기=tmuxc open(pi) · 쪽지=docs/multihost/satellite/sat-mbox.py(push/pull) · 닫기=이 스크립트가 연 세션만 kill-session
#   쓰는 곳: mini ~/Project/satellite-nano/<RUN>/ · mini ~/.fable-team/comm/(새 쪽지함 — 제품 쪽지함 아님) · tmux 세션 1개 · 이 맥은 «임시» 쪽지함 폴더 1개(제품 쪽지함 0 쓰기)
#   하지 않는 일: BYZ 소스·서버·Redis·settings·authorized_keys 접촉 0 · 다른 세션 kill 0 · 삭제 0(임시 폴더도 지우지 않음)
# 사용: bash /tmp/h<N> · DRY=1 → 사전점검만(쓰기 0)
# rc: 0 성공 · 2 전제 실패 · 3 세션 열기 실패 · 4 쪽지/지시 전달 실패 · 5 회신 시간 초과 · 6 닫기 실패
set -uo pipefail
MINI="${MINI:-mini}"; DRY="${DRY:-0}"; RUN="${RUN:-mbox-1}"
NAME="aifp-sat-nano-pi#0"; MACSEAT="aifp-sat-test-master#0"; MODEL="opengateway/deepseek/deepseek-v4.1-flash-ultrafast"
RDIR="Project/satellite-nano/$RUN"; WAIT_S="${WAIT_S:-240}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SAT="$HERE/../satellite/sat-mbox.py"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-satmb] %s\n' "$*"; }
die() { printf '[h-satmb] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }
OPENED=0; CLOSE_FAIL=0
closeit() {
  [ "$OPENED" = "1" ] || return 0
  say "닫기 — 이 스크립트가 연 세션 $NAME 만"
  ms 15 "tmux kill-session -t '=$NAME' 2>&1; sleep 2; left=\$(for p in \$(pgrep -x pi 2>/dev/null); do c=\$(lsof -a -p \$p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); case \"\$c\" in \"\$HOME/$RDIR\"*) echo \$p;; esac; done | wc -l | tr -d ' '); s=\$(tmux has-session -t '=$NAME' 2>/dev/null && echo alive || echo gone); echo session=\$s pi_left=\$left" 2>&1 | sed 's/^/        /' > /tmp/.h-satmb-close.$$
  cat /tmp/.h-satmb-close.$$
  grep -q "session=gone pi_left=0" /tmp/.h-satmb-close.$$ && say "닫힘 확인 — 세션 없음 · 이 폴더에서 도는 pi 0" || { say "⚠ 닫기 확인 실패 — 강제 kill 없이 보고만"; CLOSE_FAIL=1; }
  OPENED=0
}
trap 'closeit' EXIT

[ -f "$SAT" ] || die 2 "sat-mbox.py 가 없다: $SAT"
python3 -I -m py_compile "$SAT" 2>/dev/null || die 2 "sat-mbox.py 문법 오류"
PRE="$(ms 20 'echo tmuxc=$(command -v tmuxc >/dev/null && echo ok || echo MISSING); echo pi=$(command -v pi >/dev/null && echo ok || echo MISSING); echo ftmbox=$([ -f $HOME/.claude/skills/fable-team/scripts/ft-mbox.py ] && echo ok || echo MISSING); echo sess=$(tmux has-session -t "='"$NAME"'" 2>/dev/null && echo EXISTS || echo absent); echo dir=$([ -e $HOME/'"$RDIR"' ] && echo EXISTS || echo absent); echo mbox_dir_pending=$(ls $HOME/.fable-team/comm 2>/dev/null | wc -l | tr -d " ")' 2>&1)" || die 2 "mini 접속 실패: ${PRE}"
printf '%s\n' "$PRE" | sed 's/^/        /'
case "$PRE" in *MISSING*) die 2 "mini 에 필요한 것이 없다(위 MISSING)";; esac
case "$PRE" in *"sess=EXISTS"*) die 2 "같은 이름 세션이 이미 있다 — 건드리지 않는다";; esac
case "$PRE" in *"dir=EXISTS"*) die 2 "작업 폴더 $RDIR 가 이미 있다 — RUN=<다른이름> 으로 다시";; esac
MACBOX="$(mktemp -d "${TMPDIR:-/tmp}/h-satmb.XXXXXX")/comm"; mkdir -p "$MACBOX" || die 2 "임시 쪽지함 생성 실패"
say "이 맥 임시 쪽지함(제품 아님): $MACBOX"
if [ "$DRY" = "1" ]; then say "DRY — 쓰기 0(임시 폴더 제외). 조건 OK: ① 작업 폴더 ② push(이 맥→mini 쪽지) ③ 나노 열기+지시 ④ pull 로 회신 대기(최대 ${WAIT_S}s) ⑤ 닫기"; exit 0; fi

say "1/5 작업 폴더 + push (이 맥 → mini 쪽지함)"
ms 15 "mkdir -p \$HOME/$RDIR" || die 4 "폴더 생성 실패"
BODY="[aifp-multihost-master-claude#4->$NAME] 회신 작업. 아래 명령을 그대로 실행해라: FT_MBOX_DIR=\$HOME/.fable-team/comm bash \$HOME/.claude/skills/fable-team/scripts/ft-mbox.sh send '$MACSEAT' '$NAME' \"SAT-MBOX-REPLY host=\$(hostname)\" — 실행 뒤 더 하지 않는다."
python3 -I "$SAT" push "$NAME" "aifp-multihost-master-claude#4" "$BODY" 2>&1 | sed 's/^/        /'
[ "${PIPESTATUS[0]}" = "0" ] || die 4 "push 실패"

say "2/5 pi 나노 열기"
OP="$(ms 40 "tmuxc open \$HOME/$RDIR --name '$NAME' --agent pi --role worker --model '$MODEL' --effort medium 2>&1" 2>&1)" || die 3 "tmuxc open 실패: $(printf '%s' "$OP" | tail -3)"
OPENED=1
UP=0; for i in 1 2 3 4 5 6; do
  N="$(ms 12 "pp=\$(tmux display -p -t '=$NAME:' '#{pane_pid}' 2>/dev/null); [ -n \"\$pp\" ] && pgrep -P \$pp | wc -l | tr -d ' '" 2>/dev/null)"
  [ "${N:-0}" -ge 1 ] 2>/dev/null && { UP=1; break; }; sleep 5
done
[ "$UP" = "1" ] || die 3 "pi 프로세스가 안 떴다(자식 0건이라 입력 전송 금지)"
sleep 8

say "3/5 나노에게 지시 한 줄 (-l 과 Enter 별도 호출)"
MSG="[발주 #1] 쪽지가 왔다. 실행해서 읽고 그 안의 지시를 즉시 수행해라: FT_MBOX_DIR=\$HOME/.fable-team/comm bash \$HOME/.claude/skills/fable-team/scripts/ft-mbox.sh recv '$NAME'"
ms 12 "tmux send-keys -t '=$NAME:' -l \"$MSG\"" || die 4 "send-keys(-l) 실패"
sleep 1
ms 12 "tmux send-keys -t '=$NAME:' Enter" || die 4 "send-keys(Enter) 실패"

say "4/5 회신 대기 — 10초마다 pull (최대 ${WAIT_S}초)"
GOT=0; T0=$(date +%s)
while [ $(( $(date +%s) - T0 )) -lt "$WAIT_S" ]; do
  FT_MBOX_DIR="$MACBOX" python3 -I "$SAT" pull --seats "$MACSEAT" 2>&1 | sed 's/^/        /'
  if FT_MBOX_DIR="$MACBOX" bash "$HOME/.claude/skills/fable-team/scripts/ft-mbox.sh" peek "$MACSEAT" 2>/dev/null | grep -q "pending=[1-9]"; then GOT=1; break; fi
  sleep 10
done
if [ "$GOT" != "1" ]; then
  say "시간 초과 — 나노 화면 마지막 줄(진단):"; ms 12 "tmux capture-pane -p -t '=$NAME:' | tail -6 | cut -c1-160" 2>&1 | sed 's/^/        /'
  die 5 "이 맥 임시 쪽지함에 회신이 ${WAIT_S}초 안에 안 왔다"
fi
say "        도착 — 걸린 시간 $(( $(date +%s) - T0 ))초. 이 맥에서 읽은 내용:"
FT_MBOX_DIR="$MACBOX" bash "$HOME/.claude/skills/fable-team/scripts/ft-mbox.sh" recv "$MACSEAT" 2>&1 | grep "^READ" | sed 's/^/        | /'
RES="$(ms 15 "FT_MBOX_DIR=\$HOME/.fable-team/comm bash \$HOME/.claude/skills/fable-team/scripts/ft-mbox.sh peek '$NAME'" 2>&1 | head -1)"
say "        mini 쪽 나노 앞 대기: ${RES} (pending=0 이면 나노가 지시 쪽지를 소비함)"

say "5/5 닫기"
closeit
trap - EXIT
[ "$CLOSE_FAIL" = "0" ] || die 6 "닫기 확인 실패"
say "6/6 (덤) 실제 쪽지함으로 pull — 앞선 위성 실험(test-2) 때 mini 쪽지함에 갇힌 나노 보고(수신자 aifp-multihost-master-claude#4)를 진짜 쪽지함에 배달"
python3 -I "$SAT" pull --seats "aifp-multihost-master-claude#4" 2>&1 | sed 's/^/        /'
say "완료 rc=0 — 쪽지 왕복 성공: 이 맥 push → mini 나노 recv·send → 이 맥 pull. (임시 쪽지함 $MACBOX 는 지우지 않았다) · 갇힌 보고는 위 6/6 줄 확인 후 recv"
exit 0
