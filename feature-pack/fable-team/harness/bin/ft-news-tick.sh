#!/usr/bin/env bash
# 뉴스 틱 = «큐 비우기 + 적체 + 좌석 순회 + 브랜치 순회»를 한 명령으로 묶는다.
# 왜: 규칙(§6-1·규칙13)에 네 번 박고 네 번 어겼다 — 오빠 「내가 뉴스 발행할때마다 읽으라고했지 / 몇번얘기했냐」.
#     기억으로 지키는 규칙은 지켜지지 않는다. 뉴스를 쓰려면 «이 명령을 먼저 돌려야» 값이 나오게 만든다.
set -u
ROOT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
WT=$ROOT/.worktrees/v6-realtime-live
# ME 는 seats.json 의 «현역 master» 에서 읽는다 — 좌석명을 박아두면 승계 때마다 죽은 큐를 읽는다
# (실측 2026-09-22: 박힌 값이 ft-v65-master-claude#3 인데 그 좌석은 없고 현역은 ft-v65-master-opus#7).
# 못 찾으면 #0 RULE 대로 죽는다 — 엉뚱한 좌석 큐를 조용히 읽어 「pending=0」을 거짓으로 만들지 않는다.
ME=${FT_ME:-$(python3 -c "
import json
d=json.load(open('$ROOT/.fable-team/seats.json'))
print(next((k for k,v in d.items()
            if isinstance(v,dict) and v.get('role')=='master' and not v.get('_replaced_by')), ''))
" 2>/dev/null)}
[ -n "$ME" ] || { echo "ERROR: seats.json 에 현역 master 가 없다 — FT_ME 로 좌석명을 지정해라" >&2; exit 2; }
echo "ME=$ME (seats.json 현역 master)"
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
echo; echo "════ ⑥ 완성본 하는 일 트리 (뉴스에 그대로 · 상태는 카드 폴더·seats.json 에서) ════"
TREE="${FT_NEWS_TREE:-$WT/design/v65/NEWS-TREE.md}"
if [ -f "$TREE" ]; then python3 "$WT/.fable-team/bin/ft-news-tree.py" "$TREE"; else echo "ERROR: 트리 원본 없음 — $TREE" >&2; fi
