#!/usr/bin/env bash
# h-mini-hermes-update.sh — mini(byz@) hermes(게이트웨이)를 원격 main 으로 올린다. 초안 · 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1
#   (2026-10-22 · aifp-multihost-master-claude#2 · 상위 #3259 ② · h-oci-hermes-update.sh 를 macOS 용으로 고침)
#   실측(2026-10-22): mini v0.21.4 @5f47c35d · 원격 main 8237c7f8 · launchd ai.hermes.gateway(pid 1 개) · 슬랙/텔레그램 connected(feishu retrying 은 원래 상태) · active_agents=0
#   ★~/.hermes 가 36.9GB 라 전체 백업(zip, --backup)을 쓰지 않는다★ — hermes 기본의 빠른 상태 스냅샷 + 이 h 의 핵심 상태 tar 만.
#   로컬 수정: 추적 파일 4개(gateway/platforms/base.py + 테스트 3개, +222/-1) · 미추적 agent/anthropic_adapter.py.bak-mcpdedup-13135 · stash 1개(autostash 20260923)
#     → 업데이트가 stash→복원을 시도한다. 이 h 는 시작 전 `git diff HEAD` 전체를 patch 로 저장하고, 끝난 뒤 «같은 4파일이 다시 수정 상태인지» 확인한다(복원 실패면 patch 로 3-way 적용 안내).
#   OCI(h5)에서 로컬 수정이 사라진 전례(플러그인 파일 소실) → 이번엔 끝난 뒤 확인을 합격 기준에 넣었다.
# 단계: 0 사전점검 → 1 보존(상태 tar·patch·untracked tar·sha) → 2 업데이트(분리 실행·10초 폴링) → 3 확인(게이트웨이 재시작은 hermes 가 함, 아니면 1회) → 4 증거 → 롤백 안내
# rc: 0 성공 · 2 사전점검 실패 · 3 보존 실패 · 4 업데이트 실패 · 5 재시작/증거 실패(코드는 새 버전일 수 있음)
# ★롤백은 «덮어쓰기» 라 사람(HIL) 승인 — 실행하지 않고 안내만:
#   ssh mini 'cd ~/.hermes/hermes-agent && git checkout <OLD_SHA> && hermes gateway restart'   (설정이 마이그레이션됐으면 state.tgz 를 ~/.hermes 에 풀기)
#   로컬 수정 복원: ssh mini 'cd ~/.hermes/hermes-agent && git apply --3way <보존폴더>/local.patch'
set -uo pipefail

