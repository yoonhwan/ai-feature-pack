#!/usr/bin/env bash
# test_nano_spawn_teamset_cap.sh — r-teamset-standard(판정 2170): ft-nano-spawn.sh 팀셋 나노 상한 칸 + ft-resource-reclaim.sh --only-prefix.
# 전부 mktemp — 임시 저장소·가짜 tmux(PATH)·가짜 TEAMSET·가짜 회수(FT_RECLAIM_SH)·가짜 센서. 실 좌석·실 워크트리·실 kill 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/scripts/fable-team-bin"; KIT="$REPO/scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
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
mkdir -p "$T/repo/.fable-team" && echo '{"_name":"alpha"}' > "$T/repo/.fable-team/seats-alpha.json"
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
sp() { ( cd "$T/repo" && export FT_NANO_PREFIX="byz-${PFX_TEAM:-alpha}-nano-" FT_SEATS_JSON="$T/repo/.fable-team/seats-alpha.json" FT_TEAMSET_MD="${MDX:-$MD}" FT_RECLAIM_SH="$T/reclaim.sh" \
  && PATH="$FAKE:$PATH" bash "$KIT/ft-nano-spawn.sh" design/alpha/indices/대기/x.md --from byz-alpha-master-claude#1 "$@" 2>&1 ); }
wts() { git -C "$T/repo" worktree list | wc -l | tr -d ' '; }

for f in ft-nano-spawn.sh ft-resource-reclaim.sh ft-nano-close.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 불일치 $f"; done

# ⓐ 상한 미만 → 통과(CAP 줄) · QUEUED 0 · 회수 호출 0
sess "byz-alpha-nano-a#0"; rm -f "$T/reclaim.calls"
o="$(sp --dry-run)"; { [[ "$o" == *"CAP alpha live=1 cap=2"* ]] && [[ "$o" != *QUEUED* ]] && [ ! -f "$T/reclaim.calls" ]; } && ok "ⓐ 상한 미만 → CAP 줄 · 회수 0 · QUEUED 0" || bad "ⓐ $o"

# ⓑ 상한 도달 + 회수가 1석 비움 → 회수 인자 확인(--caller·--need 1·--only-prefix) · 통과
sess "byz-alpha-nano-a#0" "byz-alpha-nano-b#0"; touch "$T/reclaim.free"; rm -f "$T/reclaim.calls"
o="$(sp)"; c="$(cat "$T/reclaim.calls" 2>/dev/null)"
{ [[ "$c" == *"--caller byz-alpha-master-claude#1"* ]] && [[ "$c" == *"--need 1"* ]] && [[ "$c" == *"--team alpha"* ]] && [[ "$o" != *QUEUED* ]] && [ "$(grep -c . "$T/reclaim.calls")" = 1 ]; } \
  && ok "ⓑ 상한 도달 → --team 으로 회수 1회 → 통과" || bad "ⓑ calls=«${c}» $o"

# ⓒ 상한 도달 + 회수 0 → QUEUED 순번=1 rc7 · 큐 1줄 · 워크트리·명부 변화 0
sess "byz-alpha-nano-a#0" "byz-alpha-nano-b#0"; rm -f "$T/reclaim.free" "$T/reclaim.calls" "$Q"
o="$(sp)"; rc=$?
{ [ "$rc" = 7 ] && [[ "$o" == *"QUEUED alpha 순번=1"* ]] && [ "$(grep -c . "$Q")" = 1 ] && [ "$(wts)" = 1 ] && [ ! -d "$T/repo/.worktrees" ]; } \
  && ok "ⓒ 회수 0 → QUEUED 순번=1 rc7 · 부작용 0" || bad "ⓒ rc=$rc $o"
o="$(sp)"; [[ "$o" == *"순번=1"* ]] && [ "$(grep -c . "$Q")" = 1 ] && ok "ⓒ 같은 카드 재시도 → 순번 그대로 · 중복 0" || bad "ⓒ-2 $o"

# ⓓ 다른 팀은 영향 0 — beta(상한 기본 3 · 라이브 0) 는 alpha 큐와 무관하게 통과
o="$(PFX_TEAM=beta sp --dry-run)"; [[ "$o" == *"CAP beta live=0 cap=3"* ]] && [[ "$o" != *QUEUED* ]] && ok "ⓓ 다른 팀(beta) 통과 — 일괄 정지 0" || bad "ⓓ $o"

# ⓔ --dry-run + 상한 도달 → rc7 · 큐 파일 불변 · 회수 호출 0
rm -f "$Q" "$T/reclaim.calls"; o="$(sp --dry-run)"; rc=$?
{ [ "$rc" = 7 ] && [[ "$o" == *"AT-CAP"* ]] && [ ! -f "$Q" ] && [ ! -f "$T/reclaim.calls" ]; } && ok "ⓔ dry-run 상한 도달 → rc7 · 큐·회수 0" || bad "ⓔ rc=$rc $o"

# ⓕ TEAMSET.md 파일 없음 → 눈에 보이는 WARN 후 통과 · 표가 깨졌으면 REJECT
o="$(MDX="$T/없는파일.md" sp --dry-run)"; { [[ "$o" == *"WARN TEAMSET.md 없음"* ]] && [[ "$o" != *QUEUED* ]]; } && ok "ⓕ 표 파일 없음 → WARN 후 통과(착지 전 호환)" || bad "ⓕ-1 $o"
printf '# 표 없음\n' > "$T/bad.md"; o="$(MDX="$T/bad.md" sp --dry-run)"; rc=$?; { [ "$rc" = 1 ] && [[ "$o" == *REJECT* ]]; } && ok "ⓕ 표 깨짐 → REJECT rc1" || bad "ⓕ-2 rc=$rc $o"

# ⓖ FT_TEAMSET=0 → 칸 건너뜀(출력 0)
o="$(FT_TEAMSET=0 sp --dry-run)"; [[ "$o" != *"alpha live="* ]] && ok "ⓖ FT_TEAMSET=0 → 상한 칸 건너뜀" || bad "ⓖ $o"

# ⓗ reclaim --only-prefix: 접두 밖 좌석은 후보에서 뺀다(사용법 문구 + 코드 실재)
grep -q -- '--team' "$BIN/ft-resource-reclaim.sh" && ok "ⓗ reclaim 에 --team 실재" || bad "ⓗ --team 없음"
o="$(PATH="$FAKE:$PATH" FT_RES_ROOT="$T/rr" bash "$BIN/ft-resource-reclaim.sh" --dry-run --caller x --need 1 --team alpha 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"RECLAIMED 0"* ]]; } && ok "ⓗ --team dry-run rc0 · 후보 0(가짜 tmux 에 활동 시각 없음)" || bad "ⓗ rc=$rc $o"

[ "$(git config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
