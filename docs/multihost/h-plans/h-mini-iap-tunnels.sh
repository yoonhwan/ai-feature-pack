#!/usr/bin/env bash
# h-mini-iap-tunnels.sh — h-B: mini 가 «자기 IAP 터널» 을 갖게 한다(이 맥 역방향 포워딩 의존을 걷어내는 첫 단계). 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1
#   (2026-10-22 · aifp-multihost-master-claude#2 · 상위 #3242 (b) · 키 = h7 이 mini ~/.config/byz-tunnel/sa.json 에 둔 byz-mini-tunnel 새 서비스 계정)
#   하는 일(mini 안 · GCP 쓰기 0 · sudo 0):
#     ① gcloud CLI 587.0.0(이 맥과 같은 버전) 사용자 설치 → ~/.local/share/gcloud-587/google-cloud-sdk — tarball 은 mini 가 직접 받아 sha256 대조(고정값)
#     ② 전용 설정 폴더 ~/.config/byz-tunnel/cfg 에서 byz-mini-tunnel 활성화(다른 계정·기본 설정과 섞이지 않음)
#     ③ launchd 사용자 에이전트 2개 상주(KeepAlive): com.byz.iap-tunnel-llm (llm-dev:8000) · com.byz.iap-tunnel-stt (stt-tts-dev:8000)
#        ★이번 단계의 mini 쪽 포트는 «시험용» 18703·18708★ — 운영 포워딩(8000·8001)과 겹치지 않는다. 8000/8001 로 바꾸는 건 다음 단계(h-B2: 포워딩 8000·8001 끄기 + 이 에이전트 포트 교체)
#     ④ 증거: 두 포트 LISTEN · 각 /health 응답 · ★STT 동등성★: mini 18708(IAP → stt-tts-dev:8000) 응답 본문과 이 맥 8001(ssh -L → VM localhost:8000) 응답 본문이 같은지(DA r1 ④ 해소)
# rc: 0 성공 · 2 사전점검 실패 · 3 설치 실패 · 4 터널/증거 실패(설치물은 남김 — 롤백 안내)
# ★롤백은 «삭제» 라 사람(HIL) 승인 — 이 스크립트가 지우지 않는다:
#   ssh mini 'for l in llm stt; do launchctl bootout gui/$(id -u)/com.byz.iap-tunnel-$l; rm -f ~/Library/LaunchAgents/com.byz.iap-tunnel-$l.plist; done; rm -rf ~/.local/share/gcloud-587 ~/.config/byz-tunnel/cfg ~/.config/byz-tunnel/run-tunnel.sh'
set -uo pipefail

MINI="${MINI:-mini}"; DRY="${DRY:-0}"
P="${P:-byz-agents-484214}"; Z="${Z:-asia-northeast3-a}"
SA="byz-mini-tunnel@$P.iam.gserviceaccount.com"
VER=587.0.0
URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-$VER-darwin-arm.tar.gz"
SHA256=088d923d11dd5f922bfdf0ff12fc8a94934264e32a57c0cd3afc24ce7bfa5452   # 이 맥에서 같은 URL 을 받아 계산한 값(53973848 bytes · 2026-10-22)
PORT_LLM="${PORT_LLM:-18703}"; PORT_STT="${PORT_STT:-18708}"
MAC_STT_PORT="${MAC_STT_PORT:-8001}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-B] %s\n' "$*"; }
die() { printf '[h-B] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }
SDK='$HOME/.local/share/gcloud-587/google-cloud-sdk'

say "0/4 사전점검 (DRY=$DRY · 시험 포트 llm=$PORT_LLM stt=$PORT_STT)"
case "$PORT_LLM$PORT_STT" in *[!0-9]*) die 2 "포트는 숫자만";; esac
PRE="$(ms 20 'echo "sa_json=$(test -s $HOME/.config/byz-tunnel/sa.json && stat -f %Lp $HOME/.config/byz-tunnel/sa.json || echo NONE)"
echo "py313=$(test -x /opt/homebrew/bin/python3.13 && echo yes || echo NO)"
echo "sdk=$(test -x '"$SDK"'/bin/gcloud && '"$SDK"'/bin/gcloud --version 2>/dev/null | head -1 || echo none)"
echo "free_gb=$(df -g $HOME | tail -1 | awk "{print \$4}")"
for p in '"$PORT_LLM"' '"$PORT_STT"'; do echo "busy_$p=$(lsof -nP -iTCP:$p -sTCP:LISTEN 2>/dev/null | wc -l | tr -d " ")"; done
echo "agents=$(launchctl list 2>/dev/null | grep -c com.byz.iap-tunnel)"' 2>&1)" || die 2 "mini 접속 실패"
printf '%s\n' "$PRE" | sed 's/^/        /'
get() { printf '%s\n' "$PRE" | sed -n "s/^$1=//p" | head -1; }
[ "$(get sa_json)" = 600 ] || die 2 "mini ~/.config/byz-tunnel/sa.json 이 없거나 권한이 600 이 아니다(h7 먼저)"
[ "$(get py313)" = yes ] || die 2 "mini 에 homebrew python3.13 없음 — gcloud 가 쓸 파이썬이 필요"
[ "${P:-}" ] && [ "$(get free_gb)" -ge 3 ] 2>/dev/null || die 2 "mini 디스크 여유 3GB 미만"
[ "$(get busy_$PORT_LLM)" = 0 ] && [ "$(get busy_$PORT_STT)" = 0 ] || die 2 "시험 포트가 mini 에서 이미 사용 중이다"
[ "$(get agents)" = 0 ] || say "        ⚠️ 이미 com.byz.iap-tunnel 에이전트가 $(get agents)개 있다 — 같은 이름이면 교체(bootout 후 bootstrap)"
curl --noproxy '*' -s -o /dev/null -m 7 -w '%{http_code}' "http://127.0.0.1:$MAC_STT_PORT/health" | grep -q 200 || die 2 "이 맥 127.0.0.1:$MAC_STT_PORT(STT 기준 경로) health 가 200 이 아니다 — 동등성 비교 불가"
if [ "$DRY" = 1 ]; then
  say "DRY — 하려던 일(쓰기 0): ① gcloud $VER 설치(sha256 ${SHA256:0:12}…) ② byz-mini-tunnel 활성화 ③ launchd 2개(${PORT_LLM}→llm-dev:8000 · ${PORT_STT}→stt-tts-dev:8000) ④ 증거 + STT 동등성"
  exit 0
