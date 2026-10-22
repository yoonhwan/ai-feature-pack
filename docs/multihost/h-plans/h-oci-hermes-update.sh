#!/usr/bin/env bash
# h-oci-hermes-update.sh — OCI hermes(게이트웨이)를 원격 main 으로 올린다. 초안 · 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   (2026-10-22 · aifp-multihost-master-claude#2 · 상위 #3207 · 오빠 10-21 «hermes도 업데이트 지원하고»)
#   먼저 계획만: `DRY=1 bash …` (읽기 전용 · 쓰기 0). 대상 바꾸기: R=oci(기본).
#
# 실측(2026-10-22): OCI v0.15.1 (v2026.5.29-796 · 46b2afc5) · 이 맥 v0.20.5 · mini v0.21.4 · 원격 main 81a55437.
#   OCI 는 --plan 이 없는 «옛» 버전 → 4.5개월 점프(설정 마이그레이션 가능) · 로컬 수정 2건: AGENTS.md(+16줄 침묵 프리픽스) · plugins/em-dash-filter/(untracked)
#   hermes-gateway.service = systemd --user(Restart=always) · linger=yes · ~/.hermes 4.5G · 디스크 여유 69G
#   `hermes update --check` 는 두 호스트 모두 60초 안에 안 끝났다(rc=124) → 이 h 는 git ls-remote(15초)로 대신 확인한다.
#
# 단계: 0 사전점검 → 1 보존(상태 tar·로컬 수정 patch·sha 장부) → 2 업데이트(분리 실행·진행 폴링) → 3 재시작 → 4 증거(version·doctor·서비스·로그) → 롤백 안내
# rc: 0 성공 · 2 사전점검 실패 · 3 보존 실패 · 4 업데이트 실패 · 5 재시작/증거 실패(코드는 새 버전 — 롤백 안내 출력)
#
# ★롤백은 «덮어쓰기» 라 사람(HIL) 승인 건 — 이 스크립트가 실행하지 않는다. 출력되는 줄을 오빠 승인 뒤에:
#   ssh oci 'cd ~/.hermes/hermes-agent && git checkout <OLD_SHA> && ./venv/bin/pip install -e . -q && systemctl --user restart hermes-gateway'
#   설정이 마이그레이션됐으면: ssh oci 'tar -xzf ~/.hermes/backups/pre-update-<ts>/state.tgz -C ~/.hermes'  (config.yaml 등 되돌림)
set -uo pipefail

R="${R:-oci}"; DRY="${DRY:-0}"
OCI_KEY="${KEY:-$HOME/.ssh/oci_chuncheon}"
REPO_URL="https://github.com/NousResearch/hermes-agent.git"
if [ "$R" = oci ]; then SSHX=(-o IdentitiesOnly=yes -i "$OCI_KEY"); else SSHX=(); fi
CP="$(mktemp -d /tmp/h-hu-cm.XXXXXX)"
cleanup() { ssh -O exit -o ControlPath="$CP/s" "$R" >/dev/null 2>&1; rmdir "$CP" 2>/dev/null; }
trap cleanup EXIT
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3
    ${SSHX[@]+"${SSHX[@]}"} -o ControlMaster=auto -o ControlPersist=180 -o ControlPath="$CP/s")
