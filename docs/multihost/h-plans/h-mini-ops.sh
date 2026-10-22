#!/usr/bin/env bash
# h-mini-ops.sh — BYZ Mac mini(ssh 별칭 `mini` · 100.71.41.107 · 사용자 byz)를 «운용·시험 노드» 로: pi·tmm 설치(이 맥과 같은 버전) + tmuxc 0.4.3(probe 가능) + 운용 1회(좌석 열기→probe→닫기)
#   초안(2026-10-22 · aifp-pi-master-pi#0) · 실행은 오빠가 `! bash /tmp/h<N>` 로만.
# 실측 전제(2026-10-22): byz 사용자 · brew /opt/homebrew 쓰기가능 · node v25.8.1 · tmux 3.7 · 기존 tmuxc 0.1.0(=`open`/`list` 만, probe 없음) · headroom 8790=200 · cliproxy 8317=200 · mini sudo 는 암호 필요 → **사용자 설치만**
# 비대화형 · 멱등 · 비밀값 0(값을 읽지도 출력하지도 않는다) · sudo 0 · brew install 0(npm/파일복사만)
# rc: 0 성공 · 2 사전점검 · 3 설치 실패 · 5 운용 증거 실패
set -uo pipefail

# ★고정 규칙(오빠 2026-10-22)★ mini 는 «ssh mini» 로만 부른다 — 사용자 이름(yoonhwan/byz)을 스크립트에 박지 않는다.
MINI="${MINI:-mini}"          # ~/.ssh/config: Host mini byz-mini byzs-mac-mini · HostName 100.71.41.107 · User byz · IdentityFile id_ed25519_aifp_op
KEY="${KEY:-$HOME/.ssh/id_ed25519_aifp_op}"
REPO="${REPO:-/Users/yoonhwan/Project/ai-feature-pack}"
PI_VER="${PI_VER:-1.3.0}"
TMUXC_PACK="$REPO/feature-pack/tmuxc"
TMM_PACK="$REPO/feature-pack/tmm"

SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-mini] %s\n' "$*"; }
die() { printf '[h-mini] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "$@"; }

# ── 0) 로컬 사전점검 ────────────────────────────────────────────────────────
say "0/6 로컬 사전점검"
ssh -G "$MINI" 2>/dev/null | grep -qx "user byz" || die 2 "ssh 별칭 $MINI 가 User byz 로 안 풀린다(~/.ssh/config 확인)"
[ -d "$TMUXC_PACK" ] && [ -d "$TMM_PACK" ] || die 2 "팩 폴더가 없다: $TMUXC_PACK · $TMM_PACK"
TMUXC_VER="$(cat "$TMUXC_PACK/core/VERSION")"; TMM_VER="$(cat "$TMM_PACK/core/VERSION")"
say "        팩 버전: tmuxc=$TMUXC_VER tmm=$TMM_VER · pi=$PI_VER"

# ── 1) 원격 사전점검 ────────────────────────────────────────────────────────
say "1/6 mini 사전점검 (ssh $MINI)"
PRE="$(ms 20 'bash -s' <<'PREEOF'
echo "host=$(hostname -s)"
echo "arch=$(uname -m)"
echo "user=$(id -un)"
echo "brew=$(test -w /opt/homebrew/lib/node_modules && echo yes || echo NO)"
echo "node=$(node --version 2>/dev/null)"
echo "npm=$(npm --version 2>/dev/null)"
echo "tmux=$(tmux -V 2>&1)"
echo "fzf=$(command -v fzf >/dev/null 2>&1 && echo yes || echo NO)"
echo "tmuxc_old=$(cat ~/.tmuxc/current/core/VERSION 2>/dev/null)"
echo "headroom=$(curl -s -o /dev/null -w %{http_code} -m 4 http://127.0.0.1:8790/health || true)"
echo "cliproxy=$(curl -s -o /dev/null -w %{http_code} -m 4 http://127.0.0.1:8317/v1/models || true)"
echo "claude=$(test -x ~/.local/bin/claude && echo yes || echo NO)"
echo "have_pi=$(command -v pi >/dev/null 2>&1 && echo yes || echo no)"
PREEOF
)" || die 2 "mini 접속 실패(키 배포 확인): $PRE"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -qx 'arch=arm64' || die 2 "arm64 가 아니다"
printf '%s\n' "$PRE" | grep -qx 'user=byz' || die 2 "원격 사용자가 byz 가 아니다 — ssh 별칭 mini 의 User 설정 확인(~/.ssh/config: Host mini … User byz)"
printf '%s\n' "$PRE" | grep -qx 'brew=yes' || die 2 "brew 모듈 폴더에 쓰기 불가 — npm -g 설치가 안 된다"
printf '%s\n' "$PRE" | grep -qx 'fzf=yes' || die 2 "fzf 가 없다(tmm 은 fzf 필요) — brew install fzf 는 오빠 승인 뒤"
printf '%s\n' "$PRE" | grep -qx 'claude=yes' || die 2 "mini 에 claude 가 없다(~/.local/bin/claude)"

# ── 2) pi 설치(이 맥과 같은 버전) ───────────────────────────────────────────
say "2/6 pi@$PI_VER 설치"
if printf '%s\n' "$PRE" | grep -q '^have_pi=yes'; then say "        이미 있음 — 버전 확인만"; fi
ms 240 "bash -lc 'npm install -g @earendil-works/pi-coding-agent@$PI_VER >/tmp/h-mini-pi.log 2>&1 && echo pi_install=ok'" \
  || die 3 "pi 설치 실패(/tmp/h-mini-pi.log)"
ms 30 'bash -lc "echo pi=\$(pi --version 2>/dev/null)"' 2>&1 | sed 's/^/        /'