fi

# ── 1) gcloud 설치(없을 때만 · 분리 실행 + 폴링) ──────────────────────────────
if [ "$(get sdk)" = none ]; then
  say "1/4 gcloud $VER 사용자 설치(mini 가 직접 받음 · 분리 실행)"
  ms 15 "mkdir -p \$HOME/.local/share/gcloud-587 && nohup setsid bash -c 'set -e; cd \$HOME/.local/share/gcloud-587; curl -sSf -o sdk.tgz \"$URL\"; echo \"$SHA256  sdk.tgz\" | shasum -a 256 -c - > sha.out 2>&1; tar -xzf sdk.tgz; rm -f sdk.tgz; echo DONE > done.flag' >\$HOME/.local/share/gcloud-587/install.log 2>&1 </dev/null & echo started" >/dev/null || die 3 "설치 시작 실패"
  OK=0
  for i in $(seq 1 60); do   # 60 × 5초 = 5분 상한(분리 실행이라 호출은 매번 ≤7초)
    sleep 5
    ST="$(ms 7 'cd $HOME/.local/share/gcloud-587 2>/dev/null && { test -f done.flag && echo DONE || { pgrep -f "[g]cloud-587" >/dev/null && echo RUN || echo STOP; }; }' 2>&1)" || ST=SSH
    case "$ST" in DONE) OK=1; break;; STOP) break;; esac
  done
  [ "$OK" = 1 ] || { ms 7 'tail -3 $HOME/.local/share/gcloud-587/install.log; cat $HOME/.local/share/gcloud-587/sha.out 2>/dev/null' 2>&1 | sed 's/^/        /'; die 3 "gcloud 설치가 끝나지 않았거나 실패(sha 불일치 포함) — 로그 위"; }
  ms 7 'cat $HOME/.local/share/gcloud-587/sha.out' 2>&1 | sed 's/^/        /'
  ms 20 "$SDK/bin/gcloud --version 2>&1 | head -1" 2>&1 | sed 's/^/        /'
else
  say "1/4 gcloud 이미 설치됨($(get sdk)) — 건너뜀"
fi

# ── 2) 터널 실행 스크립트 + 활성화 + launchd ─────────────────────────────────
say "2/4 전용 설정 폴더에서 $SA 활성화 · 터널 실행 스크립트"
ms 40 "set -e; umask 077; mkdir -p \$HOME/.config/byz-tunnel/cfg
cat > \$HOME/.config/byz-tunnel/run-tunnel.sh <<'RT'
#!/bin/bash
# run-tunnel.sh <instance> <remote-port> <local-port> — launchd 가 호출. 환경을 비우고 byz-mini-tunnel 로만 터널을 연다.
exec /usr/bin/env -i HOME=\"\$HOME\" LANG=C PATH=/opt/homebrew/bin:/usr/bin:/bin \\
  CLOUDSDK_CONFIG=\"\$HOME/.config/byz-tunnel/cfg\" CLOUDSDK_PYTHON=/opt/homebrew/bin/python3.13 \\
  \"\$HOME/.local/share/gcloud-587/google-cloud-sdk/bin/gcloud\" --project=$P --account=$SA \\
  compute start-iap-tunnel \"\$1\" \"\$2\" --local-host-port=127.0.0.1:\"\$3\" --zone=$Z
