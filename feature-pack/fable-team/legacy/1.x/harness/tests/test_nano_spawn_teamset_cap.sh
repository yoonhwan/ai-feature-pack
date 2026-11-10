#!/usr/bin/env bash
# test_nano_spawn_teamset_cap.sh — r-teamset-standard(판정 2170): ft-nano-spawn.sh 팀셋 나노 상한 칸 + ft-resource-reclaim.sh --only-prefix.
# ★r921 — AT-CAP 은 «순번 큐» 가 아니라 «회수 1회 → 그래도 AT-CAP 이면 WARN 1줄 + 연다»(오빠 2026-10-25 «멈추지 마라»). 큐 적재 0.
# 전부 mktemp — 임시 저장소·가짜 tmux(PATH)·가짜 TEAMSET·가짜 회수(FT_RECLAIM_SH)·가짜 센서. 실 좌석·실 워크트리·실 kill 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'tmux_isolate_end; rm -rf "$T"' EXIT
. "$HERE/lib/tmux_isolate.sh"   # r957: 실 tmux 서버 격리 — 가짜 tmux 만 있고 가짜 tmuxc 가 없으면 진짜 tmuxc 가 불린다(실측)
. "$HERE/lib/fake_tmm.sh"; fake_tmm "$T/fake" byz-alpha-master-claude#1   # r975 r4: 살아 있는 좌석 목록 대역(둘 다 보존)
. "$HERE/lib/fake_resource_env.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

