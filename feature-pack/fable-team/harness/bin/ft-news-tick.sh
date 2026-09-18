#!/usr/bin/env bash
# 뉴스 틱 = «큐 비우기 + 적체 + 좌석 순회 + 브랜치 순회»를 한 명령으로 묶는다.
# 왜: 규칙(§6-1·규칙13)에 네 번 박고 네 번 어겼다 — 오빠 「내가 뉴스 발행할때마다 읽으라고했지 / 몇번얘기했냐」.
#     기억으로 지키는 규칙은 지켜지지 않는다. 뉴스를 쓰려면 «이 명령을 먼저 돌려야» 값이 나오게 만든다.
set -u
ROOT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
WT=$ROOT/.worktrees/v6-realtime-live
ME=ft-v65-master-claude#3
echo "════ ① 내 큐 비우기 ════"
bash "$ROOT/.fable-team/comm/mbox.sh" recv "$ME" --all 2>&1 | grep -vE '^SCANNED' | head -40
echo; echo "════ ①-b ★나를 기다리는 좌석★ ════"
bash "$WT/.fable-team/bin/ft-blocked-on-master.sh" 2>/dev/null
echo; echo "════ ② 좌석 적체 ════"
bash "$WT/.fable-team/bin/ft-mbox-census.sh" 3
echo; echo "════ ③ 좌석 상태 ════"
python3 -c "
import json;d=json.load(open('$ROOT/.fable-team/seats.json'))
print('\n'.join(k for k,v in d.items() if isinstance(v,dict) and v.get('role') not in ('stop-ready',) and k.startswith('ft-v65')))" 2>/dev/null | while read -r S; do
  T=$(bash "$WT/.fable-team/bin/ft-seat-status.sh" turn "$S" 2>/dev/null | awk '{print $1}')
  A=$(bash "$WT/.fable-team/bin/ft-seat-status.sh" one "$S" 2>/dev/null | awk '{print $3}')
  [ -n "$T" ] && [ "$T" != "UNKNOWN" -o "$A" != "-" ] && printf "%-50s %-8s age=%s\n" "${S:0:50}" "$T" "$A"
done
echo; echo "════ ④ 좌석 브랜치 미랜딩 (그 턴에 랜딩할 것) ════"
for W in "$ROOT"/.worktrees/v65-*; do
  [ -d "$W/.git" ] || [ -f "$W/.git" ] || continue
  N=$(git -C "$W" log --oneline feat/v6-realtime-live..HEAD 2>/dev/null | wc -l | tr -d ' ')
  [ "${N:-0}" != "0" ] && printf "%-46s 미랜딩=%s\n" "$(basename "$W")" "$N"
done
echo; echo "════ ⑤ 라이브 값 ════"
R=v6-realtime-live-redis-1
echo "PEL=$(docker exec $R redis-cli --no-auth-warning XINFO GROUPS lst_stt_requests 2>/dev/null | sed -n '6p') lease=$(docker exec $R redis-cli --no-auth-warning EVAL "local c=0 local cur='0' repeat local r=redis.call('SCAN',cur,'MATCH','lst_stt_requests:lease:*','COUNT',5000) cur=r[1] c=c+#r[2] until cur=='0' return c" 0 2>/dev/null) $(docker exec $R redis-cli --no-auth-warning INFO memory 2>/dev/null | grep used_memory_human | tr -d '\r')"
WPID=$(lsof -ti:8081 -sTCP:LISTEN 2>/dev/null | head -1)
[ -n "$WPID" ] && echo "worker pid=$WPID 기동=$(ps -o lstart= -p $WPID | sed 's/^ *//')  최신제품커밋=$(git -C "$WT" log -1 --format='%h %ad' --date=format:'%m-%d %H:%M:%S' -- worker shared gateway clients)"