RT
chmod 700 \$HOME/.config/byz-tunnel/run-tunnel.sh
env -i HOME=\"\$HOME\" LANG=C PATH=/opt/homebrew/bin:/usr/bin:/bin CLOUDSDK_CONFIG=\$HOME/.config/byz-tunnel/cfg CLOUDSDK_PYTHON=/opt/homebrew/bin/python3.13 \$HOME/.local/share/gcloud-587/google-cloud-sdk/bin/gcloud auth activate-service-account $SA --key-file=\$HOME/.config/byz-tunnel/sa.json 2>&1 | tail -1" 2>&1 | sed 's/^/        /' || die 3 "활성화 실패"

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
HOMEDIR="$(ms 7 'echo $HOME')" || die 3 "홈 조회 실패"
[ "$HOMEDIR" = /Users/byz ] || die 3 "mini 홈이 /Users/byz 가 아니다($HOMEDIR) — plist 경로 점검"
say "3/4 launchd 에이전트 2개 상주"
for spec in "llm|byz-agents-gce-llm-dev|8000|$PORT_LLM" "stt|byz-agents-gce-stt-tts-dev|8000|$PORT_STT"; do
  IFS='|' read -r nm inst rp lp <<<"$spec"; lab="com.byz.iap-tunnel-$nm"
  mkplist "$lab" "$inst" "$rp" "$lp" | ms 20 "cat > \$HOME/Library/LaunchAgents/$lab.plist && chmod 644 \$HOME/Library/LaunchAgents/$lab.plist && plutil -lint \$HOME/Library/LaunchAgents/$lab.plist >/dev/null" || die 3 "$lab plist 쓰기 실패"
  ms 20 "launchctl bootout gui/\$(id -u)/$lab 2>/dev/null; launchctl bootstrap gui/\$(id -u) \$HOME/Library/LaunchAgents/$lab.plist && echo bootstrapped" 2>&1 | sed "s/^/        $lab /" || die 3 "$lab bootstrap 실패"
done

# ── 4) 증거 ──────────────────────────────────────────────────────────────────
say "4/4 증거 — 두 포트 LISTEN · health · STT 동등성(조건부 IAM·터널 시작에 최대 ~1분)"
FAIL=0
for spec in "llm|$PORT_LLM" "stt|$PORT_STT"; do
  IFS='|' read -r nm lp <<<"$spec"; ok=0
  for i in $(seq 1 12); do sleep 5; n="$(ms 7 "lsof -nP -iTCP:$lp -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' '" 2>/dev/null)" || n=0; [ "${n:-0}" -ge 1 ] 2>/dev/null && { ok=1; break; }; done
  if [ "$ok" = 1 ]; then c="$(ms 10 "curl -s -o /dev/null -w '%{http_code}' -m 6 http://127.0.0.1:$lp/health" 2>/dev/null)"; say "        $nm 포트 $lp LISTEN · /health HTTP $c"; [ "$c" = 200 ] || FAIL=1
  else say "        $nm 포트 $lp ❌ 60초 안에 LISTEN 안 됨 — /tmp/com.byz.iap-tunnel-$nm.log: $(ms 7 "tail -2 /tmp/com.byz.iap-tunnel-$nm.log | tr '\n' ' ' | cut -c1-200" 2>/dev/null)"; FAIL=1; fi
done
MB="$(ms 10 "curl -s -m 6 http://127.0.0.1:$PORT_STT/health | shasum -a 256 | cut -c1-16" 2>/dev/null)"
AB="$(curl --noproxy '*' -s -m 6 "http://127.0.0.1:$MAC_STT_PORT/health" | shasum -a 256 | cut -c1-16)"
if [ -n "$MB" ] && [ "$MB" = "$AB" ]; then say "        STT 동등성 ✅ mini IAP(stt-tts-dev:8000) 응답 == 이 맥 ssh -L 경로 응답(sha ${MB})"
else say "        STT 동등성 ⚠️ 응답 본문 불일치(mini=${MB:-없음} mac=${AB}) — 시간·상태 필드 때문일 수 있다. 본문 비교: ssh mini 'curl -s http://127.0.0.1:$PORT_STT/health'"; FAIL=1; fi
if [ "$FAIL" = 0 ]; then say "완료 rc=0 — mini 자체 IAP 터널 상주(시험 포트). 다음: h-B2(8000·8001 교체)"; exit 0; fi
say "일부 실패 rc=4 — 에이전트·설치물은 남김. 롤백은 헤더(사람 승인)"; exit 4