say() { printf '[h-hermes] %s\n' "$*"; }
die() { printf '[h-hermes] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$R" "$@"; }   # t = 호출 1회 상한(초)
RP='export PATH="$HOME/.local/bin:$PATH";'
HD='$HOME/.hermes'

# ── 0) 사전점검 (읽기 전용) ──────────────────────────────────────────────────
say "0/4 사전점검 (R=$R DRY=$DRY)"
PRE="$(rs 20 "$RP"' cd '"$HD"'/hermes-agent 2>/dev/null || { echo NOREPO; exit 0; }
echo "ver=$(hermes --version 2>&1 | head -1)"
echo "head=$(git rev-parse HEAD)"
echo "branch=$(git branch --show-current)"
echo "dirty=$(git status --short | tr "\n" ";" | cut -c1-200)"
echo "svc=$(systemctl --user is-active hermes-gateway 2>&1)"
echo "linger=$(loginctl show-user "$USER" -p Linger 2>&1)"
echo "disk_free_gb=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9)"
echo "hermes_home_mb=$(du -sm '"$HD"' 2>/dev/null | cut -f1)"' 2>&1)" || die 2 "$R 접속/조회 실패"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -q '^NOREPO' && die 2 "원격에 ~/.hermes/hermes-agent 가 없다"
OLD_SHA="$(printf '%s\n' "$PRE" | sed -n 's/^head=//p')"; [ -n "$OLD_SHA" ] || die 2 "현재 sha 를 못 읽었다"
printf '%s\n' "$PRE" | grep -q '^svc=active' || die 2 "hermes-gateway 가 active 가 아니다 — 업데이트 전에 현재 상태부터 확인"
printf '%s\n' "$PRE" | grep -q '^branch=main' || die 2 "원격 체크아웃이 main 이 아니다"
FREE="$(printf '%s\n' "$PRE" | sed -n 's/^disk_free_gb=//p')"; [ "${FREE:-0}" -ge 15 ] 2>/dev/null || die 2 "디스크 여유 ${FREE:-?}GB < 15GB"
NEW_SHA="$(rs 20 "cd $HD/hermes-agent && timeout 15 git ls-remote origin refs/heads/main 2>&1 | cut -f1" 2>&1)" || die 2 "원격 main 조회 실패(15초)"
[ ${#NEW_SHA} -eq 40 ] || die 2 "원격 main sha 이상: $NEW_SHA"
say "        현재 $OLD_SHA → 원격 main $NEW_SHA"
[ "$OLD_SHA" != "$NEW_SHA" ] || { say "이미 최신 — 할 일 없음 rc=0"; exit 0; }

if [ "$DRY" = 1 ]; then
  say "DRY — 아래는 «하려던 일» 이다(쓰기 0):"
  say "  1 보존: ~/.hermes/backups/pre-update-<ts>/ 에 state.tgz(config.yaml·auth.json·channel_*·cron·gateway_state.json 등 핵심 상태 0600) + local.patch(AGENTS.md diff) + untracked.tgz(em-dash-filter 등) + sha 장부"
  say "  2 업데이트: nohup hermes update --yes --backup (분리 실행 · 로그 ~/.hermes/backups/pre-update-<ts>/update.log) → 10초 간격 폴링(호출마다 ≤7초) · 진행 중 서비스는 hermes 가 재시작"
  say "  3 재시작: systemctl --user restart hermes-gateway (update 가 이미 했어도 1회 확정)"
  say "  4 증거: hermes --version · hermes doctor(요약) · 서비스 active · 로그 tail 에러 줄 수 · gateway_state.json"
  say "  롤백 줄은 실패 시에만 출력(실행 안 함)"
  exit 0
fi

# ── 1) 보존 ─────────────────────────────────────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"; BK="$HD/backups/pre-update-$TS"
say "1/4 보존 → $BK"
rs 40 "umask 077; set -e; mkdir -p $BK; cd $HD
tar -czf $BK/state.tgz --ignore-failed-read config.yaml auth.json auth.lock channel_directory.json channel_roles cron gateway_state.json AGENTS.md 2>/dev/null || true
cd $HD/hermes-agent; git diff > $BK/local.patch; tar -czf $BK/untracked.tgz \$(git ls-files --others --exclude-standard | head -200) 2>/dev/null || true
printf 'old_sha=$OLD_SHA\nnew_sha=$NEW_SHA\nts=$TS\n' > $BK/sha.txt; ls -l $BK | awk 'NR>1{print \$5, \$9}'" 2>&1 | sed 's/^/        /'
rs 10 "test -s $BK/state.tgz && test -s $BK/sha.txt" || die 3 "보존 파일이 비었다 — 업데이트 하지 않는다"

# ── 2) 업데이트 (분리 실행 + 폴링) ───────────────────────────────────────────
say "2/4 업데이트 시작(분리 실행 — pip 설치는 수 분)"
rs 15 "$RP cd $HD/hermes-agent && nohup hermes update --yes --backup </dev/null >$BK/update.log 2>&1 & echo \$! > $BK/update.pid; sleep 1; cat $BK/update.pid" >/dev/null || die 4 "update 시작 실패"
OK=0
for i in $(seq 1 90); do   # 90 × 10초 = 15분 상한(분리 실행이라 호출은 매번 ≤7초)
  sleep 10
  ST="$(rs 7 "kill -0 \$(cat $BK/update.pid) 2>/dev/null && echo RUN || echo DONE; tail -1 $BK/update.log 2>/dev/null | cut -c1-110" 2>&1)" || ST="SSH?"
  [ $((i % 6)) = 0 ] && say "        ${i}0초 경과: $(printf '%s' "$ST" | tr '\n' ' ')"
  case "$ST" in DONE*) OK=1; break;; esac
done
[ "$OK" = 1 ] || die 4 "15분 안에 안 끝났다 — update.log: $BK/update.log (프로세스는 계속 돈다 · 끊지 않음)"
rs 10 "tail -8 $BK/update.log | cut -c1-140" 2>&1 | sed 's/^/        /'

# ── 3) 재시작 ───────────────────────────────────────────────────────────────
say "3/4 재시작"
rs 20 "systemctl --user restart hermes-gateway; sleep 5; systemctl --user is-active hermes-gateway" 2>&1 | sed 's/^/        /'

# ── 4) 증거 ─────────────────────────────────────────────────────────────────
say "4/4 증거"
EV="$(rs 40 "$RP echo \"ver=\$(hermes --version 2>&1 | head -1)\"; echo \"head=\$(cd $HD/hermes-agent && git rev-parse HEAD)\"; echo \"svc=\$(systemctl --user is-active hermes-gateway)\"; echo \"err_lines_2min=\$(journalctl --user -u hermes-gateway --since '2 min ago' --no-pager 2>/dev/null | grep -c -i -E 'error|traceback')\"; echo \"state=\$(head -c 200 $HD/gateway_state.json 2>/dev/null | tr '\n' ' ')\"; timeout 25 hermes doctor 2>&1 | tail -6 | cut -c1-120 | sed 's/^/doctor: /'" 2>&1)" || EV="증거 수집 실패"
printf '%s\n' "$EV" | sed 's/^/        /'
FAIL=0
printf '%s\n' "$EV" | grep -q '^svc=active' || FAIL=1
printf '%s\n' "$EV" | grep -q "^head=$NEW_SHA" || FAIL=1
if [ "$FAIL" = 0 ]; then say "완료 rc=0 — 새 sha 적용 · 서비스 active. 로그 에러 줄 수·doctor 는 위를 눈으로 확인"; exit 0; fi
say "증거 불일치 rc=5 — 코드는 바뀌었을 수 있다. 롤백(사람 승인 뒤): ssh oci 'cd ~/.hermes/hermes-agent && git checkout $OLD_SHA && ./venv/bin/pip install -e . -q && systemctl --user restart hermes-gateway'"
say "설정 되돌림: ssh oci 'tar -xzf $BK/state.tgz -C ~/.hermes'"
exit 5
