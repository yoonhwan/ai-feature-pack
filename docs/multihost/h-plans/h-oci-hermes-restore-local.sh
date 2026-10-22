#!/usr/bin/env bash
# h-oci-hermes-restore-local.sh — OCI hermes 업데이트(h5)가 지운 오빠 로컬 수정 2건 복원. 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: `DRY=1 bash …`
#   (2026-10-22 · aifp-multihost-master-claude#2 · 상위 #3210)
#   ① plugins/em-dash-filter (plugin.yaml + __init__.py · hook pre_gateway_dispatch) — config.yaml 의 plugins.enabled 에는 이미 있다
#      → 업데이트가 지우지 않는 ~/.hermes/plugins/em-dash-filter 에 둔다(관리 클론 밖). hermes 가 거기서 못 찾으면 원래 자리(관리 클론 plugins/)로 폴백.
#   ② AGENTS.md 끝의 «침묵 프리픽스» 16줄 — 보존된 local.patch 의 + 줄만 뽑아 끝에 덧붙인다(상류가 바뀌어 patch 적용은 실패).
#      관리 클론 안이라 다음 업데이트에 또 버려진다 → 행동은 ① 플러그인이 맡고 ② 는 에이전트 안내문일 뿐.
#   그 뒤 hermes-gateway 재시작 → 증거(플러그인 목록·서비스·slack 연결·로그의 등록 줄).
# rc: 0 성공 · 2 사전점검 실패 · 3 복원 실패 · 5 재시작/증거 실패(복원 파일은 남김)
# 롤백(사람 승인): ssh oci 'rm -rf ~/.hermes/plugins/em-dash-filter ~/.hermes/hermes-agent/plugins/em-dash-filter; cd ~/.hermes/hermes-agent && git checkout AGENTS.md'
set -uo pipefail
R="${R:-oci}"; DRY="${DRY:-0}"
OCI_KEY="${KEY:-$HOME/.ssh/oci_chuncheon}"
BK="${BK:-/home/ubuntu/.hermes/backups/pre-update-20261022-181126}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o IdentitiesOnly=yes -i "$OCI_KEY")
say() { printf '[h-restore] %s\n' "$*"; }
die() { printf '[h-restore] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$R" "$@"; }
RP='export PATH="$HOME/.local/bin:$PATH";'

say "0/3 사전점검 (DRY=$DRY)"
PRE="$(rs 20 "$RP"' B='"$BK"'
echo "bk_untracked=$(tar -tzf $B/untracked.tgz 2>/dev/null | tr "\n" " ")"
echo "bk_patch_plus=$(grep -c "^+[^+]" $B/local.patch 2>/dev/null)"
echo "svc=$(systemctl --user is-active hermes-gateway)"
echo "ver=$(hermes --version 2>&1 | head -1 | cut -c1-60)"
echo "plug_user_dir=$(ls -d ~/.hermes/plugins/em-dash-filter 2>/dev/null || echo none)"
echo "plug_clone_files=$(ls ~/.hermes/hermes-agent/plugins/em-dash-filter 2>/dev/null | wc -l | tr -d " ")"
echo "agents_has_rule=$(grep -c "em dash" ~/.hermes/hermes-agent/AGENTS.md)"
echo "enabled_cfg=$(grep -c "^    - em-dash-filter" ~/.hermes/config.yaml)"
echo "active_agents=$(python3 -c "import json;print(json.load(open(\"$HOME/.hermes/gateway_state.json\")).get(\"active_agents\"))" 2>&1)"' 2>&1)" || die 2 "접속/조회 실패"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -q 'plugins/em-dash-filter/__init__.py' || die 2 "보존본 untracked.tgz 에 플러그인 파일이 없다($BK)"
printf '%s\n' "$PRE" | grep -q '^bk_patch_plus=1[0-9]' || die 2 "보존본 local.patch 의 추가 줄 수가 예상(16 안팎)과 다르다"
printf '%s\n' "$PRE" | grep -q '^svc=active' || die 2 "hermes-gateway 가 active 가 아니다"
printf '%s\n' "$PRE" | grep -q '^enabled_cfg=[1-9]' || say "        ⚠️ config.yaml 의 plugins.enabled 에 em-dash-filter 가 없다 — 복원해도 로드되지 않을 수 있음(증거 단계에서 확인)"
if [ "$DRY" = 1 ]; then
  say "DRY — 하려던 일(쓰기 0): ① 보존본 untracked.tgz 의 플러그인 2파일 → ~/.hermes/plugins/em-dash-filter/ (0644) ② local.patch 의 + 줄만 AGENTS.md 끝에 덧붙임(이미 규칙이 있으면 건너뜀) ③ hermes-gateway 재시작 ④ 증거"
  exit 0
fi

say "1/3 복원"
rs 30 "$RP set -e; B=$BK
mkdir -p ~/.hermes/plugins/em-dash-filter
tar -xzf \$B/untracked.tgz -C /tmp --wildcards 'plugins/em-dash-filter/*' 2>/dev/null || { mkdir -p /tmp/h-restore-x && tar -xzf \$B/untracked.tgz -C /tmp/h-restore-x; }
SRC=/tmp/plugins/em-dash-filter; [ -d \$SRC ] || SRC=/tmp/h-restore-x/plugins/em-dash-filter
cp -p \$SRC/plugin.yaml \$SRC/__init__.py ~/.hermes/plugins/em-dash-filter/; chmod 644 ~/.hermes/plugins/em-dash-filter/*
rm -rf /tmp/plugins /tmp/h-restore-x
if ! grep -q 'em dash' ~/.hermes/hermes-agent/AGENTS.md; then
  { echo; grep '^+[^+]' \$B/local.patch | sed 's/^+//'; } >> ~/.hermes/hermes-agent/AGENTS.md
fi
ls -l ~/.hermes/plugins/em-dash-filter | awk 'NR>1{print \$5, \$9}'; echo agents_rule=\$(grep -c 'em dash' ~/.hermes/hermes-agent/AGENTS.md)" 2>&1 | sed 's/^/        /' || die 3 "복원 실패"

say "2/3 재시작"
rs 40 "systemctl --user restart hermes-gateway; sleep 8; systemctl --user is-active hermes-gateway" 2>&1 | sed 's/^/        /'

say "3/3 증거"
EV="$(rs 40 "$RP echo \"plugins=\$(timeout 15 hermes plugins list 2>&1 | grep -i -E 'em-dash' | head -2 | tr -s ' ' | tr '\n' ';')\"
echo \"svc=\$(systemctl --user is-active hermes-gateway)\"
echo \"slack=\$(python3 -c \"import json;print(json.load(open('\$HOME/.hermes/gateway_state.json'))['platforms']['slack']['state'])\" 2>&1)\"
echo \"log_em_dash=\$(journalctl --user -u hermes-gateway --since '2 min ago' --no-pager 2>/dev/null | grep -i -c 'em-dash')\"
echo \"err_2min=\$(journalctl --user -u hermes-gateway --since '2 min ago' --no-pager 2>/dev/null | grep -c -i -E 'traceback')\"" 2>&1)" || EV="증거 수집 실패"
printf '%s\n' "$EV" | sed 's/^/        /'
printf '%s\n' "$EV" | grep -q '^svc=active' || { say "서비스 비정상 rc=5 — 롤백 줄은 헤더(사람 승인)"; exit 5; }
printf '%s\n' "$EV" | grep -q -i '^plugins=.*em-dash' || { say "플러그인 목록에 없음 rc=5 — 사용자 폴더에서 못 찾음. 폴백(원래 자리): ssh oci 'cp -r ~/.hermes/plugins/em-dash-filter ~/.hermes/hermes-agent/plugins/ && systemctl --user restart hermes-gateway' (승인 뒤)"; exit 5; }
say "완료 rc=0 — 플러그인 로드 · 서비스 active. 실제 동작은 슬랙에서 «—» 로 시작하는 메시지를 보내 무응답인지 확인(오빠 손 1회)"
exit 0
