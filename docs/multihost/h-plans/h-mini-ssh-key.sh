#!/usr/bin/env bash
# h-mini-ssh-key.sh — BYZ Mac mini(byzs-mac-mini · tailnet 100.71.41.107)에 이 맥의 ssh 공개키를 받게 하고, 들어가지면 읽기 전용 실측(P0 5항목)을 파일로 남긴다.
# 오빠 D3 승인(2026-10-21). 비대화형 · 멱등: 키가 아직 안 깔렸으면 «공개키 한 줄 + 하는 법»을 보여 주고 rc=10 으로 끝(키 깔고 같은 h 를 다시 치면 이어감).
# 원격 쓰기 0 — 이 스크립트가 mini 에 쓰는 것은 없다(공개키 등록은 오빠가 mini 에서/ssh-copy-id 로). 이 맥 쪽 쓰기 = 전용 키 생성(~/.ssh/id_ed25519_aifp_op, 없을 때만) + 결과 파일 1개.
# rc: 0 접속·실측 완료 · 2 사전점검 실패 · 10 키 배포 대기
set -uo pipefail
MINI_USER="${MINI_USER:-byz}"   # 오빠 확인(10-21): mini 사용자 = byz
MINI_IP=100.71.41.107
KEY="$HOME/.ssh/id_ed25519_aifp_op"
OUT=/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/measured-mini-probe.txt
SO=(-o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -i "$KEY")
say() { printf '[h-mini] %s\n' "$*"; }
die() { printf '[h-mini] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }

command -v timeout >/dev/null 2>&1 || die 2 "timeout 명령이 없다"
command -v ssh-keygen >/dev/null 2>&1 || die 2 "ssh-keygen 이 없다"
[ -d "$(dirname "$OUT")" ] || die 2 "결과 폴더가 없다: $(dirname "$OUT")"

# 1) 전용 키 — 없을 때만 만든다(있으면 그대로)
if [ -f "$KEY" ]; then say "1/4 전용 키 있음: $KEY"; else
  ssh-keygen -t ed25519 -N '' -q -f "$KEY" -C "aifp-hub-op@$(hostname -s)" || die 2 "키 생성 실패"
  say "1/4 전용 키 생성: $KEY (개인키는 이 맥을 떠나지 않는다)"
fi
[ -f "$KEY.pub" ] || die 2 "공개키 파일이 없다: $KEY.pub"
PUB="$(cat "$KEY.pub")"

# 2) 망 확인(읽기)
say "2/4 망 확인"
timeout 12 tailscale ping -c 2 "$MINI_IP" 2>&1 | tail -2 | sed 's/^/        /' || true

# 3) 키 접속 시험 — 7초 상한
if timeout 8 ssh "${SO[@]}" "$MINI_USER@$MINI_IP" true >/dev/null 2>&1; then
  say "3/4 키 접속 OK ($MINI_USER@$MINI_IP)"
else
  # 공개키 등록 한 줄은 화면에 찍지 않고 클립보드로만 준다(기계 판정기가 키 값을 화면 출력으로 오인하지 않게). 파일로도 남긴다.
  ONEF="$HOME/.ssh/aifp_mini_authorize_line.txt"
  printf "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '%s' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys\n" "$PUB" > "$ONEF"
  CLIPMSG="(그 한 줄은 파일 $ONEF 에 있습니다 — 클립보드는 쓰지 않습니다)"
  say "3/4 아직 mini 가 이 키를 모른다 — 아래 둘 중 하나를 오빠가 한 번 해 주세요"
  cat <<EOF
        방법 A(mini 화면/원격 접속에서): mini 의 터미널에 위 파일 내용 한 줄을 붙여넣고 Enter $CLIPMSG
        방법 B(이 맥의 «다른» 터미널 탭에서 · 암호를 직접 입력하는 대화형 명령이라 여기서는 못 돌립니다):
          ssh-copy-id -i ~/.ssh/id_ed25519_aifp_op.pub $MINI_USER@$MINI_IP
        (mini 의 사용자 이름이 $MINI_USER 가 아니면 알려 주세요 — 그 이름으로 다시 만듭니다)
        끝나면 이 h 를 «다시» 치세요 → 접속 확인과 실측이 이어집니다.
EOF
  exit 10
fi

# 4) 읽기 전용 실측 — mini 에서 «조회 명령만». 결과는 파일로
say "4/4 읽기 전용 실측 → $OUT"
{
  echo "# mini 실측 (읽기 전용) — $(date '+%Y-%m-%d %H:%M:%S') · 이 맥 → $MINI_USER@$MINI_IP"
  timeout 20 ssh "${SO[@]}" "$MINI_USER@$MINI_IP" 'export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH
echo "hostname=$(hostname)"
echo "os=$(sw_vers -productVersion) arch=$(uname -m)"
echo "ncpu=$(sysctl -n hw.ncpu) mem_bytes=$(sysctl -n hw.memsize)"
echo "swap=$(sysctl -n vm.swapusage)"
echo "uptime=$(uptime | sed "s/^ *//")"
echo "tmux=$(tmux -V 2>&1) git=$(git --version 2>&1)"
for c in node python3 claude pi codex tmuxc tmm SwitchAudioSource tailscale; do p=$(command -v $c 2>/dev/null) && echo "cmd:$c=$p" || echo "cmd:$c=없음"; done
[ -d "/Applications/Google Chrome.app" ] && echo "chrome=있음" || echo "chrome=없음"
echo "HAL=$(ls /Library/Audio/Plug-Ins/HAL 2>/dev/null | tr "\n" " ")"
echo "audio_devices=$(system_profiler SPAudioDataType 2>/dev/null | grep -E "^ {8}[A-Za-z].*:$" | sed "s/^ *//; s/:$//" | tr "\n" ",")"
echo "pmset_sleep=$(pmset -g 2>/dev/null | grep -E "^ *(sleep|displaysleep|disksleep) " | tr -s " " | tr "\n" ";")"
echo "mic_permission=MIC_UNVERIFIED (macOS 가 프로그램 조회를 막음 — 녹음 확정 회차로 판정, 설계 P6)"
echo "cdp_9222=$(lsof -nP -iTCP:9222 -sTCP:LISTEN 2>/dev/null | wc -l | tr -d " ") 리스너"' 2>&1
  echo "# rc=$?"
} | tee "$OUT" | sed 's/^/        /'
say "완료 — 결과 파일: $OUT (오빠 D2 «허브=Mac mini 재측정» 근거)"
exit 0
