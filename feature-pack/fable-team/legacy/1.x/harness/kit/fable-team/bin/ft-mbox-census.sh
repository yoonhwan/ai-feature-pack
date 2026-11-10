#!/usr/bin/env bash
# 좌석별 미독(pending) 전수 — 뉴스 §세션 상태 첫 줄용 (오빠 지시 2026-09-17
#   「다른 세션들도 mbox에 n개 이상 쌓인거 체크되게 세션 엠박스 카운팅도 세션 상태에 추가」).
# 왜: 내 큐만 보면 «내가 못 읽은 것»만 보인다. 좌석이 「보냈다」고 해도 받는 쪽 큐가
#     막혀 있으면 값이 안 돈다 — 링 버퍼 10 이라 방치하면 영구 유실이다.
# 쓰기: ft-mbox-census.sh [임계N=3]
set -u
ROOT="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents"
THRESH="${1:-3}"
ALL="${2:-}"
python3 - "$ROOT" "$THRESH" <<'PY'
import json,sys,os
root,thresh=sys.argv[1],int(sys.argv[2])
seats=json.load(open(os.path.join(root,'.fable-team','seats.json')))
alive={k for k,v in seats.items() if isinstance(v,dict) and v.get('role')!='stop-ready'}
pend={}
mb=os.path.join(root,'.fable-team','comm','mailbox.jsonl')
if os.path.exists(mb):
    for ln in open(mb,encoding='utf-8',errors='replace'):
        ln=ln.strip()
        if not ln: continue
        try: r=json.loads(ln)
        except Exception: continue
        if r.get('read'): continue
        to=r.get('to')
        if to: pend[to]=pend.get(to,0)+1
# ★현역만 본다★ — 죽은 좌석 큐는 «묘지»라 매 틱 읽으면 현역 적체가 묻힌다(실측 175건/77좌석).
live_rows=sorted(((v,k) for k,v in pend.items() if v>0 and k in alive), reverse=True)
dead=sum(v for k,v in pend.items() if k not in alive)
tot=0
for v,k in live_rows:
    tot+=v
    print(f"{'*' if v>=thresh else ' '}{k} pending={v}")
print(f"TOTAL live_pending={tot} live_seats_with_queue={len(live_rows)} thresh={thresh} (묘지 {dead}건은 제외 — --all 로 전수)")
PY
