#!/usr/bin/env bash
# h-mac-hermes-swap.sh — 이 맥 hermes 체크아웃을 «재이식 브랜치(local/cliproxy-loopback-v2)» 로 교체하고 올린다. 초안 · 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1
#   (2026-10-23 · aifp-multihost-master-claude#2 · 상위 #3269 · 오빠 결정 «재이식 GO · 침묵 접두사는 동작이 다르면 32줄 그대로 이식»)
#   전제(끝남): 별도 사본 ~/.hermes-port/hermes-agent-port 의 브랜치 local/cliproxy-loopback-v2 = 새 main 41dfcf2c 위 커밋 2개
#     3ebb06a560 loopback 예외+미디어 실패 알림 · 906227f14f 슬랙 침묵 접두사 가드  — 시험 117 passed(팀장 재실행) · 슬랙 어댑터 회귀 516 passed(나노)
#   이 h 가 하는 일 (라이브 ~/.hermes/hermes-agent):
#     0 사전점검(읽기): 현재 브랜치·HEAD · 사본 브랜치 sha 일치 · 사본 시험 재실행 · 두 게이트웨이 active_agents=0 · 디스크
#     1 보존: 상태 tar · 전체 patch · stash 목록 · «현재 작업 트리까지 담은 커밋» 을 보존 브랜치 backup/h-mac-pre-swap-<ts> 로(HEAD·작업 트리는 안 건드림)
#     2 가져오기: 사본의 브랜치를 라이브 저장소로 fetch(로컬 경로 · 네트워크 0) — 이미 같은 이름이 있으면 sha 가 같을 때만
#     3 교체: 수정 6파일을 stash(추가만 · drop 0) → 브랜치 local/cliproxy-loopback-v2 로 checkout → 추적 파일 깨끗 확인
#     4 올리기: config 에 updates.parked_branch_strategy: update_in_place(백업) → hermes update --yes(분리 실행 · 폴링 · 의존성 설치·웹 빌드·필요하면 더 새 main 병합 · 게이트웨이 2개 hermes 가 재시작)
#     5 증거: 브랜치·HEAD 에 사본 커밋 2개 포함 · venv 파이썬으로 loopback 가드 호출(True/False) · 침묵 접두사 함수 · 게이트웨이 2개 새 pid·슬랙 connected · 감시 launchd 생존 · 옛 브랜치/stash 그대로
# rc: 0 성공 · 2 사전점검 실패(쓰기 0) · 3 보존/교체 실패(되돌림 안내) · 4 업데이트 실패 · 5 증거 불일치
# ★삭제 0 — 옛 브랜치 local/cliproxy-loopback-base-url · 기존 stash 3개 · 보존 브랜치 · 사본 모두 그대로. (stash drop 0 · branch -D 0)★
# ★위험 1개★: 3 에서 코드만 새 것으로 바뀐 뒤 4 의 의존성 설치가 실패하면, 게이트웨이(메모리의 옛 코드)는 계속 돌지만 launchd 가 다시 띄우면 새 코드+옛 의존성이다.
#   → 4 가 실패하면(rc=4) 즉시 아래 «되돌림»을 사람 승인으로 먼저 한다. (이 h 는 4 실패 시 게이트웨이를 건드리지 않는다.)
# ★되돌림(사람 승인 · 출력만)★:
#   cd ~/.hermes/hermes-agent && git checkout local/cliproxy-loopback-base-url && git stash apply 'stash^{/h-mac-swap-<ts>}'   # 이름으로 지정(맨 위가 아닌 다른 stash 를 잘못 꺼내지 않음) · apply 라 stash 는 남는다
#   cp ~/.hermes/config.yaml.bak-h-mac-swap-<ts> ~/.hermes/config.yaml ; hermes gateway restart ; hermes -p zion gateway restart
set -uo pipefail

