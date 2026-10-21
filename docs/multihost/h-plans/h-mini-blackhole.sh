#!/usr/bin/env bash
# h-mini-blackhole.sh — BYZ Mac mini(사용자 byz · tailnet 100.71.41.107)에 BlackHole 2ch + SwitchAudioSource 설치. 오빠 D13 승인(2026-10-21).
# 이 맥에서 치는 줄(! bash /tmp/h<N>)이다. 흐름:
#   ① 읽기 전용 사전점검(brew·이미 설치 여부·sudo 상태) ② sudo 암호가 필요하면 → rc=11 로 끝내고 «mini 화면 앞에서 칠 한 줄»을 안내(대화형이라 여기서 못 돌림)
#   ③ 무암호로 되는 경우(또는 mini 앞 한 줄을 이미 친 뒤)에는 설치 확인까지 자동. 멱등: 이미 있으면 건너뜀.
# BYZ e2e 러너는 «BlackHole 2ch» 만 쓴다(scripts·tests 14곳) → 2ch 만 설치(16/64ch 는 설치 안 함).
# 되돌리기(줄 그대로): brew uninstall --cask blackhole-2ch ; brew uninstall switchaudio-osx   (오디오 장치 1개 추가가 사라진다. 재부팅 불필요)
# 마이크 권한은 이 h 와 무관 — MIC_UNVERIFIED 그대로(D9 확인 녹음에서 판정). 시스템 기본 입출력 장치는 바꾸지 않는다.
# 설치는 됐는데 장치가 안 보이면(드라이버 미로드) → rc=13: mini 앞에서 오디오 서비스 재시작 1줄(1~2초 끊김). 그래도 안 보이면 rc=14: 재부팅 여부를 오빠께 묻는 단계.
# rc: 0 설치·장치 확인 완료(또는 이미 있음) · 2 사전점검 실패 · 11 mini 앞 sudo 설치 단계 필요 · 12 설치 후 확인 실패 · 13 드라이버 로드(오디오 서비스 재시작) 필요 · 14 재시작 뒤에도 안 보임 → 재부팅 판단
set -uo pipefail
MINI_USER="${MINI_USER:-byz}"
MINI_IP=100.71.41.107
KEY="$HOME/.ssh/id_ed25519_aifp_op"
SO=(-o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes -i "$KEY")
MARK="$HOME/.cache/aifp-h-mini-bh.guided"   # 재시작 안내를 한 번 줬는지(이 맥 로컬 표식 · 완료되면 지움)
mkdir -p "$HOME/.cache"
say() { printf '[h-mini-bh] %s\n' "$*"; }
die() { printf '[h-mini-bh] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI_USER@$MINI_IP" "$@"; }
PATHFIX='export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH'

command -v timeout >/dev/null 2>&1 || die 2 "timeout 명령이 없다"
[ -f "$KEY" ] || die 2 "전용 키가 없다: $KEY (먼저 h-mini-ssh-key 실행)"

# 1) 사전점검 — 읽기만
say "1/4 사전점검(읽기 전용)"
PRE="$(rs 15 "$PATHFIX
echo brew=\$(command -v brew || echo none)
echo bh=\$(brew list --cask 2>/dev/null | grep -c -x blackhole-2ch)
echo sas=\$(command -v SwitchAudioSource >/dev/null 2>&1 && echo yes || echo no)
echo dev=\$(system_profiler SPAudioDataType 2>/dev/null | grep -c 'BlackHole 2ch')
echo dev2=\$(SwitchAudioSource -a 2>/dev/null | grep -c 'BlackHole 2ch')
echo sudo=\$(sudo -n true >/dev/null 2>&1 && echo nopass || echo needpass)" 2>&1)" || die 2 "mini 접속 실패: $PRE"
echo "$PRE" | sed 's/^/        /'
echo "$PRE" | grep -q '^brew=/' || die 2 "mini 에 brew 가 없다"
BH=$(echo "$PRE" | sed -n 's/^bh=//p'); SAS=$(echo "$PRE" | sed -n 's/^sas=//p'); DEV=$(echo "$PRE" | sed -n 's/^dev=//p'); DEV2=$(echo "$PRE" | sed -n 's/^dev2=//p'); [ "${DEV:-0}" -ge 1 ] 2>/dev/null || DEV=${DEV2:-0}; SUDO=$(echo "$PRE" | sed -n 's/^sudo=//p')

if [ "$BH" = 1 ] && [ "$SAS" = yes ] && [ "${DEV:-0}" -ge 1 ] 2>/dev/null; then
  say "이미 설치돼 있다(BlackHole 2ch 장치 보임 · SwitchAudioSource 있음) — 건너뜀"; rm -f "$MARK"; exit 0
fi

# 1.5) 설치는 됐는데 장치가 안 보임 = 드라이버가 아직 로드되지 않음(재설치가 아니라 오디오 서비스 재시작이 맞다)
if [ "$BH" = 1 ] && [ "$SAS" = yes ]; then
  if [ ! -f "$MARK" ]; then
    : > "$MARK"
    say "1.5/4 설치(BlackHole 2ch·SwitchAudioSource)는 끝났지만 장치 목록에 «BlackHole 2ch» 가 아직 없습니다 — 드라이버 로드만 남았습니다"
    cat <<'EOF'
        ▶ 오빠 손 1회 (mini 화면 앞 또는 mini 로 원격 접속한 터미널): 오디오 서비스 재시작 — 소리가 1~2초 끊기는 것 외에 영향 없음
          sudo killall coreaudiod
        ▶ 끝난 뒤 이 h 를 «다시» 치세요 → 장치 확인(SwitchAudioSource -a · system_profiler)을 자동으로 합니다.
        되돌리기: 해당 없음(이미 설치됨). 제거는 brew uninstall --cask blackhole-2ch ; brew uninstall switchaudio-osx
EOF
    exit 13
  fi
  say "1.5/4 재시작 안내 뒤에도 «BlackHole 2ch» 장치가 보이지 않습니다"
  cat <<'EOF'
        ▶ 오빠 판단 필요: 오디오 서비스 재시작으로 안 보이면 macOS 재시작이 필요할 수 있습니다(mini 는 62일 가동 중인 허브 후보라 끊김 영향이 큽니다).
          ① 재부팅해도 되는 시각인지 알려 주세요 ② 시스템 설정 → 개인정보 보호 및 보안 에서 «시스템 소프트웨어 허용» 대기 항목이 있는지도 확인
        이 h 는 재부팅하지 않습니다. 재부팅 뒤 같은 h 를 다시 치면 장치 확인만 합니다.
EOF
  exit 14
fi

# 2) sudo 단계 — 무암호가 아니면 mini 앞에서
if [ "$SUDO" != nopass ]; then
  say "2/4 설치에는 mini 의 관리자 암호(sudo)가 필요합니다 — 이 자리에서는 입력할 수 없어 여기서 멈춥니다"
  cat <<'EOF'
        ▶ 오빠 손 1회 (mini 화면 앞 또는 mini 로 원격 접속한 터미널에서):
          export PATH=/opt/homebrew/bin:$PATH; brew install --cask blackhole-2ch; brew install switchaudio-osx
          (암호를 물으면 mini 관리자 암호 입력 · 끝나면 새 오디오 장치 «BlackHole 2ch» 1개가 보입니다)
        ▶ 끝난 뒤 이 h 를 «다시» 치세요 → 설치 확인(장치·SwitchAudioSource)을 자동으로 합니다.
        되돌리기: brew uninstall --cask blackhole-2ch ; brew uninstall switchaudio-osx
EOF
  exit 11
fi

# 3) 무암호 sudo 인 경우 — 이 자리에서 설치(비대화형)
say "3/4 설치(무암호 sudo 확인됨) — 7초 룰 대신 크기 아는 배치: 상한 120초"
rs 125 "$PATHFIX
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 NONINTERACTIVE=1
[ \$(brew list --cask 2>/dev/null | grep -c -x blackhole-2ch) = 1 ] || brew install --cask blackhole-2ch
command -v SwitchAudioSource >/dev/null 2>&1 || brew install switchaudio-osx" 2>&1 | tail -4 | sed 's/^/        /'

# 4) 확인 — 읽기만. 장치 목록은 로드에 시간이 걸릴 수 있어 7초 간격으로 최대 3번
say "4/4 설치 확인"
ok=0
for i in 1 2 3; do
  R="$(rs 15 "$PATHFIX
echo dev=\$((\$(system_profiler SPAudioDataType 2>/dev/null | grep -c 'BlackHole 2ch') + \$(SwitchAudioSource -a 2>/dev/null | grep -c 'BlackHole 2ch')))
echo sas=\$(command -v SwitchAudioSource >/dev/null 2>&1 && echo yes || echo no)" 2>&1)"
  echo "$R" | grep -q '^dev=[1-9]' && echo "$R" | grep -q '^sas=yes' && { ok=1; break; }
  sleep 7
done
echo "$R" | sed 's/^/        /'
[ "$ok" = 1 ] || die 12 "BlackHole 장치가 아직 안 보인다 — mini 에서 시스템 설정 → 개인정보 보호 및 보안 에서 드라이버 허용이 필요한지 확인(macOS 가 확장을 막을 수 있음)"
rm -f "$MARK"
say "완료 — BlackHole 2ch + SwitchAudioSource 확인. 마이크 권한은 별도(D9 확인 녹음)"
exit 0