# ── 3) tmuxc·tmm 팩 복사 + 사용자 설치 ──────────────────────────────────────
say "3/6 tmuxc $TMUXC_VER · tmm $TMM_VER 설치"
ms 20 'mkdir -p ~/packs && echo ok' >/dev/null || die 3 "~/packs 생성 실패"
for pk in tmuxc tmm; do
  ms 25 "set -e; mkdir -p ~/packs; rm -rf ~/packs/$pk.prev; [ -d ~/packs/$pk ] && mv ~/packs/$pk ~/packs/$pk.prev || true; echo ok" >/dev/null || die 3 "$pk 사전정리 실패"
  timeout 180 tar -C "$REPO/feature-pack" -czf - "$pk" | ms 180 "set -e; tar -xzf - -C ~/packs; echo unpack=ok" >/dev/null || die 3 "$pk 전송/해제 실패"
  ms 20 "set -e; [ -f ~/packs/$pk/core/VERSION ] && echo version_ok" >/dev/null || die 3 "$pk 해제 후 버전 파일 없음"
done
ms 120 'set -e; cd ~/packs/tmuxc && bash install.sh >/tmp/h-mini-tmuxc.log 2>&1; tail -2 /tmp/h-mini-tmuxc.log' || die 3 "tmuxc install.sh 실패(/tmp/h-mini-tmuxc.log)"
ms 120 'set -e; cd ~/packs/tmm && bash install.sh >/tmp/h-mini-tmm.log 2>&1; tail -2 /tmp/h-mini-tmm.log'   || die 3 "tmm install.sh 실패(/tmp/h-mini-tmm.log)"
LOCK="$(ms 30 'echo "tmuxc=$(cat ~/.tmuxc/current/core/VERSION 2>/dev/null)"; echo "tmm=$(cat ~/.tmm/current/core/VERSION 2>/dev/null)"; echo "probe=$(~/.local/bin/tmuxc probe --help >/dev/null 2>&1 && echo yes || echo NO)"' 2>&1)"
printf '%s\n' "$LOCK" | sed 's/^/        /'
printf '%s\n' "$LOCK" | grep -q "tmuxc=$TMUXC_VER" || die 3 "tmuxc 버전 불일치(기대 $TMUXC_VER)"
printf '%s\n' "$LOCK" | grep -q "tmm=$TMM_VER"     || die 3 "tmm 버전 불일치(기대 $TMM_VER)"

# ── 4) 운용 1회 ① 이 맥에서 ssh 로 mini 의 tmuxc 를 불러 좌석 열기 ──────────
say "4/6 운용 ① 좌석 열기(이 맥 ssh → mini tmuxc)"
SEAT="mini-ops-proof-$(date +%H%M%S)"
OPEN="$(ms 90 "bash -lc 'export PATH=\$HOME/.local/bin:\$PATH; cd ~ && tmuxc open . --name $SEAT --agent claude --role worker 2>&1 | tail -6'" 2>&1)" || true
printf '%s\n' "$OPEN" | sed 's/^/        /'
printf '%s\n' "$OPEN" | grep -qi 'session=' || say "        ⚠ 세션 생성 줄이 안 보인다 — 아래 probe/생존 확인으로 판정"

# ── 5) 운용 ② probe(모델·헤드룸 경유) ③ 닫기 ───────────────────────────────
say "5/6 운용 ② probe"
PROBE="$(ms 40 "bash -lc 'export PATH=\$HOME/.local/bin:\$PATH; tmuxc probe $SEAT 2>&1 | head -8; echo ---; tmux show-environment -t \"=$SEAT\" 2>/dev/null | grep -E \"^(ANTHROPIC_BASE_URL|TMUXC_|PORT)\" | sed \"s/=.*/=<set>/\"; tmux show-environment -t \"=$SEAT\" ANTHROPIC_BASE_URL 2>/dev/null | sed \"s#http://[^ ]*#http://<host:port>#\"'" 2>&1)" || true
printf '%s\n' "$PROBE" | sed 's/^/        /'
say "        판정 기준: probe 에 model= 줄이 있고(모델 확인) · ANTHROPIC_BASE_URL 이 세션 env 에 있으면 «헤드룸 경유» 확인 · 없으면 «경유 미확인» 으로 정직하게 보고"

say "5/6 운용 ③ 닫기"
CLOSE="$(ms 30 "bash -lc 'tmux has-session -t \"=$SEAT\" 2>/dev/null && tmux kill-session -t \"=$SEAT\"; tmux has-session -t \"=$SEAT\" 2>/dev/null && echo seat=STILL_ALIVE || echo seat=closed'" 2>&1)" || true
printf '%s\n' "$CLOSE" | sed 's/^/        /'

# ── 6) 끝 ───────────────────────────────────────────────────────────────────
say "6/6 끝"
cat <<EOF
        닫는 증거 3줄(보고에 그대로):
          · pi=\$(pi --version) · tmuxc=$TMUXC_VER · tmm=$TMM_VER (위 잠금 확인 줄)
          · probe 결과(모델 줄 + ANTHROPIC_BASE_URL 유무)
          · seat=closed 줄
        롤백: ssh mini 'rm -rf ~/.tmm/versions/$TMM_VER ~/.tmuxc/versions/$TMUXC_VER; npm rm -g @earendil-works/pi-coding-agent'
              기존 tmuxc 0.1.0 은 지우지 않았다(~/.tmuxc/versions/0.1.0 그대로 · 심링크만 $TMUXC_VER 로 바뀐다)
        남은 것(오빠 판정): mini 에 브라우저 시험을 이관하려면 Chrome CDP·BlackHole·러너 조건 목록이 필요 — 별도 발주.
EOF
exit 0