DRY="${DRY:-0}"
HD="$HOME/.hermes"; REPO="$HD/hermes-agent"
PORT="$HOME/.hermes-port/hermes-agent-port"
OLD_BRANCH="local/cliproxy-loopback-base-url"; NEW_BRANCH="local/cliproxy-loopback-v2"
PORT_SHA_WANT="${PORT_SHA_WANT:-906227f14f}"      # 사본 브랜치 HEAD 앞 10자리
WANT_COMMITS=(3ebb06a560 906227f14f)
TRACK_FILES=(apps/desktop/package.json gateway/platforms/base.py gateway/run.py package-lock.json package.json plugins/platforms/slack/adapter.py)
STATE_FILES=("$HD/gateway_state.json" "$HD/profiles/zion/gateway_state.json")
GW_LABELS=(ai.hermes.gateway ai.hermes.gateway-zion)
WATCH_LABELS=(com.hermes.byz-slack-mbox-inbound com.hermes.byz-slack-talk-inbound com.hermes.byz-mbox-slack-mirror com.hermes.byz-github-slack-mirror)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
say() { printf '[h-mac-swap] %s\n' "$*"; }
die() { printf '[h-mac-swap] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
g() { git -C "$REPO" "$@"; }
pidof_label() { launchctl list 2>/dev/null | awk -v l="$1" '$3==l{print $1}'; }

say "0/5 사전점검 (DRY=$DRY)"
[ -d "$REPO/.git" ] && [ -d "$PORT/.git" ] || die 2 "라이브($REPO) 또는 사본($PORT)이 없다"
BR="$(g branch --show-current)"; HEAD_SHA="$(g rev-parse HEAD)"
[ "$BR" = "$OLD_BRANCH" ] || { [ "$BR" = "$NEW_BRANCH" ] && say "        이미 $NEW_BRANCH 위에 있다 — 4(올리기)부터 이어간다" || die 2 "라이브 체크아웃이 $OLD_BRANCH 도 $NEW_BRANCH 도 아니다('$BR')"; }
PBR="$(git -C "$PORT" branch --show-current)"; PHEAD="$(git -C "$PORT" rev-parse HEAD)"
[ "$PBR" = "$NEW_BRANCH" ] && [ "${PHEAD:0:${#PORT_SHA_WANT}}" = "$PORT_SHA_WANT" ] || die 2 "사본 브랜치/sha 가 기대와 다르다(브랜치 $PBR · HEAD ${PHEAD:0:10} ≠ $PORT_SHA_WANT) — 사본이 바뀌었으면 다시 점검한 뒤 PORT_SHA_WANT 를 갱신"
[ -z "$(git -C "$PORT" status --porcelain --untracked-files=no)" ] || die 2 "사본에 커밋 안 된 변경이 있다"
for c in "${WANT_COMMITS[@]}"; do git -C "$PORT" merge-base --is-ancestor "$c" HEAD || die 2 "사본에 기대한 커밋 $c 가 없다"; done
say "        라이브 $BR@${HEAD_SHA:0:8} · 사본 $PBR@${PHEAD:0:10} (커밋 ${#WANT_COMMITS[@]}개 확인)"
MODS="$(g diff HEAD --name-only | sort)"; EXTRA="$(comm -23 <(printf '%s\n' "$MODS") <(printf '%s\n' "${TRACK_FILES[@]}" | sort) | sed '/^$/d')"
[ -z "$EXTRA" ] || die 2 "예상 밖 수정 파일: $(printf '%s' "$EXTRA" | tr '\n' ' ') — 의도를 모르는 변경은 건드리지 않는다"
say "        라이브 수정 파일 $(printf '%s\n' "$MODS" | sed '/^$/d' | wc -l | tr -d ' ')개(알려진 6개 범위) · stash $(g stash list | wc -l | tr -d ' ')개"
# 사본 시험 재실행 (정지 상태에서 20초대)
TR="$(cd "$PORT" && PYTHONDONTWRITEBYTECODE=1 timeout 120 /opt/homebrew/bin/pytest -q -p no:cacheprovider tests/gateway/test_slack_silence_prefix.py tests/gateway/test_media_delivery_failure_notice_on_exception.py tests/hermes_cli/test_runtime_provider_resolution.py 2>&1 | tail -1)"
printf '%s' "$TR" | grep -q "passed" && ! printf '%s' "$TR" | grep -q "failed" || die 2 "사본 시험이 통과하지 않는다: $TR"
say "        사본 시험: $TR"
BUSY=""
for sf in "${STATE_FILES[@]}"; do
  AA="$(python3 -c "import json;print(json.load(open('$sf')).get('active_agents'))" 2>&1)"
  if [ "$AA" != 0 ]; then
    if [ "$DRY" = 1 ]; then BUSY="$BUSY $(basename "$(dirname "$sf")")(active_agents=$AA)"; else die 2 "$(basename "$(dirname "$sf")") active_agents=$AA — 진행 중 작업이 있다(재시작이 끊는다). 끝난 뒤 다시"; fi
  fi
done
[ -z "$BUSY" ] && say "        두 게이트웨이 active_agents=0" || say "        ⚠️ 지금은 진행 중 작업이 있다:${BUSY} — DRY 가 아닌 실행이면 여기서 막힌다"
for l in "${GW_LABELS[@]}"; do p="$(pidof_label "$l")"; [ -n "$p" ] && [ "$p" != "-" ] || die 2 "$l 이 running 이 아니다"; done
WATCH_BEFORE=""; for l in "${WATCH_LABELS[@]}"; do p="$(pidof_label "$l")"; [ -n "$p" ] && [ "$p" != "-" ] && WATCH_BEFORE="$WATCH_BEFORE $l"; done
say "        슬랙 감시 launchd 가동 중:${WATCH_BEFORE:- 없음}"
FREE="$(df -g "$HOME" | tail -1 | awk '{print $4}')"; [ "${FREE:-0}" -ge 10 ] 2>/dev/null || die 2 "디스크 여유 ${FREE:-?}GB < 10GB"
if [ "$DRY" = 1 ]; then
  say "DRY — 하려던 일(쓰기 0): 1 보존(~/.hermes/backups/pre-swap-mac-<ts>/ + 보존 브랜치 backup/h-mac-pre-swap-<ts>) → 2 사본 브랜치 fetch → 3 stash(6파일)+checkout $NEW_BRANCH → 4 config update_in_place + hermes update --yes → 5 증거"
  exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"; BK="$HD/backups/pre-swap-mac-$TS"
if [ "$BR" = "$OLD_BRANCH" ]; then
  say "1/5 보존 → $BK"
  ( umask 077; mkdir -p "$BK"
    tar -czf "$BK/state.tgz" -C "$HD" config.yaml auth.json gateway_state.json channel_directory.json profiles/zion/config.yaml profiles/zion/gateway_state.json 2>/dev/null || tar -czf "$BK/state.tgz" -C "$HD" config.yaml gateway_state.json
    g diff HEAD > "$BK/full.patch"; g stash list > "$BK/stash.txt"; printf 'old_branch=%s\nold_head=%s\nport_head=%s\nts=%s\n' "$BR" "$HEAD_SHA" "$PHEAD" "$TS" > "$BK/sha.txt" )
  [ -s "$BK/state.tgz" ] && [ -s "$BK/full.patch" ] && [ -s "$BK/sha.txt" ] || die 3 "보존 파일이 비었다 — 아무것도 바꾸지 않았다"
  # 작업 트리까지 담은 커밋 객체 → 보존 브랜치 (HEAD·인덱스·작업 트리 불변: 임시 인덱스)
  TI="$(mktemp -d "${TMPDIR:-/tmp}/h-mac-swap-idx.XXXXXX")"
  C="$( cd "$REPO" && export GIT_INDEX_FILE="$TI/idx" && git read-tree HEAD && for f in "${TRACK_FILES[@]}"; do [ -f "$f" ] && git update-index --add --cacheinfo "100644,$(git hash-object -w "$f"),$f" 2>/dev/null; done; git commit-tree "$(git write-tree)" -p HEAD -m "h-mac-swap $TS 보존(작업 트리 포함)" )" || die 3 "보존 커밋 객체 만들기 실패"
  g branch "backup/h-mac-pre-swap-$TS" "$C" || die 3 "보존 브랜치를 못 만들었다"
  say "        보존 브랜치 backup/h-mac-pre-swap-$TS → ${C:0:10} (현재 HEAD + 수정 6파일 포함)"
  ls -l "$BK" | awk 'NR>1{print "        " $5, $9}'

  say "2/5 사본 브랜치 가져오기(로컬 fetch)"
  if g rev-parse --verify -q "refs/heads/$NEW_BRANCH" >/dev/null; then
    [ "$(g rev-parse "refs/heads/$NEW_BRANCH")" = "$PHEAD" ] || die 3 "라이브에 이미 $NEW_BRANCH 가 있고 sha 가 사본과 다르다 — 사람이 판단(덮어쓰지 않음)"
    say "        라이브에 이미 같은 sha 로 있음"
  else
    g fetch -q --no-tags "$PORT" "$NEW_BRANCH:refs/heads/$NEW_BRANCH" || die 3 "fetch 실패 — 아무것도 바뀌지 않았다(보존 브랜치만 추가됨)"
  fi
  g merge-base --is-ancestor "${WANT_COMMITS[1]}" "refs/heads/$NEW_BRANCH" || die 3 "가져온 브랜치에 기대한 커밋이 없다"

  say "3/5 교체 — 수정 6파일 stash(추가만) → checkout $NEW_BRANCH"
  g stash push -q -m "h-mac-swap-$TS" -- "${TRACK_FILES[@]}" || die 3 "stash 실패 — 되돌림 불필요(체크아웃 안 바뀜)"
  g checkout -q "$NEW_BRANCH" 2>&1 | sed 's/^/        /'
  [ "$(g branch --show-current)" = "$NEW_BRANCH" ] || { g stash pop -q 2>/dev/null; die 3 "checkout 실패 — stash 를 되돌렸다"; }
  [ -z "$(g status --porcelain --untracked-files=no)" ] || die 3 "교체 후 추적 파일이 깨끗하지 않다: $(g status --porcelain --untracked-files=no | head -3 | tr '\n' ' ')"
  say "        $NEW_BRANCH@$(g rev-parse --short HEAD) 위 · 추적 파일 깨끗 · stash $(g stash list | wc -l | tr -d ' ')개(+1)"
fi

say "4/5 올리기 — config update_in_place + hermes update --yes(분리 실행)"
cp -p "$HD/config.yaml" "$HD/config.yaml.bak-h-mac-swap-$TS" 2>/dev/null
python3 - "$HD/config.yaml" <<'PY' || die 3 "config.yaml 수정 실패(백업 config.yaml.bak-h-mac-swap-$TS)"
import re, sys
p = sys.argv[1]; L = open(p, encoding="utf-8").read().split("\n")
i = next((k for k, l in enumerate(L) if l == "updates:"), None)
if i is None: sys.exit("updates: 블록이 없다")
j = i + 1
while j < len(L) and (L[j].startswith("  ") or L[j] == ""): j += 1
blk = L[i + 1:j]
k = next((n for n, l in enumerate(blk) if re.match(r"\s+parked_branch_strategy:", l)), None)
if k is None: L.insert(i + 1, "  parked_branch_strategy: update_in_place")
else: L[i + 1 + k] = "  parked_branch_strategy: update_in_place"
open(p, "w", encoding="utf-8").write("\n".join(L))
PY
mkdir -p "$BK" 2>/dev/null
( cd "$REPO" && nohup hermes update --yes </dev/null >"$BK/update.log" 2>&1 & echo $! > "$BK/update.pid" ); sleep 1
OK=0
for i in $(seq 1 120); do
  sleep 10
  kill -0 "$(cat "$BK/update.pid" 2>/dev/null)" 2>/dev/null || { OK=1; break; }
  [ $((i % 6)) = 0 ] && say "        ${i}0초 경과: $(tail -1 "$BK/update.log" | cut -c1-100)"
done
[ "$OK" = 1 ] || die 4 "20분 안에 안 끝났다 — $BK/update.log (프로세스는 계속 돈다 · 끊지 않음)"
tail -8 "$BK/update.log" | cut -c1-140 | sed 's/^/        /'
if grep -q -i "SKIPPED" "$BK/update.log"; then die 4 "hermes 가 코드 업데이트를 SKIPPED 했다 — 게이트웨이는 건드리지 않았다. ★되돌림(헤더)을 사람 승인으로 먼저★. 로그 $BK/update.log"; fi

say "5/5 증거 (재시작 완료 대기 20초)"; sleep 20
FAIL=0
[ "$(g branch --show-current)" = "$NEW_BRANCH" ] && say "        브랜치 유지 ✅ $NEW_BRANCH@$(g rev-parse --short HEAD)" || { say "        브랜치가 바뀜 ❌ '$(g branch --show-current)'"; FAIL=1; }
for c in "${WANT_COMMITS[@]}"; do g merge-base --is-ancestor "$c" HEAD 2>/dev/null && say "        이식 커밋 $c 유지 ✅" || { say "        이식 커밋 $c 사라짐 ❌"; FAIL=1; }; done
SM="$("$REPO/venv/bin/python" - <<'PY' 2>&1 | tail -2
import sys
sys.path.insert(0, ".")
from hermes_cli.runtime_provider import _anthropic_base_url_override_ok as f
print("loopback_guard", f("http://127.0.0.1:8317"), f("https://evil.example.com/"))
PY
)"
( cd "$REPO" && "$REPO/venv/bin/python" -c "
import importlib.util
s=importlib.util.spec_from_file_location('sl','plugins/platforms/slack/adapter.py'); print('adapter_file_ok')" ) >/dev/null 2>&1
say "        venv 파이썬 가드 호출: $SM  (기대: loopback_guard True False)"
printf '%s' "$SM" | grep -q "loopback_guard True False" || FAIL=1
say "        hermes: $(hermes --version 2>&1 | head -1 | cut -c1-80)"
for l in "${GW_LABELS[@]}"; do p="$(pidof_label "$l")"; [ -n "$p" ] && [ "$p" != "-" ] && say "        $l running pid=$p" || { say "        $l ❌ running 아님"; FAIL=1; }; done
for sf in "${STATE_FILES[@]}"; do say "        $(basename "$(dirname "$sf")"): $(python3 -c "import json;d=json.load(open('$sf'));print(d.get('gateway_state'),{k:v.get('state') for k,v in d.get('platforms',{}).items()})" 2>&1)"; done
for l in $WATCH_BEFORE; do p="$(pidof_label "$l")"; [ -n "$p" ] && [ "$p" != "-" ] || { say "        감시 $l ❌ 사라짐"; FAIL=1; }; done
say "        옛 브랜치 $OLD_BRANCH $(g rev-parse --verify -q "refs/heads/$OLD_BRANCH" >/dev/null && echo 그대로 ✅ || echo 없음 ❌) · stash $(g stash list | wc -l | tr -d ' ')개 · 보존 브랜치 $(g branch --list 'backup/h-mac-pre-swap-*' | wc -l | tr -d ' ')개"
if [ "$FAIL" = 0 ]; then say "완료 rc=0 — 이식 브랜치 위에서 새 main 으로 올라감, loopback 가드·침묵 접두사 유지, 게이트웨이 2개 가동. 슬랙에서 «— 메모» 와 일반 메시지 1회씩 확인(오빠 손 1회)"; exit 0; fi
say "증거 불일치 rc=5 — 위 ❌ 확인. 되돌림(사람 승인): cd ~/.hermes/hermes-agent && git checkout $OLD_BRANCH && git stash apply 'stash^{/h-mac-swap-$TS}' ; cp $HD/config.yaml.bak-h-mac-swap-$TS $HD/config.yaml ; hermes gateway restart ; hermes -p zion gateway restart"
exit 5