R="${R:-mini}"; DRY="${DRY:-0}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-hermes-mini] %s\n' "$*"; }
die() { printf '[h-hermes-mini] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rs() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$R" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }   # t = 호출 1회 상한(초)
HD='$HOME/.hermes'

say "0/4 사전점검 (R=$R DRY=$DRY)"
PRE="$(rs 25 'cd '"$HD"'/hermes-agent 2>/dev/null || { echo NOREPO; exit 0; }
echo "ver=$(hermes --version 2>&1 | head -1 | cut -c1-70)"
echo "head=$(git rev-parse HEAD)"
echo "branch=$(git branch --show-current)"
echo "mods=$(git diff HEAD --name-only | tr "\n" ";")"
echo "untracked=$(git ls-files --others --exclude-standard | head -20 | tr "\n" ";")"
echo "stash=$(git stash list | wc -l | tr -d " ")"
echo "svc=$(launchctl list 2>/dev/null | awk "\$3==\"ai.hermes.gateway\"{print (\$1==\"-\"?\"stopped\":\"running\")}")"
echo "active_agents=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser(\"~/.hermes/gateway_state.json\"))).get(\"active_agents\"))" 2>&1)"
echo "free_gb=$(df -g $HOME | tail -1 | awk "{print \$4}")"' 2>&1)" || die 2 "$R 접속/조회 실패"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -q '^NOREPO' && die 2 "원격에 ~/.hermes/hermes-agent 가 없다"
OLD_SHA="$(printf '%s\n' "$PRE" | sed -n 's/^head=//p')"; [ -n "$OLD_SHA" ] || die 2 "현재 sha 를 못 읽었다"
printf '%s\n' "$PRE" | grep -q '^svc=running' || die 2 "ai.hermes.gateway 가 running 이 아니다 — 먼저 현재 상태 확인"
printf '%s\n' "$PRE" | grep -q '^branch=main' || die 2 "mini 체크아웃이 main 이 아니다"
AA="$(printf '%s\n' "$PRE" | sed -n 's/^active_agents=//p')"; [ "$AA" = 0 ] || die 2 "진행 중인 에이전트 작업이 ${AA}건이다 — 끝난 뒤(재시작이 끊는다)"
FREE="$(printf '%s\n' "$PRE" | sed -n 's/^free_gb=//p')"; [ "${FREE:-0}" -ge 10 ] 2>/dev/null || die 2 "디스크 여유 ${FREE:-?}GB < 10GB"
NEW_SHA="$(rs 20 "cd $HD/hermes-agent && timeout 15 git ls-remote origin refs/heads/main 2>&1 | cut -f1")" || die 2 "원격 main 조회 실패"
[ ${#NEW_SHA} -eq 40 ] || die 2 "원격 main sha 이상: $NEW_SHA"
say "        현재 $OLD_SHA → 원격 main $NEW_SHA"
[ "$OLD_SHA" != "$NEW_SHA" ] || { say "이미 최신 — 할 일 없음 rc=0"; exit 0; }
MODS_BEFORE="$(printf '%s\n' "$PRE" | sed -n 's/^mods=//p')"
if [ "$DRY" = 1 ]; then
  say "DRY — 하려던 일(쓰기 0): 1 보존 ~/.hermes/backups/pre-update-<ts>/(state.tgz 핵심 파일·local.patch·untracked.tgz·sha.txt) → 2 nohup hermes update --yes(빠른 스냅샷만 · --backup 금지: ~/.hermes 36.9GB) 10초 폴링 → 3 게이트웨이 확인 → 4 증거(버전·sha·svc·슬랙 connected·수정 파일 복원 여부)"
  exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"; BK="$HD/backups/pre-update-$TS"
say "1/4 보존 → $BK"
rs 40 "umask 077; set -e; mkdir -p $BK; cd $HD
tar -czf $BK/state.tgz config.yaml auth.json channel_directory.json gateway_state.json cron.db 2>/dev/null || tar -czf $BK/state.tgz config.yaml auth.json gateway_state.json
cd $HD/hermes-agent; git diff HEAD > $BK/local.patch; git ls-files --others --exclude-standard | head -200 | tar -czf $BK/untracked.tgz -T - 2>/dev/null || true
printf 'old_sha=$OLD_SHA\nnew_sha=$NEW_SHA\nts=$TS\nmods=%s\n' '$MODS_BEFORE' > $BK/sha.txt; ls -l $BK | awk 'NR>1{print \$5, \$9}'" 2>&1 | sed 's/^/        /'
rs 10 "test -s $BK/state.tgz && test -s $BK/local.patch && test -s $BK/sha.txt" || die 3 "보존 파일이 비었다 — 업데이트 하지 않는다"

say "2/4 업데이트 시작(분리 실행)"
rs 15 "cd $HD/hermes-agent && nohup hermes update --yes </dev/null >$BK/update.log 2>&1 & echo \$! > $BK/update.pid; sleep 1; cat $BK/update.pid" >/dev/null || die 4 "update 시작 실패"
OK=0
for i in $(seq 1 90); do
  sleep 10
  ST="$(rs 7 "kill -0 \$(cat $BK/update.pid) 2>/dev/null && echo RUN || echo DONE; tail -1 $BK/update.log 2>/dev/null | cut -c1-110" 2>&1)" || ST="SSH?"
  [ $((i % 6)) = 0 ] && say "        ${i}0초 경과: $(printf '%s' "$ST" | tr '\n' ' ')"
  case "$ST" in DONE*) OK=1; break;; esac
done
[ "$OK" = 1 ] || die 4 "15분 안에 안 끝났다 — update.log: $BK/update.log (프로세스는 계속 돈다 · 끊지 않음)"
rs 10 "tail -8 $BK/update.log | cut -c1-140" 2>&1 | sed 's/^/        /'

say "3/4 게이트웨이 확인(hermes 가 이미 재시작했는지 — 시작 시각으로 판정)"
rs 25 "sleep 5; launchctl list | awk '\$3==\"ai.hermes.gateway\"{print \"pid=\" \$1}'; ps -o etime= -p \$(launchctl list | awk '\$3==\"ai.hermes.gateway\"{print \$1}') 2>/dev/null | tr -d ' '" 2>&1 | sed 's/^/        /'

say "4/4 증거"
EV="$(rs 45 'echo "ver=$(hermes --version 2>&1 | head -1 | cut -c1-70)"; echo "head=$(cd '"$HD"'/hermes-agent && git rev-parse HEAD)"
echo "svc=$(launchctl list 2>/dev/null | awk "\$3==\"ai.hermes.gateway\"{print (\$1==\"-\"?\"stopped\":\"running\")}")"
echo "mods_after=$(cd '"$HD"'/hermes-agent && git diff HEAD --name-only | tr "\n" ";")"
echo "state=$(python3 -c "import json,os;d=json.load(open(os.path.expanduser(\"~/.hermes/gateway_state.json\")));print(d.get(\"gateway_state\"),{k:v.get(\"state\") for k,v in d.get(\"platforms\",{}).items()})" 2>&1)"
echo "err_log=$(tail -200 '"$HD"'/logs/agent.log 2>/dev/null | grep -c -i traceback)"' 2>&1)" || EV="증거 수집 실패"
printf '%s\n' "$EV" | sed 's/^/        /'
FAIL=0
printf '%s\n' "$EV" | grep -q '^svc=running' || FAIL=1
printf '%s\n' "$EV" | grep -q "^head=$NEW_SHA" || FAIL=1
MODS_AFTER="$(printf '%s\n' "$EV" | sed -n 's/^mods_after=//p')"
if [ -n "$MODS_BEFORE" ] && [ "$MODS_AFTER" != "$MODS_BEFORE" ]; then
  say "        ⚠️ 로컬 수정 파일 목록이 달라졌다(전: $MODS_BEFORE / 후: ${MODS_AFTER:-없음}) — 복원 확인 필요: ssh mini 'cd ~/.hermes/hermes-agent && git apply --3way $BK/local.patch'"; FAIL=1
fi
if [ "$FAIL" = 0 ]; then say "완료 rc=0 — 새 sha · 서비스 running · 로컬 수정 파일 그대로. 슬랙 응답은 오빠가 한 번 확인"; exit 0; fi
say "증거 불일치 rc=5 — 코드는 바뀌었을 수 있다. 롤백(사람 승인 뒤): ssh mini 'cd ~/.hermes/hermes-agent && git checkout $OLD_SHA && hermes gateway restart'"
say "설정 되돌림: ssh mini 'tar -xzf $BK/state.tgz -C ~/.hermes'"
exit 5
