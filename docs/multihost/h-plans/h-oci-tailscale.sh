#!/usr/bin/env bash
# h-oci-tailscale.sh — OCI(ssh 별칭 oci)에 Tailscale 설치 + 로그인(브라우저 승인 1회). 오빠 D4 승인(2026-10-21).
# 비대화형(프롬프트 0) · 멱등(이미 된 단계는 건너뜀 · 다시 쳐도 이어감) · 인증키 파일/값 0(방식 A: 브라우저 승인).
# 하지 않는 것: 공인 22 닫기 · ACL 편집 · 태그 광고(tagOwners 가 콘솔에 없으면 up 이 실패한다 → 콘솔 설정 뒤 별도) · 키 만료 끄기(콘솔).
# 롤백: 끝에 출력. rc: 0 성공 · 2 사전점검 실패 · 3 설치 실패 · 4 로그인 승인 안 됨(다시 치면 이어감) · 5 사후점검 실패
set -uo pipefail
R=oci
HN=aifp-oci-jarvis
KEY="$HOME/.ssh/oci_chuncheon"
SO=(-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)
say() { printf '[h-oci] %s\n' "$*"; }
die() { printf '[h-oci] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$R" "$@"; }   # 원격 1회 호출 = 상한 t초

# 0) 로컬 사전점검
command -v timeout >/dev/null 2>&1 || die 2 "timeout 명령이 없다"
[ -f "$KEY" ] || die 2 "ssh 키 파일이 없다: $KEY"
ssh -G "$R" 2>/dev/null | grep -q '^hostname ' || die 2 "ssh 별칭 $R 이 없다"
command -v tailscale >/dev/null 2>&1 || die 2 "이 맥에 tailscale CLI 가 없다"

# 1) 원격 사전점검 — 읽기만
say "1/5 사전점검(읽기 전용)"
PRE="$(rs 12 'echo "arch=$(uname -m)"; . /etc/os-release; echo "codename=$VERSION_CODENAME"; sudo -n true >/dev/null 2>&1 && echo sudo=ok || echo sudo=NO; command -v tailscale >/dev/null 2>&1 && echo ts=present || echo ts=absent' 2>&1)" || die 2 "oci 접속 실패: $PRE"
echo "$PRE" | sed 's/^/        /'
echo "$PRE" | grep -q '^arch=aarch64$'    || die 2 "aarch64 가 아니다"
echo "$PRE" | grep -q '^codename=jammy$'  || die 2 "Ubuntu jammy(22.04)가 아니다 — 저장소 주소가 다르다"
echo "$PRE" | grep -q '^sudo=ok$'         || die 2 "무암호 sudo 가 안 된다"

# 2) 설치 — 이미 있으면 건너뜀. 기존 서비스는 재시작하지 않는다(NEEDRESTART_MODE=l = 목록만)
if echo "$PRE" | grep -q '^ts=present$'; then
  say "2/5 설치: 이미 있음 — 건너뜀"
else
  say "2/5 설치 ① 서명키·저장소 등록"
  rs 25 'set -e
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
echo keyring+list=ok' || die 3 "저장소 등록 실패(되돌리기: sudo rm /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg)"
  say "2/5 설치 ② apt-get update"
  rs 70 'sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get update -qq && echo update=ok' || die 3 "apt-get update 실패/시간 초과"
  say "2/5 설치 ③ apt-get install tailscale"
  rs 70 'sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y -qq tailscale >/dev/null && echo install=ok' || die 3 "설치 실패/시간 초과(되돌리기: sudo apt-get remove -y tailscale)"
fi
V="$(rs 10 'tailscale version | head -1; echo "tailscaled=$(systemctl is-active tailscaled)"' 2>&1)" || die 3 "설치 확인 실패: $V"
echo "$V" | sed 's/^/        /'

# 3) 로그인 — 방식 A(브라우저 승인). up 은 7초만 기다리고 URL 만 받는다 → 상태를 7초 간격으로 확인
state() { rs 12 'sudo -n tailscale status --json 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get(\"BackendState\",\"\"),d.get(\"AuthURL\",\"\"))"' 2>/dev/null; }
S="$(state || true)"
if [ "${S%% *}" = "Running" ]; then
  say "3/5 로그인: 이미 Running — 건너뜀"
else
  say "3/5 로그인: up 시작(7초 상한)"
  rs 14 "sudo -n tailscale up --hostname=$HN --ssh=false --accept-dns=false --timeout=7s" >/dev/null 2>&1 || true
  URL=""; ok=0
  for i in $(seq 1 40); do                       # 최대 약 5분. 매 확인은 7초 상한 ssh 1회
    S="$(state || true)"
    case "${S%% *}" in
      Running) ok=1; break ;;
      NeedsLogin|NeedsMachineAuth)
        U="${S#* }"
        if [ -n "$U" ] && [ "$U" != "$URL" ]; then URL="$U"; say "        ▶ 오빠 손 1회: 브라우저에서 이 주소를 열어 로그인·승인(같은 계정 yoonhwan.ko@gmail.com tailnet): $URL"; fi ;;
    esac
    sleep 7
  done
  [ "$ok" = 1 ] || die 4 "승인이 확인되지 않았다 — 승인 후 같은 h 를 다시 치면 이어간다"
fi

# 4) 사후점검 — 읽기만 + 이 맥에서 tailnet 주소로 ssh 왕복
say "4/5 사후점검"
IP4="$(rs 10 'sudo -n tailscale ip -4 | head -1' 2>/dev/null | tr -d '\r')"
[[ "$IP4" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 5 "tailnet 주소를 못 읽었다: '$IP4'"
say "        oci tailnet 주소 = $IP4"
rs 10 'echo "sshd 22 리스너 수=$(ss -ltn | grep -c ":22 ")"; echo "tailscaled=$(systemctl is-active tailscaled) enabled=$(systemctl is-enabled tailscaled)"' 2>&1 | sed 's/^/        /'
timeout 12 tailscale ping -c 2 "$IP4" 2>&1 | tail -2 | sed 's/^/        /' || true
T0=$(date +%s)
if timeout 8 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$KEY" "ubuntu@$IP4" true >/dev/null 2>&1; then
  say "        ssh ubuntu@$IP4 (tailnet) rc=0 · $(( $(date +%s) - T0 ))초"
else
  die 5 "tailnet 주소로 ssh 가 안 된다(공인 접속은 그대로 살아 있다 — oci 별칭으로 확인). ACL·방화벽 확인 필요"
fi

# 5) 마무리 안내
say "5/5 끝 — 설치·로그인 완료"
cat <<EOF
        남은 오빠 손(콘솔 · Tailscale admin → Machines):
          ① $HN 의 «Disable key expiry» 켜기(서버라 키 만료로 조용히 끊기지 않게)
          ② 태그·ACL(tag:aifp 같은 기계끼리 22/tcp 만)은 tagOwners 정의 뒤 — 이 h 는 태그를 광고하지 않았다
        롤백(필요할 때만): ssh oci 'sudo tailscale down && sudo systemctl disable --now tailscaled'  ·  완전 제거: sudo apt-get remove -y tailscale
EOF
exit 0
