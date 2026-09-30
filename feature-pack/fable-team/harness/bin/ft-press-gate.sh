#!/usr/bin/env bash
# press 전 게이트 — 「랜딩+재기동 전에는 press 에 아무 반영이 없다」를 물리적으로 막는다.
# 왜: 2026-09-17 밤, 나노가 각자 nano/* 브랜치에서 고친 것을 feat 에 랜딩하지 않은 채
#     2시간 동안 발화를 돌렸다. 회차는 전부 「반영 0」인 서버에서 났고 분모만 늘었다.
#     같은 밤 재기동에서 화면(FE)만 1시간 뒤처져 회차가 또 오염됐다.
#     규칙에 네 번 적었고 네 번 빠뜨렸다 — 기억이 아니라 종료코드로 막는다.
# 쓰기: ft-press-gate.sh   → 통과 0 / 막힘 1. tester 는 이걸 통과해야만 쏜다.
set -u
WT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live
ROOT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
cd "$WT" || exit 1
FAIL=0
say(){ printf '%s %s\n' "$1" "$2"; }

# ① 현역 나노 브랜치 미랜딩 0
UNLANDED=0
# ★현역 좌석이 붙어 있는 워크트리만 본다★ — 죽은 좌석 워크트리의 옛 커밋은 press 와 무관하다
LIVE_WT=$(python3 -c "
import json,subprocess,re
d=json.load(open('$ROOT/.fable-team/seats.json'))
live=set(subprocess.run(['tmux','list-sessions','-F','#{session_name}'],capture_output=True,text=True).stdout.split())
out=set()
for k,v in d.items():
    if not isinstance(v,dict) or v.get('role')=='stop-ready' or k not in live: continue
    m=re.match(r'ft-v65-temp-(.+?)#\\d+$',k) or re.match(r'ft-v65-(mr|le)-track#\\d+$',k)
    if m: out.add('v65-'+m.group(1))
print(' '.join(sorted(out)))" 2>/dev/null)
for W in $LIVE_WT; do
  W="$ROOT/.worktrees/$W"
  [ -e "$W/.git" ] || continue
  N=$(git -C "$W" log --oneline feat/v6-realtime-live..HEAD 2>/dev/null | wc -l | tr -d ' ')
  # 제품 경로를 건드린 미랜딩만 센다(문서만이면 press 에 영향 0)
  # ★cherry-pick -x 로 이미 feat 에 올라간 것은 «미랜딩이 아니다»★ — 원본 sha 는 조상이 아니므로
  # 제목으로 대조한다(이 오탐 때문에 9건이 미랜딩으로 잡혔다).
  # ★테스트 파일은 실행 번들에 영향 0★ 이라 제품 경로에서 뺀다.
  # 랜딩 판정 셋 — 하나라도 맞으면 랜딩된 것으로 본다:
  #   ⒜같은 제목이 feat 에 있다(cherry-pick -x)
  #   ⒝feat 커밋 «본문»에 그 sha 가 인용돼 있다(통행증 규격으로 «재작성»해 올린 경우 — 실제로 있었다)
  #   ⒞sha 가 feat 의 조상이다
  P=0
  FEAT_SUBJ=$(git log feat/v6-realtime-live --format='%s' -400)
  FEAT_BODY=$(git log feat/v6-realtime-live --format='%H%n%B' -60)
  while IFS=$'\t' read -r h t; do
    [ -z "$h" ] && continue
    printf '%s\n' "$FEAT_SUBJ" | grep -qxF "$t" && continue
    printf '%s\n' "$FEAT_BODY" | grep -q "${h:0:9}" && continue
    git merge-base --is-ancestor "$h" feat/v6-realtime-live 2>/dev/null && continue
    P=$((P+1)); say "  ·" "미랜딩 후보: $t"
  done < <(git -C "$W" log --format='%H%t%s' feat/v6-realtime-live..HEAD -- worker shared gateway clients ':(exclude)*__tests__*' ':(exclude)tests/*' 2>/dev/null | sed 's/\(^[0-9a-f]*\)/\1\t/' )
  [ "${P:-0}" != "0" ] && { say "✗" "미랜딩 제품 커밋 $P — $(basename "$W")"; UNLANDED=$((UNLANDED+P)); }
done
[ "$UNLANDED" = "0" ] && say "✓" "미랜딩 제품 커밋 0" || FAIL=1

# ② 워커·관문·화면 기동시각 > 각자의 최신 제품 커밋
chk(){ # 이름 포트 경로들
  local name=$1 port=$2; shift 2
  local pid ep cp
  pid=$(lsof -ti:"$port" -sTCP:LISTEN 2>/dev/null | head -1)
  [ -z "$pid" ] && { say "✗" "$name 리스너 없음(:$port)"; FAIL=1; return; }
  ep=$(python3 -c "
import subprocess,datetime,re
o=subprocess.run(['ps','-o','lstart=','-p','$pid'],capture_output=True,text=True).stdout.strip()
m=re.search(r'(\\d{1,2})/\\s*(\\d{1,2})\\s+(\\d{2}):(\\d{2}):(\\d{2})\\s+(\\d{4})',o)
if m:
    mo,dd,hh,mi,ss,yy=map(int,m.groups())
    print(int(datetime.datetime(yy,mo,dd,hh,mi,ss).timestamp()))
else:
    try: print(int(datetime.datetime.strptime(' '.join(o.split()),'%a %b %d %H:%M:%S %Y').timestamp()))
    except Exception: print('')" 2>/dev/null)
  cp=$(git log -1 --format=%ct -- "$@" 2>/dev/null)
  if [ -n "$ep" ] && [ -n "$cp" ] && [ "$ep" -gt "$cp" ]; then
    say "✓" "$name pid=$pid 기동 > 최신 커밋($(date -r "$cp" '+%m-%d %H:%M:%S'))"
  else
    say "✗" "$name pid=$pid 기동이 최신 커밋보다 «앞»선다 — 재기동 필요"; FAIL=1
  fi
}
chk worker 8081 worker shared
chk gateway 8080 gateway shared
chk 화면 3001 clients/web ":(exclude)clients/web/__tests__/*"

# ③ 활성화 lane + health
grep -q 'activation bundle established' /tmp/byz-worker.log \
  && say "✓" "[C2c-ACT] activation bundle established" \
  || { say "✗" "활성화 번들 줄 없음 — legacy lane 의심"; FAIL=1; }
code=$(curl -s -m 4 -o /dev/null -w '%{http_code}' http://localhost:8081/health 2>/dev/null)
[ "$code" = "200" ] && say "✓" "worker health 200" || { say "✗" "worker health=$code"; FAIL=1; }
# HTTP 200 이어도 본문 consumer_ready=false 면 PTT disabled — press 가 no_viable_target 으로 무효(2026-09-26 long3m-002)
cr=$(curl -s -m 4 http://localhost:8081/health 2>/dev/null | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("unparsed"); sys.exit()
print("ok" if d.get("consumer_ready") is True else "status=%s consumer_ready=%s" % (d.get("status"), d.get("consumer_ready")))' 2>/dev/null)
[ "$cr" = "ok" ] && say "✓" "worker consumer_ready=true" || { say "✗" "worker ${cr:-unparsed} — LOOM DSN·언어 웜업 먼저(troubleshoot 20260926-local-worker)"; FAIL=1; }

# ④ 워커 필수 env(WORKER_ENV_SPEC 키 이름만 대조 · 값 복제 0)
wpid=$(lsof -ti:8081 -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$wpid" ]; then
  miss=0
  while read -r k; do
    ps eww "$wpid" 2>/dev/null | tr ' ' '\n' | grep -q "^${k}=" || { say "✗" "env 없음: $k"; miss=$((miss+1)); }
  done < <(sed -n '/^WORKER_ENV_SPEC=(/,/^)/p' scripts/server/ready-check.sh | grep -oE '"[A-Z0-9_]+=' | tr -d '"=')
  [ "$miss" = "0" ] && say "✓" "필수 env 전부 실림" || FAIL=1
fi

echo
[ "$FAIL" = "0" ] && { echo "PRESS-GATE PASS — 발화해도 된다"; exit 0; }
echo "PRESS-GATE BLOCK — 위 ✗ 를 먼저 닫아라(랜딩 → stop→run → 화면도 같이)"; exit 1
