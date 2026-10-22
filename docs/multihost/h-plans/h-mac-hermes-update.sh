#!/usr/bin/env bash
# h-mac-hermes-update.sh — 이 맥 hermes 를 «loopback 패치(직접 만든 커밋)를 유지한 채» 원격 main 으로 올린다. 초안 · 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1
#   (2026-10-23 · aifp-multihost-master-claude#2 · 상위 #3266 · 오빠 결정 «loopback 패치 유지하고 올리기»)
#
# 이 맥의 특수 사정(mini·OCI 와 다름):
#   · 체크아웃이 main 이 아니라 local/cliproxy-loopback-base-url 이고, 그 위에 직접 만든 커밋 1개(6b4da78f · hermes_cli/runtime_provider.py +5줄 · anthropic base_url 가드의 loopback 예외)
#   · 수정 파일 6개 = 직접 고친 코드 3개(gateway/platforms/base.py +27 · gateway/run.py +14 · plugins/platforms/slack/adapter.py +32 — 미디어 전송 실패 알림 #66797)
#                    + npm install 흔적 3개(package.json · package-lock.json · apps/desktop/package.json — 의존성 고정값 자동 갱신 · 업데이트가 재설치로 다시 만든다)
#   · 게이트웨이 2개(default · zion) + 슬랙 mbox 인바운드·미러 launchd — 업데이트가 게이트웨이 둘을 재시작한다
#   · hermes 기본 정책(parked_branch_strategy=switch)은 «main 으로 갈아타고 직접 만든 커밋은 옛 브랜치에 남김» → 올린 코드에서 loopback 패치가 사라진다(cliproxy 경유 막힘).
#     공식 지원 경로 = updates.parked_branch_strategy: update_in_place — origin/main 을 «현재 브랜치에 병합»(병합 커밋 · 재정렬 아님 · 강제 0). 이 h 가 그 설정을 켠다.
#     단 «수정 중인 작업 트리» 는 건드리지 않고 업데이트를 SKIPPED 로 끝낸다 → 코드 3개는 «커밋으로 보존», npm 3개는 «stash 로 보존» 해서 트리를 깨끗하게 만든 뒤 돌린다.
#
# 단계: 0 사전점검(읽기) → 1 보존 → 2 준비(설정 1줄·커밋 1개·stash 1개) → 3 업데이트(분리 실행·폴링) → 4 증거 → 롤백 안내
#   0 의 «충돌 예보»: 원격 main 을 현재 브랜치(+코드 3개 수정)에 병합했을 때 충돌이 나는지 git merge-tree 로 «객체만 만들어» 미리 본다(작업 트리·브랜치·설정 불변). 충돌이면 여기서 중단(rc=2) — 아무것도 바꾸지 않는다.
#   0 의 «진행 중 작업 0»: 두 게이트웨이 active_agents 가 모두 0 일 때만(재시작이 끊는다).
# rc: 0 성공 · 2 사전점검 실패(쓰기 0) · 3 보존/준비 실패 · 4 업데이트 실패 · 5 증거 불일치(코드는 새 버전일 수 있음)
# ★삭제·덮어쓰기 0 — 브랜치·stash·커밋은 하나도 지우지 않는다(stash drop 0 · 브랜치 삭제 0).★
# ★롤백(사람 승인 · 이 스크립트는 실행하지 않고 출력만):
#   cd ~/.hermes/hermes-agent && git checkout -B local/cliproxy-loopback-base-url backup/h-mac-hermes-<ts> && git stash pop   # 브랜치를 보존 지점(원래 HEAD)으로, npm 수정 복원
#   cp ~/.hermes/config.yaml.bak-h-mac-<ts> ~/.hermes/config.yaml ; hermes gateway restart ; hermes -p zion gateway restart
set -uo pipefail

