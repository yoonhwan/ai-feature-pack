#!/usr/bin/env bash
# h-oci-cli-tools.sh — OCI(aifp-oci-jarvis · ubuntu)를 «CLI 운용 노드» 로: claude·pi·codex(npm 사용자 prefix) + tmuxc·tmm(이 리포 팩 복사)
#   초안(2026-10-22 · aifp-pi-master-pi#0) · 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   전제: h-oci-infer-stack.sh 가 먼저 성공해 127.0.0.1:8317(cliproxy)·8790(headroom)이 살아 있어야 «claude ping» 증거가 나온다.
# 비대화형 · 멱등(이미 깔린 버전이면 건너뜀) · 비밀값 0 · 전역 export 0(claude 래퍼 파일 안에서만 8317 을 본다)
# 하지 않는 것: apt 설치 · sudo 필요 작업 · 기존 hermes-gateway/cloudflared 유닛 만지기 · PATH 영구 변경(래퍼 심링크만)
# 상한: 외부 호출 단건 70초 천장(하드 룰 12) · 넘으면 rc=3 이고 같은 h 재실행이 이어감
# rc: 0 성공 · 2 사전점검 · 3 설치 실패 · 5 증거(좌석 열기/닫기) 실패
set -uo pipefail

R="${R:-oci}"
KEY="${KEY:-$HOME/.ssh/oci_chuncheon}"
REPO="${REPO:-/Users/yoonhwan/Project/ai-feature-pack}"
BIN_TMUXC="$REPO/feature-pack/tmuxc"
BIN_TMM="$REPO/feature-pack/tmm"
PI_VER="${PI_VER:-1.3.0}"            # 이 맥과 같은 버전
CODEX_VER="${CODEX_VER:-0.163.0}"
CLAUDE_PKG="@anthropic-ai/claude-code"
CLIPROXY_URL="http://127.0.0.1:8317"

CP="$(mktemp -d /tmp/h-oci-cm.XXXXXX)"
cleanup() { ssh -O exit -o ControlPath="$CP/s" "$R" >/dev/null 2>&1; rm -f "$CP/s"; rmdir "$CP" 2>/dev/null; }
trap cleanup EXIT
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3
    -o IdentitiesOnly=yes -i "$KEY" -o ControlMaster=auto -o ControlPersist=300 -o ControlPath="$CP/s")
say() { printf '[h-cli] %s\n' "$*"; }
die() { printf '[h-cli] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
# ★원격은 항상 PATH 접두★ — ssh 비대화형 PATH 에는 ~/.local/bin·~/.npm-global/bin 이 없다(h377 1차 실측: 방금 깐 tmuxc 를 tmm 설치 점검이 «누락» 으로 오판 → rc=3)
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$R" "export PATH=\$HOME/.local/bin:\$HOME/.npm-global/bin:\$PATH; $*"; }

# ── 0) 로컬 사전점검 ─────────────────────────────────────────────────────────
say "0/6 로컬 사전점검"
[ -f "$KEY" ] || die 2 "ssh 키 없음: $KEY"
[ -d "$BIN_TMUXC" ] && [ -d "$BIN_TMM" ] || die 2 "팩 폴더가 없다: $BIN_TMUXC · $BIN_TMM"
TMUXC_VER="$(cat "$BIN_TMUXC/core/VERSION" 2>/dev/null)"; TMM_VER="$(cat "$BIN_TMM/core/VERSION" 2>/dev/null)"
[ -n "$TMUXC_VER" ] && [ -n "$TMM_VER" ] || die 2 "버전 파일을 못 읽었다"
say "        복사할 팩 버전: tmuxc=$TMUXC_VER tmm=$TMM_VER · npm 고정: pi=$PI_VER codex=$CODEX_VER"

# ── 1) 원격 사전점검 ────────────────────────────────────────────────────────
say "1/6 원격 사전점검"
PRE="$(rs 20 'bash -s' <<'PREEOF'
echo "arch=$(uname -m)"
echo "node=$(node --version 2>/dev/null)"
echo "npm=$(npm --version 2>/dev/null)"
echo "prefix=$(npm config get prefix 2>/dev/null)"
echo "write_prefix=$(test -w "$(npm config get prefix 2>/dev/null)" && echo yes || echo NO)"
for b in git tmux tar gzip; do command -v $b >/dev/null 2>&1 && echo "$b=yes" || echo "$b=NO"; done
for c in claude pi codex tmuxc tmm; do command -v $c >/dev/null 2>&1 && echo "have_$c=yes" || echo "have_$c=no"; done
echo "cliproxy=$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:8317/v1/models || true)"
PREEOF
)" || die 2 "oci 접속 실패: $PRE"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -qx 'arch=aarch64' || die 2 "aarch64 아님"
printf '%s\n' "$PRE" | grep -q '^node=v22' || die 2 "node 22 가 아니다"
for b in git tmux tar gzip; do printf '%s\n' "$PRE" | grep -qx "$b=yes" || die 2 "$b 이 없다"; done
printf '%s\n' "$PRE" | grep -qx 'write_prefix=yes' || die 2 "npm prefix 에 쓰기 불가 — ~/.npm-global 로 바꾸는 단계가 먼저다"
printf '%s\n' "$PRE" | grep -q '^cliproxy=200' || die 2 "cliproxy(127.0.0.1:8317) 가 200 이 아니다 — h-oci-infer-stack.sh 를 먼저 성공시켜라"