fake_resource_env "$T" ok
FAKE="$T/fake"; SESS="$T/sessions.txt"; MD="$T/TEAMSET.md"; mkdir -p "$FAKE"
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; has-session) exit 1;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
cat > "$MD" <<'EOF'
## 표 1 — 역할
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| nano | 상한 N | `sonnet-5-5` | high | — | a | b |
- 나노 상한 기본: 3
## 표 2 — 팀
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| alpha | 2 | 0 | 상시 |
EOF
git init -q "$T/repo" && git -C "$T/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$T/repo/.fable-team/comm" "$T/repo/.fable-team/state"   # r921: all-stop 판정이 state 폴더+원장 init 줄을 요구한다(픽스처 구멍 — 사전 결함)
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$T/repo/.fable-team/state/all-stop.log" && echo '{"_name":"alpha","_master":"byz-alpha-master-claude#1","byz-alpha-master-claude#1":{"role":"master"}}' > "$T/repo/.fable-team/seats-alpha.json"   # r975 반송 r1: 회신 대상 = 고정 명부의 현역 _master
mkdir -p "$T/repo/design/alpha/indices/대기" && echo "# 카드" > "$T/repo/design/alpha/indices/대기/x.md"
Q="$T/repo/.fable-team/state/spawn-queue-alpha.tsv"
# 가짜 회수: 인자를 기록하고 FREE 파일이 있으면 alpha 나노 1개를 목록에서 뺀다(= 끝난 나노를 닫았다)
cat > "$T/reclaim.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$T/reclaim.calls"
[ -f "$T/reclaim.free" ] && { grep -v '^byz-alpha-nano-a' "$SESS" > "$SESS.n"; mv "$SESS.n" "$SESS"; }
echo "RECLAIMED 1"
EOF
sess() { : > "$SESS"; for n in "$@"; do echo "$n" >> "$SESS"; done; }
sp() { ( cd "$T/repo" && export FT_ROOT="$T/repo" FT_NANO_PREFIX="byz-${PFX_TEAM:-alpha}-nano-" FT_SEATS_JSON="$T/repo/.fable-team/seats-alpha.json" FT_TEAMSET_MD="${MDX:-$MD}" FT_RECLAIM_SH="$T/reclaim.sh" \
  && PATH="$FAKE:$PATH" bash "$KIT/ft-nano-spawn.sh" design/alpha/indices/대기/x.md --from byz-alpha-master-claude#1 "$@" 2>&1 ); }
wts() { git -C "$T/repo" worktree list | wc -l | tr -d ' '; }

for f in ft-nano-spawn.sh ft-resource-reclaim.sh ft-nano-close.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 불일치 $f"; done

# ⓐ 상한 미만 → 통과(CAP 줄) · QUEUED 0 · 회수 호출 0
sess "byz-alpha-nano-a#0"; rm -f "$T/reclaim.calls"
o="$(sp --dry-run)"; { [[ "$o" == *"CAP alpha live=1 cap=2"* ]] && [[ "$o" != *QUEUED* ]] && [ ! -f "$T/reclaim.calls" ]; } && ok "ⓐ 상한 미만 → CAP 줄 · 회수 0 · QUEUED 0" || bad "ⓐ $o"

# ⓑ live=cap+1(3/2) + 회수가 1석 비움 → CAP 로 내려와 진행(QUEUED 0) · 회수 1회(--team)
sess "byz-alpha-nano-a#0" "byz-alpha-nano-b#0" "byz-alpha-nano-c#0"; touch "$T/reclaim.free"; rm -f "$T/reclaim.calls" "$Q"
o="$(sp)"; c="$(cat "$T/reclaim.calls" 2>/dev/null)"
{ [[ "$c" == *"--caller byz-alpha-master-claude#1"* ]] && [[ "$c" == *"--need 1"* ]] && [[ "$c" == *"--team alpha"* ]] && [[ "$o" != *QUEUED* ]] && [ "$(grep -c . "$T/reclaim.calls")" = 1 ]; } \
  && ok "ⓑ cap+1 → --team 으로 회수 1회 → CAP 로 내려와 진행" || bad "ⓑ calls=«${c}» $o"

# ⓒ live=cap(2/2) → 회수 없이 WARN + 진행(cap+1 까지 · 순번 큐 적재 0)
sess "byz-alpha-nano-a#0" "byz-alpha-nano-b#0"; rm -f "$T/reclaim.free" "$T/reclaim.calls" "$Q"
o="$(sp --dry-run)"; rc=$?
{ [[ "$o" == *"WARN resource teamset"*"cap+1"* ]] && [[ "$o" != *QUEUED* ]] && [ ! -f "$T/reclaim.calls" ] && [ ! -f "$Q" ]; } \
  && ok "ⓒ live=cap → WARN(cap+1) + 진행 · 회수·큐 0" || bad "ⓒ rc=$rc $o"

# ⓒ-2 live=cap+1 + 회수 0 → 순번 큐(QUEUED 순번=1 rc7) · 워크트리·명부 변화 0
sess "byz-alpha-nano-a#0" "byz-alpha-nano-b#0" "byz-alpha-nano-c#0"; rm -f "$T/reclaim.free" "$T/reclaim.calls" "$Q"
o="$(sp)"; rc=$?
{ [ "$rc" = 7 ] && [[ "$o" == *"QUEUED alpha 순번=1"* ]] && [ "$(grep -c . "$Q")" = 1 ] && [ "$(wts)" = 1 ] && [ ! -d "$T/repo/.worktrees" ]; } \
  && ok "ⓒ-2 cap+1 포화 → QUEUED 순번=1 rc7 · 부작용 0" || bad "ⓒ-2 rc=$rc $o"
o="$(sp)"; [[ "$o" == *"순번=1"* ]] && [ "$(grep -c . "$Q")" = 1 ] && ok "ⓒ-3 같은 카드 재시도 → 순번 그대로 · 중복 0" || bad "ⓒ-3 $o"

# ⓓ 다른 팀은 영향 0 — beta(상한 기본 3 · 라이브 0) 는 alpha 큐와 무관하게 통과
o="$(PFX_TEAM=beta sp --dry-run)"; [[ "$o" == *"CAP beta live=0 cap=3"* ]] && [[ "$o" != *QUEUED* ]] && ok "ⓓ 다른 팀(beta) 통과 — 일괄 정지 0" || bad "ⓓ $o"

# ⓔ --dry-run + cap+1 포화 → 계획만(DRY 줄) · 회수·큐 0
sess "byz-alpha-nano-a#0" "byz-alpha-nano-b#0" "byz-alpha-nano-c#0"; rm -f "$Q" "$T/reclaim.calls"; o="$(sp --dry-run)"; rc=$?
{ [[ "$o" == *"AT-CAP"* ]] && [[ "$o" == *"DRY AT-CAP"* ]] && [ ! -f "$Q" ] && [ ! -f "$T/reclaim.calls" ]; } && ok "ⓔ dry-run cap+1 → DRY 줄 · 회수·큐 0" || bad "ⓔ rc=$rc $o"

# ⓕ TEAMSET.md 파일 없음 → REJECT rc1(R351: «표 착지 전 호환» WARN 통과 분기 제거 — 조용한 통과 0) · 표가 깨졌으면 REJECT
o="$(MDX="$T/없는파일.md" sp --dry-run)"; rc=$?; { [[ "$o" == *"WARN 팀셋 측정 실패"* ]] && [[ "$o" != *"REJECT 팀셋"* ]] && [[ "$o" != *QUEUED* ]]; } && ok "r921 ⓕ-1 표 파일 없음 → WARN + 진행(정지 아님)" || bad "ⓕ-1 rc=$rc $o"
printf '# 표 없음\n' > "$T/bad.md"; o="$(MDX="$T/bad.md" sp --dry-run)"; rc=$?; { [[ "$o" == *"WARN 팀셋 측정 실패"* ]] && [[ "$o" != *"REJECT 팀셋"* ]]; } && ok "r921 ⓕ-2 표 깨짐 → WARN + 진행" || bad "ⓕ-2 rc=$rc $o"

# ⓖ FT_TEAMSET=0 → 칸 건너뜀(출력 0)
o="$(FT_TEAMSET=0 sp --dry-run)"; [[ "$o" != *"alpha live="* ]] && ok "ⓖ FT_TEAMSET=0 → 상한 칸 건너뜀" || bad "ⓖ $o"

# ⓗ reclaim --only-prefix: 접두 밖 좌석은 후보에서 뺀다(사용법 문구 + 코드 실재)
grep -q -- '--team' "$BIN/ft-resource-reclaim.sh" && ok "ⓗ reclaim 에 --team 실재" || bad "ⓗ --team 없음"
o="$(PATH="$FAKE:$PATH" FT_ROOT="$T/repo" FT_RES_ROOT="$T/rr" bash "$BIN/ft-resource-reclaim.sh" --dry-run --caller x --need 1 --team alpha 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"RECLAIMED 0"* ]]; } && ok "ⓗ --team dry-run rc0 · 후보 0(가짜 tmux 에 활동 시각 없음)" || bad "ⓗ rc=$rc $o"

[ "$(git -C "$REPO" config --get core.bare)" = false ]   # guard 재실행은 git 밖 cwd 로 간다 — 저장소를 명시한다(사전 결함 정정) && ok "core.bare=false" || bad "core.bare != false"
# ── r957 누수 검사: 실 tmux 서버에 시험 세션(byz-alpha-·byz-v65-·ft-v65-temp-)이 남으면 FAIL ──
tmux_isolate_leak_check || fail=$((fail+1))
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
