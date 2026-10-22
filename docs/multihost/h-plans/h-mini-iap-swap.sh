#!/usr/bin/env bash
# h-mini-iap-swap.sh — h-B2: mini 의 LLM·STT/TTS 길을 «이 맥 역방향 포워딩» 에서 «mini 자체 IAP 터널» 로 바꾼다. 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1
#   (2026-10-22 · aifp-multihost-master-claude#2 · 상위 #3259 ① · 전제 = h-B(h-mini-iap-tunnels.sh) rc=0)
#   방식: 서버 env 를 건드리지 않는다. 서버는 계속 127.0.0.1:8000(LLM)·8001(STT/TTS) 로 부르고, 그 포트의 주인만 바꾼다.
#         (상위 초안은 «서버 env 포트를 18703·18708 로 교체» 였으나 그러면 서버 재시작이 필요 — 포트 주인 교체가 서버 불변이라 더 작다.)
#   순서(DB 38309 포워딩은 ssh 한 줄에 같이 묶여 있어 ★약 10~20초 끊겼다 다시 선다★):
#     0 사전점검: h-B 증거(에이전트 2개 LISTEN 18703·18708 + health 200) · 포워딩 ssh 생존 · 서버 gateway 200
#     1 이 맥 포워딩 ssh(이 h 가 연 것만) 종료 → mini 8000·8001·38309 비어짐 확인
#     2 mini launchd 에이전트 2개 포트를 8000·8001 로 교체(plist 재작성 → bootout → bootstrap) → LISTEN·health
#     3 DB 38309 만 역방향 포워딩 재개설(FWD_EXTRA 비움)
#     4 증거: mini 8000·8001·38309 LISTEN · 각 health · 서버 gateway/web 200 · STT 동등성 · 이 맥에 8000/8001 용 -R 포워딩 0
# rc: 0 성공 · 2 사전점검 실패 · 3 교체 실패(되돌림 안내) · 4 증거 실패
# ★되돌림(사람 승인 — 에이전트 bootout/plist 삭제 포함)★: ① ssh mini 'for l in llm stt; do launchctl bootout gui/$(id -u)/com.byz.iap-tunnel-$l; done' ② bash /tmp/h18 (옛 포워딩 8000 8001 38309 전부 재개설)
#      plist 는 18703/18708 로 되돌릴 필요 없음(재실행 때 이 h 가 다시 씀).
set -uo pipefail
MINI="${MINI:-mini}"; DRY="${DRY:-0}"
HDIR="/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/h-plans"
TUN_PIDF="$HOME/.h-byz-tunnel.pid"
P_LLM_OLD=18703; P_STT_OLD=18708
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-B2] %s\n' "$*"; }
die() { printf '[h-B2] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }
lsn() { ms 10 "lsof -nP -iTCP:$1 -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' '" 2>/dev/null; }
code() { ms 12 "curl -s -L -o /dev/null -w '%{http_code}' -m 6 http://127.0.0.1:$1$2" 2>/dev/null; }

say "0/4 사전점검 (DRY=$DRY)"
[ "$(lsn $P_LLM_OLD)" -ge 1 ] 2>/dev/null && [ "$(lsn $P_STT_OLD)" -ge 1 ] 2>/dev/null || die 2 "mini 시험 터널 ${P_LLM_OLD}·$P_STT_OLD 가 LISTEN 이 아니다 — h-B(h-mini-iap-tunnels.sh) 먼저"
[ "$(code $P_LLM_OLD /health)" = 200 ] && [ "$(code $P_STT_OLD /health)" = 200 ] || die 2 "mini 시험 터널 health 가 200 이 아니다 — h-B 증거 먼저"
[ "$(code 38312 /health)" = 200 ] || die 2 "mini 서버 gateway(38312) health 200 아님 — 서버가 떠 있어야 교체 전후를 비교할 수 있다"
tp="$(cat "$TUN_PIDF" 2>/dev/null)"
if [ -n "$tp" ] && kill -0 "$tp" 2>/dev/null && ps -o args= -p "$tp" 2>/dev/null | grep -q -- "-R 127.0.0.1:"; then
  say "        이 맥 포워딩 ssh 생존 (pid $tp): $(ps -o args= -p "$tp" | grep -o -- '-R 127.0.0.1:[0-9]*' | tr '\n' ' ')"
else
  tp=""; say "        이 맥 포워딩 ssh 없음(이미 죽음) — 1단계 종료는 건너뛴다"
fi
HAS_OLD="$( [ "$(lsn 8000)" -ge 1 ] 2>/dev/null && echo yes || echo no )"
say "        mini 8000 LISTEN=$(lsn 8000) 8001=$(lsn 8001) 38309=$(lsn 38309) (교체 전)"
MB="$(ms 10 "curl -s -m 6 http://127.0.0.1:$P_STT_OLD/health | shasum -a 256 | cut -c1-16" 2>/dev/null)"
if [ "$DRY" = 1 ]; then
  say "DRY — 하려던 일(쓰기 0): 1 포워딩 ssh ${tp:-없음} 종료 → 2 mini 에이전트 2개 포트 ${P_LLM_OLD}→8000 · ${P_STT_OLD}→8001 교체 → 3 DB 38309 만 포워딩 재개설 → 4 증거(STT 동등성 기준 sha ${MB:-없음})"
  exit 0
fi

say "1/4 이 맥 포워딩 ssh 종료(이 h 계열이 연 것만)"
[ -n "$tp" ] && { kill "$tp" 2>/dev/null; rm -f "$TUN_PIDF"; }
for i in $(seq 1 12); do sleep 3; [ "$(lsn 8000)$(lsn 8001)$(lsn 38309)" = 000 ] && break; done
[ "$(lsn 8000)$(lsn 8001)$(lsn 38309)" = 000 ] || die 3 "mini 8000·8001·38309 가 비워지지 않았다(mini sshd 자식 정리 지연 — 1분 뒤 같은 h 다시)"
say "        mini 8000·8001·38309 비어짐"

say "2/4 mini 에이전트 포트 교체 (${P_LLM_OLD}→8000 · ${P_STT_OLD}→8001)"
mkplist() {  # mkplist <label> <inst> <rport> <lport>
  cat <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$1</string>
<key>ProgramArguments</key><array><string>/Users/byz/.config/byz-tunnel/run-tunnel.sh</string><string>$2</string><string>$3</string><string>$4</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>30</integer>
<key>StandardOutPath</key><string>/tmp/$1.log</string><key>StandardErrorPath</key><string>/tmp/$1.log</string>
</dict></plist>
PL
}
for spec in "llm|byz-agents-gce-llm-dev|8000|8000" "stt|byz-agents-gce-stt-tts-dev|8000|8001"; do
  IFS='|' read -r nm inst rp lp <<<"$spec"; lab="com.byz.iap-tunnel-$nm"
  mkplist "$lab" "$inst" "$rp" "$lp" | ms 20 "cat > \$HOME/Library/LaunchAgents/$lab.plist.new && plutil -lint \$HOME/Library/LaunchAgents/$lab.plist.new >/dev/null && mv \$HOME/Library/LaunchAgents/$lab.plist.new \$HOME/Library/LaunchAgents/$lab.plist" || die 3 "$lab plist 쓰기 실패 — 되돌림: 헤더"
  ms 20 "launchctl bootout gui/\$(id -u)/$lab 2>/dev/null; launchctl bootstrap gui/\$(id -u) \$HOME/Library/LaunchAgents/$lab.plist && echo bootstrapped" 2>&1 | sed "s/^/        $lab /" || die 3 "$lab bootstrap 실패 — 되돌림: 헤더"
done
FAIL=0
for lp in 8000 8001; do
  ok=0; for i in $(seq 1 12); do sleep 5; [ "$(lsn $lp)" -ge 1 ] 2>/dev/null && { ok=1; break; }; done
  [ "$ok" = 1 ] && say "        mini $lp LISTEN (자체 IAP 터널)" || { say "        mini $lp ❌ 60초 안에 LISTEN 안 됨 — /tmp/com.byz.iap-tunnel-*.log"; FAIL=1; }
done
[ "$FAIL" = 0 ] || die 3 "자체 터널이 8000/8001 에 서지 않았다 — 되돌림(사람 승인): 헤더. 서버는 LLM/STT 를 잃은 상태"

say "3/4 DB 38309 만 역방향 포워딩 재개설"
FWD_EXTRA="" bash "$HDIR/h-mini-byz-fwd-run.sh" 2>&1 | sed 's/^/        /' || true
[ "$(lsn 38309)" -ge 1 ] 2>/dev/null || die 3 "38309 포워딩이 서지 않았다 — 서버가 DB 를 잃은 상태. bash /tmp/h18 로 복구 시도(사람)"

say "4/4 증거"
FAIL=0
for pc in "8000 /health" "8001 /health" "38312 /health" "38314 /"; do set -- $pc; c="$(code $1 $2)"; say "        mini :$1$2 HTTP $c"; [ "$c" = 200 ] || FAIL=1; done
MB2="$(ms 10 "curl -s -m 6 http://127.0.0.1:8001/health | shasum -a 256 | cut -c1-16" 2>/dev/null)"
[ -n "$MB2" ] && [ "$MB2" = "$MB" ] && say "        STT 동등성 ✅ 교체 전 응답 sha == 교체 후 ($MB2)" || { say "        STT 동등성 ⚠️ 교체 전 ${MB:-없음} / 후 ${MB2:-없음} (상태 필드 변동일 수 있음)"; }
OLDR="$(ps -eo args= | grep -E 'ssh .*-R 127.0.0.1:(8000|8001):' | grep -v grep | wc -l | tr -d ' ')"
say "        이 맥의 8000/8001 용 -R 포워딩 프로세스: $OLDR (0 이어야 함)"
[ "$OLDR" = 0 ] || FAIL=1
if [ "$FAIL" = 0 ]; then say "완료 rc=0 — LLM·STT/TTS 는 mini 자체 IAP 터널, DB 만 이 맥 포워딩(다음: DB 경로 A2)"; exit 0; fi
say "증거 일부 실패 rc=4 — 위 줄 확인. 되돌림은 헤더(사람 승인)"; exit 4