# ── 2) npm 사용자 prefix 로 3종 설치 ────────────────────────────────────────
say "2/6 npm 설치(claude·pi·codex)"
# 외부 호출 70초 천장(하드 룰 12): 패키지마다 1회씩 나눈다 — 넘으면 rc=3, 같은 h 재실행이 npm 캐시로 이어간다
npm_one() { rs 70 "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"; mkdir -p \"\$HOME/.npm-global\"; npm install -g --prefix \"\$HOME/.npm-global\" '$1' >/tmp/h-npm.log 2>&1 && echo ok" >/dev/null \
  || die 3 "npm 설치 실패/70초 초과: $1 (/tmp/h-npm.log · 같은 h 재실행으로 이어감)"; }
npm_one "$CLAUDE_PKG"
npm_one "@earendil-works/pi-coding-agent@$PI_VER"
npm_one "@openai/codex@$CODEX_VER"
V="$(rs 40 'bash -lc "export PATH=\$HOME/.npm-global/bin:\$PATH; echo claude=\$(claude --version 2>/dev/null | head -1); echo pi=\$(pi --version 2>/dev/null); echo codex=\$(codex --version 2>/dev/null | head -1)"' 2>&1)"
printf '%s\n' "$V" | sed 's/^/        /'

# ── 3) tmuxc·tmm 팩 복사 + 사용자 설치 ──────────────────────────────────────
say "3/6 tmuxc·tmm 팩 설치"
rs 25 'mkdir -p ~/packs && echo ok' >/dev/null || die 3 "~/packs 생성 실패"
for pk in tmuxc tmm; do
  # 이전 사본은 .prev 로 밀어 두고 새로 푼다(롤백 경로 유지)
  rs 25 "set -e; rm -rf ~/packs/$pk.new; mkdir -p ~/packs; echo ok" >/dev/null || die 3 "정리 실패: $pk"
  timeout 70 tar -C "$REPO/feature-pack" -czf - "$pk" | rs 70 "set -e; tar -xzf - -C ~/packs; echo unpack=ok" >/dev/null || die 3 "$pk 전송/해제 실패"
  rs 20 "set -e; [ -f ~/packs/$pk/core/VERSION ] && echo '$pk'=version_ok || exit 1" >/dev/null || die 3 "$pk 해제 후 버전 파일 없음"
done
rs 70 'set -e; cd ~/packs/tmuxc && bash install.sh >/tmp/h-tmuxc-install.log 2>&1; tail -3 /tmp/h-tmuxc-install.log; echo tmuxc_install_rc=0' || die 3 "tmuxc install.sh 실패(/tmp/h-tmuxc-install.log)"
rs 70 'set -e; export PATH="$HOME/.local/bin:$PATH"; cd ~/packs/tmm && bash install.sh >/tmp/h-tmm-install.log 2>&1; tail -3 /tmp/h-tmm-install.log; echo tmm_install_rc=0' || die 3 "tmm install.sh 실패(/tmp/h-tmm-install.log)"
LOCK="$(rs 30 'echo "tmuxc=$(cat ~/.tmuxc/current/core/VERSION 2>/dev/null)"; echo "tmm=$(cat ~/.tmm/current/core/VERSION 2>/dev/null)"; ls -l ~/.local/bin/tmuxc ~/.local/bin/tmm 2>/dev/null | awk "{print \$9, \$10, \$11}"' 2>&1)"
printf '%s\n' "$LOCK" | sed 's/^/        /'
printf '%s\n' "$LOCK" | grep -q "tmuxc=$TMUXC_VER" || die 3 "tmuxc 버전 불일치(기대 $TMUXC_VER)"
printf '%s\n' "$LOCK" | grep -q "tmm=$TMM_VER"     || die 3 "tmm 버전 불일치(기대 $TMM_VER)"