DRY="${DRY:-0}"
HD="$HOME/.hermes"; REPO="$HD/hermes-agent"
BRANCH_WANT="${BRANCH_WANT:-local/cliproxy-loopback-base-url}"
CARRIED_WANT="${CARRIED_WANT:-6b4da78f2749cb46bd8f096ca4f196541ab51005}"
CODE_FILES=(gateway/platforms/base.py gateway/run.py plugins/platforms/slack/adapter.py)
NPM_FILES=(package.json package-lock.json apps/desktop/package.json)
STATE_FILES=("$HD/gateway_state.json" "$HD/profiles/zion/gateway_state.json")
GW_LABELS=(ai.hermes.gateway ai.hermes.gateway-zion)
WATCH_LABELS=(com.hermes.byz-slack-mbox-inbound com.hermes.byz-slack-talk-inbound com.hermes.byz-mbox-slack-mirror com.hermes.byz-github-slack-mirror)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
say() { printf '[h-mac-hermes] %s\n' "$*"; }
die() { printf '[h-mac-hermes] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
g() { git -C "$REPO" "$@"; }
pidof_label() { launchctl list 2>/dev/null | awk -v l="$1" '$3==l{print $1}'; }

say "0/4 사전점검 (DRY=$DRY · 읽기 전용)"
[ -d "$REPO/.git" ] || die 2 "hermes 체크아웃이 없다: $REPO"
BR="$(g branch --show-current)"; HEAD_SHA="$(g rev-parse HEAD)"
[ "$BR" = "$BRANCH_WANT" ] || die 2 "체크아웃이 $BRANCH_WANT 가 아니다(현재 '$BR') — 이 계획서의 전제와 다르다"
g merge-base --is-ancestor "$CARRIED_WANT" HEAD 2>/dev/null || die 2 "직접 만든 커밋 ${CARRIED_WANT:0:8} 이 현재 HEAD 에 없다"
say "        브랜치 $BR · HEAD ${HEAD_SHA:0:8} · 직접 만든 커밋 ${CARRIED_WANT:0:8} 포함"
# 수정 파일은 «알려진 6개» 뿐이어야 한다 — 그 밖의 수정이 있으면 의도를 모르므로 중단
MODS="$(g diff HEAD --name-only | sort)"
KNOWN="$(printf '%s\n' "${CODE_FILES[@]}" "${NPM_FILES[@]}" | sort)"
EXTRA="$(comm -23 <(printf '%s\n' "$MODS") <(printf '%s\n' "$KNOWN") | sed '/^$/d')"
[ -z "$EXTRA" ] || die 2 "예상 밖 수정 파일이 있다 — 의도를 모르는 변경은 건드리지 않는다: $(printf '%s' "$EXTRA" | tr '\n' ' ')"
for f in "${CODE_FILES[@]}"; do g diff HEAD --quiet -- "$f" && say "        ⚠️ 코드 수정이 이미 없다: $f (커밋 단계에서 건너뜀)"; done
say "        수정 파일 $(printf '%s\n' "$MODS" | sed '/^$/d' | wc -l | tr -d ' ')개 모두 알려진 것(코드 ${#CODE_FILES[@]} + npm ${#NPM_FILES[@]} 범위 안) · stash $(g stash list | wc -l | tr -d ' ')개"
# 진행 중 작업 0
BUSY=""
for sf in "${STATE_FILES[@]}"; do
  AA="$(python3 -c "import json;print(json.load(open('$sf')).get('active_agents'))" 2>&1)"
  if [ "$AA" != 0 ]; then
    if [ "$DRY" = 1 ]; then BUSY="$BUSY $(basename "$(dirname "$sf")")(active_agents=$AA)"
    else die 2 "$(basename "$(dirname "$sf")")/$(basename "$sf") active_agents=$AA — 진행 중 작업이 있다(재시작이 끊는다). 끝난 뒤 다시"; fi
  fi
done
[ -z "${BUSY:-}" ] && say "        두 게이트웨이 active_agents=0" || say "        ⚠️ 지금은 진행 중 작업이 있다:${BUSY} — 실행(DRY 아님)이면 여기서 막힌다. 끝난 뒤 실행"
for l in "${GW_LABELS[@]}"; do [ -n "$(pidof_label "$l")" ] && [ "$(pidof_label "$l")" != "-" ] || die 2 "$l 이 running 이 아니다 — 먼저 현재 상태 확인"; done
WATCH_BEFORE=""; for l in "${WATCH_LABELS[@]}"; do p="$(pidof_label "$l")"; [ -n "$p" ] && [ "$p" != "-" ] && WATCH_BEFORE="$WATCH_BEFORE $l"; done
say "        슬랙 감시 launchd 가동 중:${WATCH_BEFORE:- 없음}"
FREE="$(df -g "$HOME" | tail -1 | awk '{print $4}')"; [ "${FREE:-0}" -ge 10 ] 2>/dev/null || die 2 "디스크 여유 ${FREE:-?}GB < 10GB"
# 원격 main sha (재시도 1회 · stderr 원문)
NEW_SHA=""
for try in 1 2; do
  LR="$(cd "$REPO" && timeout 15 git ls-remote origin refs/heads/main 2>&1; echo __rc=$?)"
  C="$(printf '%s\n' "$LR" | sed -n 's/^__rc=//p')"
  if [ "$C" = 0 ]; then NEW_SHA="$(printf '%s\n' "$LR" | awk 'NR==1{print $1}')"; [ ${#NEW_SHA} -eq 40 ] && break; fi
  say "        ls-remote 시도 $try 실패(rc=${C:-?}): $(printf '%s' "$LR" | grep -v '^__rc=' | tail -2 | tr '\n' ' ' | cut -c1-200)"; [ "$try" = 1 ] && sleep 3
done
[ ${#NEW_SHA} -eq 40 ] || die 2 "원격 main sha 를 읽지 못했다(2회 시도)"
HAVE="$(g cat-file -e "$NEW_SHA^{commit}" 2>/dev/null && echo yes || echo no)"
MB="$(g merge-base HEAD "$NEW_SHA" 2>/dev/null | cut -c1-8)"
say "        원격 main ${NEW_SHA:0:8} (이 맥에 객체 ${HAVE}) · 현재 브랜치와의 공통 조상 ${MB:-없음}"
# 현재 설정
CUR_STRAT="$(grep -E '^\s+parked_branch_strategy:' "$HD/config.yaml" | head -1 | awk '{print $2}')"
say "        updates.parked_branch_strategy 현재 값: ${CUR_STRAT:-미설정(기본 switch)}"
# 충돌 예보 — 객체만 만든다(ref·작업 트리·인덱스 불변): HEAD + 코드 수정 3개를 임시 인덱스로 커밋 객체화 → origin/main 과 merge-tree
FORECAST="skipped"
if [ "$HAVE" = yes ]; then
  TI="$(mktemp -d "${TMPDIR:-/tmp}/h-mac-idx.XXXXXX")"
  ( cd "$REPO" && export GIT_INDEX_FILE="$TI/idx" && git read-tree HEAD && for f in "${CODE_FILES[@]}"; do [ -f "$f" ] && git update-index --add --cacheinfo "100644,$(git hash-object -w "$f"),$f" 2>/dev/null; done
    T="$(git write-tree)"; C="$(git commit-tree "$T" -p HEAD -m forecast)"; echo "$C" > "$TI/commit" ) 2>"$TI/err" || { say "        예보 객체 만들기 실패: $(head -2 "$TI/err" | tr '\n' ' ' | cut -c1-160)"; }
  if [ -s "$TI/commit" ]; then
    MT="$(g merge-tree --write-tree "$(cat "$TI/commit")" "$NEW_SHA" 2>&1)"; MR=$?
    if [ "$MR" = 0 ]; then FORECAST="clean"; say "        충돌 예보 ✅ 병합 충돌 0 (직접 만든 커밋 + 코드 수정 3개 포함 · 원격 ${NEW_SHA:0:8})"
    else FORECAST="conflict"; say "        충돌 예보 ❌ 병합 충돌:"; printf '%s\n' "$MT" | grep -i -E "^CONFLICT|Auto-merging" | head -8 | sed 's/^/          /'; fi
  fi
  rm -rf "$TI"
else
  say "        충돌 예보: 원격 main 객체가 이 맥에 없다 → 실행 때 받은 뒤 같은 예보를 먼저 돌린다(충돌이면 아무것도 바꾸기 전에 중단)"
fi
[ "$FORECAST" != conflict ] || die 2 "충돌이 예상된다 — 사람이 결정(어느 쪽을 살릴지). 아무것도 바꾸지 않았다"

if [ "$DRY" = 1 ]; then
  say "DRY — 하려던 일(쓰기 0): 1 보존 ~/.hermes/backups/pre-update-mac-<ts>/(state·full.patch·code.patch·npm.patch·stash 목록·sha) + 보존 브랜치 backup/h-mac-hermes-<ts>(새 이름 · 삭제 0)"
  say "        2 준비: config.yaml 에 parked_branch_strategy: update_in_place 1줄(백업 .bak-h-mac-<ts>) · 코드 수정 3개를 «커밋 1개» 로 보존 · npm 3개는 stash 1개(drop 0) → 트리 깨끗"
  say "        3 hermes update --yes (분리 실행 · 10초 폴링 · 병합 커밋 생성 · 게이트웨이 2개 hermes 가 재시작) → 4 증거(브랜치 유지·새 main 포함·직접 만든 커밋 유지·두 게이트웨이 새 pid·슬랙 연결·감시 launchd 생존)"
  exit 0
fi

# ── 1) 보존 ─────────────────────────────────────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"; BK="$HD/backups/pre-update-mac-$TS"
say "1/4 보존 → $BK"
( umask 077; mkdir -p "$BK"
  tar -czf "$BK/state.tgz" -C "$HD" config.yaml auth.json gateway_state.json channel_directory.json profiles/zion/config.yaml profiles/zion/gateway_state.json 2>/dev/null || tar -czf "$BK/state.tgz" -C "$HD" config.yaml gateway_state.json
  g diff HEAD > "$BK/full.patch"; g diff HEAD -- "${CODE_FILES[@]}" > "$BK/code.patch"; g diff HEAD -- "${NPM_FILES[@]}" > "$BK/npm.patch"
  g stash list > "$BK/stash.txt"; printf 'old_head=%s\nbranch=%s\ncarried=%s\nnew_main=%s\nts=%s\n' "$HEAD_SHA" "$BR" "$CARRIED_WANT" "$NEW_SHA" "$TS" > "$BK/sha.txt" )
[ -s "$BK/state.tgz" ] && [ -s "$BK/full.patch" ] && [ -s "$BK/sha.txt" ] || die 3 "보존 파일이 비었다 — 아무것도 바꾸지 않았다"
g branch "backup/h-mac-hermes-$TS" "$HEAD_SHA" 2>&1 | sed 's/^/        /' ; g rev-parse --verify -q "backup/h-mac-hermes-$TS" >/dev/null || die 3 "보존 브랜치를 못 만들었다"
ls -l "$BK" | awk 'NR>1{print "        " $5, $9}'

# 원격 main 객체가 없었으면 지금 받는다(분리 실행) → 충돌 예보를 «바꾸기 전에» 다시
if [ "$HAVE" = no ]; then
  say "        원격 main 객체 받기(분리 실행 · 최대 5분)"
  ( cd "$REPO" && nohup timeout 280 git fetch --no-tags origin main </dev/null >"$BK/fetch.log" 2>&1 & echo $! > "$BK/fetch.pid" )
  for i in $(seq 1 60); do sleep 5; kill -0 "$(cat "$BK/fetch.pid")" 2>/dev/null || break; done
  g cat-file -e "$NEW_SHA^{commit}" 2>/dev/null || die 3 "fetch 후에도 ${NEW_SHA:0:8} 객체가 없다(원격이 그 사이 움직였을 수 있다 — 같은 h 다시). 아무것도 바꾸지 않았다. $(tail -2 "$BK/fetch.log" | tr '\n' ' ' | cut -c1-160)"
  TI="$(mktemp -d "${TMPDIR:-/tmp}/h-mac-idx.XXXXXX")"
  ( cd "$REPO" && export GIT_INDEX_FILE="$TI/idx" && git read-tree HEAD && for f in "${CODE_FILES[@]}"; do [ -f "$f" ] && git update-index --add --cacheinfo "100644,$(git hash-object -w "$f"),$f" 2>/dev/null; done
    T="$(git write-tree)"; C="$(git commit-tree "$T" -p HEAD -m forecast)"; echo "$C" > "$TI/commit" ) 2>/dev/null
  g merge-tree --write-tree "$(cat "$TI/commit")" "$NEW_SHA" >/dev/null 2>&1; MR=$?; rm -rf "$TI"
  [ "$MR" = 0 ] || die 3 "받은 뒤 충돌 예보가 충돌이다 — 아무것도 바꾸지 않았다(보존 폴더·보존 브랜치만 남음). 사람이 결정"
  say "        충돌 예보 ✅ (받은 뒤)"
fi

# ── 2) 준비 — 설정 1줄 · 코드 커밋 1개 · npm stash 1개 ─────────────────────────
say "2/4 준비 (설정·커밋·stash — 삭제 0)"
cp -p "$HD/config.yaml" "$HD/config.yaml.bak-h-mac-$TS"
python3 - "$HD/config.yaml" <<'PY' || die 3 "config.yaml 수정 실패(백업은 config.yaml.bak-h-mac-$TS)"
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read(); L = s.split("\n")
i = next((k for k, l in enumerate(L) if l == "updates:"), None)
if i is None: sys.exit("updates: 블록이 없다")
j = i + 1
while j < len(L) and (L[j].startswith("  ") or L[j] == ""): j += 1
blk = L[i + 1:j]
if any(re.match(r"\s+parked_branch_strategy:", l) for l in blk):
    L[i + 1 + next(k for k, l in enumerate(blk) if re.match(r"\s+parked_branch_strategy:", l))] = "  parked_branch_strategy: update_in_place"
else:
    L.insert(i + 1, "  parked_branch_strategy: update_in_place")
open(p, "w", encoding="utf-8").write("\n".join(L))
PY
grep -E '^\s+parked_branch_strategy:' "$HD/config.yaml" | sed 's/^/        설정: /'
g diff HEAD --quiet -- "${CODE_FILES[@]}" || {
  g add -- "${CODE_FILES[@]}" && g commit -q -m "[wip] 직접 고친 게이트웨이 미디어 전송 실패 알림(#66797) 보존 — h-mac-hermes $TS 가 업데이트 전에 커밋" -- "${CODE_FILES[@]}" || die 3 "코드 수정 커밋 실패 — 보존 브랜치 backup/h-mac-hermes-$TS 로 복구 가능"
  say "        코드 수정 3개 → 커밋 $(g rev-parse --short HEAD)"; }
g diff HEAD --quiet -- "${NPM_FILES[@]}" || {
  g stash push -q -m "h-mac-hermes-npm-$TS" -- "${NPM_FILES[@]}" || die 3 "npm 수정 stash 실패"
  say "        npm 수정 3개 → stash@{0} (h-mac-hermes-npm-$TS · drop 0)"; }
DIRTY="$(g status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
[ "$DIRTY" = 0 ] || die 3 "추적 파일 수정이 $DIRTY 개 남아 hermes 가 SKIPPED 로 끝낸다 — $(g status --porcelain --untracked-files=no | head -3 | tr '\n' ' ')"

# ── 3) 업데이트 (분리 실행 + 폴링) ─────────────────────────────────────────────
say "3/4 hermes update --yes 시작(분리 실행 — 의존성·웹 빌드·병합 · 게이트웨이 2개 재시작 포함)"
( cd "$REPO" && nohup hermes update --yes </dev/null >"$BK/update.log" 2>&1 & echo $! > "$BK/update.pid" ); sleep 1
OK=0
for i in $(seq 1 120); do   # 120 × 10초 = 20분 상한 (호출마다 ≤ 즉시)
  sleep 10
  kill -0 "$(cat "$BK/update.pid" 2>/dev/null)" 2>/dev/null || { OK=1; break; }
  [ $((i % 6)) = 0 ] && say "        ${i}0초 경과: $(tail -1 "$BK/update.log" | cut -c1-100)"
done
[ "$OK" = 1 ] || die 4 "20분 안에 안 끝났다 — $BK/update.log (프로세스는 계속 돈다 · 끊지 않음)"
tail -8 "$BK/update.log" | cut -c1-140 | sed 's/^/        /'
if grep -q -i "SKIPPED" "$BK/update.log"; then die 4 "hermes 가 코드 업데이트를 SKIPPED 했다(브랜치 정책/작업 트리) — 게이트웨이·코드 그대로. 로그 $BK/update.log · 준비 단계(설정·커밋·stash)는 남음: 롤백 안내 참고"; fi

# ── 4) 증거 ─────────────────────────────────────────────────────────────────
say "4/4 증거 (재시작 완료 대기 20초)"; sleep 20
FAIL=0
BR2="$(g branch --show-current)"; [ "$BR2" = "$BRANCH_WANT" ] && say "        브랜치 유지 ✅ $BR2" || { say "        브랜치가 바뀜 ❌ '$BR2'"; FAIL=1; }
g merge-base --is-ancestor "$NEW_SHA" HEAD 2>/dev/null && say "        새 main ${NEW_SHA:0:8} 포함 ✅ · HEAD $(g rev-parse --short HEAD)" || { say "        새 main 이 HEAD 에 안 들어옴 ❌ (원격이 그 사이 더 움직였으면 정상일 수 있음 — origin/main $(g rev-parse --short origin/main))"; FAIL=1; }
g merge-base --is-ancestor "$CARRIED_WANT" HEAD 2>/dev/null && say "        직접 만든 커밋 ${CARRIED_WANT:0:8} 유지 ✅" || { say "        직접 만든 커밋이 사라짐 ❌"; FAIL=1; }
for f in "${CODE_FILES[@]}"; do n="$(g diff origin/main -- "$f" | wc -l | tr -d ' ')"; say "        $f : origin/main 대비 ${n}줄 차이 ($([ "$n" -gt 0 ] && echo 직접 고친 코드 유지 || echo 상류가 같은 수정을 이미 포함))"; done
say "        hermes: $(hermes --version 2>&1 | head -1 | cut -c1-80)"
for l in "${GW_LABELS[@]}"; do p="$(pidof_label "$l")"; [ -n "$p" ] && [ "$p" != "-" ] && say "        $l running pid=$p" || { say "        $l ❌ running 아님"; FAIL=1; }; done
for sf in "${STATE_FILES[@]}"; do say "        $(basename "$(dirname "$sf")"): $(python3 -c "import json;d=json.load(open('$sf'));print(d.get('gateway_state'),{k:v.get('state') for k,v in d.get('platforms',{}).items()})" 2>&1)"; done
for l in $WATCH_BEFORE; do p="$(pidof_label "$l")"; [ -n "$p" ] && [ "$p" != "-" ] || { say "        감시 $l ❌ 사라짐"; FAIL=1; }; done
say "        슬랙 감시 launchd 생존 확인(전 ${WATCH_BEFORE:+있음})"
say "        stash 목록 $(g stash list | wc -l | tr -d ' ')개 (업데이트 전 +1 = npm 보존분 · drop 0)"
if [ "$FAIL" = 0 ]; then say "완료 rc=0 — 브랜치·직접 만든 커밋·코드 수정 유지, 새 main 포함, 게이트웨이 2개 가동. 슬랙 응답은 오빠가 한 번 확인"; exit 0; fi
say "증거 불일치 rc=5 — 위 ❌ 확인. 롤백(사람 승인): cd ~/.hermes/hermes-agent && git checkout -B $BRANCH_WANT backup/h-mac-hermes-$TS && git stash pop ; cp $HD/config.yaml.bak-h-mac-$TS $HD/config.yaml ; hermes gateway restart ; hermes -p zion gateway restart"
exit 5