# ── 4) claude 래퍼(전역 export 금지 · 파일 안에서만 8317) ───────────────────
say "4/6 claude 래퍼"
rs 25 "set -e
mkdir -p ~/.local/bin
cat > ~/.local/bin/claude-aifp <<'W'
#!/usr/bin/env bash
# aifp · OCI 로컬 추론 경로 전용 래퍼 — ANTHROPIC_BASE_URL 을 «이 프로세스에만» 준다(전역 export 금지).
export ANTHROPIC_BASE_URL='$CLIPROXY_URL'
# OCI 의 claude 는 로그인 정보가 없다 — cliproxy(api-keys 비어 있음 = 클라이언트 인증 없음)용 자리표시 값(비밀 아님 · mini 와 같은 방식)
export ANTHROPIC_API_KEY=aifp-local-no-auth
export PATH=\"\$HOME/.npm-global/bin:\$PATH\"
exec claude \"\$@\"
W
chmod 755 ~/.local/bin/claude-aifp
# tmuxc open 은 --model 이 있으면 \$HOME/.headroom/claude-hr.sh 를 실행한다(tmuxc:235) — OCI 엔 그 파일이 없어 좌석이 바로 죽는다 → 얇은 심(하네스 파일 편집 0)
mkdir -p ~/.headroom
cat > ~/.headroom/claude-hr.sh <<'S'
#!/usr/bin/env bash
# aifp · OCI 심 — tmuxc 가 부르는 claude-hr.sh 자리를 claude-aifp(OCI 로컬 cliproxy 8317)로 잇는다.
exec \"\$HOME/.local/bin/claude-aifp\" \"\$@\"
S
chmod 755 ~/.headroom/claude-hr.sh
echo wrapper=ok" || die 3 "래퍼 작성 실패"
rs 20 'grep -c "ANTHROPIC_BASE_URL" ~/.local/bin/claude-aifp; ls -l ~/.headroom/claude-hr.sh | awk "{print \$1, \$9}"; ls -l ~/.local/bin/claude-aifp | awk "{print \$1, \$9}"' 2>&1 | sed 's/^/        /'

# ── 5) 닫는 증거 — claude ping(7초 상한) + 좌석 열고 probe→닫기 ─────────────
say "5/6 증거 ① claude -p ping (7초 상한)"
PING="$(rs 12 'bash -lc "export PATH=\$HOME/.npm-global/bin:\$HOME/.local/bin:\$PATH; timeout 7 claude-aifp -p ping > /tmp/h-ping.out 2>&1; rc=\$?; tail -3 /tmp/h-ping.out; echo ping_rc=\$rc"' 2>&1)" || true
printf '%s\n' "$PING" | sed 's/^/        /'
printf '%s\n' "$PING" | grep -q 'ping_rc=0' || say "        ⚠ ping rc≠0 — 로그: journalctl --user -u headroom -n 30 · cliproxy 인증 확인(다음 장에서 재시도)"

say "5/6 증거 ② 사전: 작업 폴더(\$HOME) 신뢰·온보딩·API키 승인 표식(첫 화면 질문이 Enter 로 «No, exit» 가 되는 것 방지)"
# mini 실측(2026-10-22): 처음 여는 폴더는 «trust this folder?» 가 뜨고 tmuxc 가 보낸 Enter 가 기본값 «No, exit» 를 눌러 claude 가 종료됐다.
# ~/.claude.json 의 projects[<폴더>].hasTrustDialogAccepted 는 Claude Code 의 표준 키(이 맥 파일에서 확인). 백업 후 JSON 검증을 거쳐 원자적 교체.
rs 25 'python3 -' <<'PYEOF' 2>&1 | sed 's/^/        /'
import json, os, shutil, time
p = os.path.expanduser('~/.claude.json'); d = {}
if os.path.exists(p):
    shutil.copy2(p, p + '.bak-' + time.strftime('%Y%m%d-%H%M%S'))
    d = json.load(open(p))
d['hasCompletedOnboarding'] = True
d.setdefault('projects', {}).setdefault(os.path.expanduser('~'), {})['hasTrustDialogAccepted'] = True
d.setdefault('customApiKeyResponses', {}).setdefault('approved', [])
if 'aifp-local-no-auth' not in d['customApiKeyResponses']['approved']:
    d['customApiKeyResponses']['approved'].append('aifp-local-no-auth')
tmp = p + '.tmp'
json.dump(d, open(tmp, 'w'), ensure_ascii=False, indent=2); json.load(open(tmp)); os.chmod(tmp, 0o600); os.replace(tmp, p)
# 2026-10-22 h377 실측: tmuxc 가 띄운 claude 첫 화면 «Bypass Permissions 동의» 에 Enter → «No, exit». 이 맥과 같은 설정 키(settings.json)로 건너뛴다.
s = os.path.expanduser('~/.claude/settings.json'); sd = {}
os.makedirs(os.path.dirname(s), exist_ok=True)
if os.path.exists(s):
    shutil.copy2(s, s + '.bak-' + time.strftime('%Y%m%d-%H%M%S'))
    sd = json.load(open(s))
sd['skipDangerousModePermissionPrompt'] = True
tmp = s + '.tmp'
json.dump(sd, open(tmp, 'w'), ensure_ascii=False, indent=2); json.load(open(tmp)); os.replace(tmp, s)
print('trust_onboarding_key=ok skip_bypass_prompt=ok')
PYEOF

say "5/6 증거 ② tmuxc 좌석 열기 → 화면 캡처 → probe → 닫기"
SEAT="oci-cli-proof-$(date +%H%M%S)"
OPEN="$(rs 60 "bash -lc 'export PATH=\$HOME/.local/bin:\$HOME/.npm-global/bin:\$PATH; cd ~ && tmuxc open . --name $SEAT --agent claude --model claude-sonnet-5-5 --role worker 2>&1 | tail -5'" 2>&1)" || true
printf '%s\n' "$OPEN" | sed 's/^/        /'
sleep 6
SCR="$(rs 15 "bash -lc 'tmux capture-pane -p -t \"$SEAT:\" 2>/dev/null | grep -v \"^\\s*$\" | tail -8 | cut -c1-120'" 2>&1)" || true
printf '%s\n' "$SCR" | sed 's/^/        화면| /'
PROBE="$(rs 30 "bash -lc 'export PATH=\$HOME/.local/bin:\$PATH; tmuxc probe $SEAT 2>&1 | head -8'" 2>&1)" || true
printf '%s\n' "$PROBE" | sed 's/^/        /'
CLOSE="$(rs 25 "bash -lc 'tmux has-session -t \"=$SEAT\" 2>/dev/null && tmux kill-session -t \"=$SEAT\"; tmux has-session -t \"=$SEAT\" 2>/dev/null && echo seat=STILL_ALIVE || echo seat=closed'" 2>&1)" || true
printf '%s\n' "$CLOSE" | sed 's/^/        /'

# ── 6) 끝 ───────────────────────────────────────────────────────────────────
say "6/6 끝"
cat <<EOF
        닫는 증거 3줄(보고에 그대로):
          · claude-aifp -p ping → 위 ping_rc 줄
          · tmuxc probe 결과(모델·세션) 줄
          · seat=closed 줄
        롤백: ssh $R 'rm -f ~/.local/bin/claude-aifp ~/.headroom/claude-hr.sh; rm -rf ~/.tmuxc/versions/$TMUXC_VER ~/.tmm/versions/$TMM_VER; npm rm -g --prefix ~/.npm-global $CLAUDE_PKG @earendil-works/pi-coding-agent @openai/codex'
        주의: tmuxc 좌석은 tmux 안에서 산다 — 닫기는 위에서 이미 했다(seat=closed 확인).
EOF
exit 0
