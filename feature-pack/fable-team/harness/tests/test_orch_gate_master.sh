#!/bin/bash
# 시험: orchestration-gate 의 master 좌석 모드 (세션명 3번째 토큰 = master)
# 가짜 tmux 가 FAKE_SESSION 을 돌려준다. master 케이스 + 비-master 회귀(수정 전 훅 대조).
# r703: master 좌석 모드는 BYZ 프로젝트 훅에만 있다 — 대상은 BYZ 리포(FT_BYZ_REPO · 기본 = cwd 리포 LIVE_ROOT 1행)의
#       origin/main 훅 · 수정 전 훅 = 같은 리포 BASE_REV. 못 찾으면 FAIL rc1(건너뛰기 0).
HOOK=".claude/hooks/orchestration-gate.sh"
BASE_REV="${OLD_HOOK_REV:-43eb52ed632a}"   # 수정 전 훅이 있던 BYZ main 커밋
BYZ="${FT_BYZ_REPO:-}"
if [ -z "$BYZ" ]; then
  LR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/../.fable-team/LIVE_ROOT"
  [ -f "$LR" ] && BYZ="$(sed -n '1p' "$LR" | tr -d '\r')"
fi
[ -n "$BYZ" ] || { echo "FAIL BYZ 리포 못 찾음 — FT_BYZ_REPO 미지정 · cwd 리포 .fable-team/LIVE_ROOT 없음"; exit 1; }
git -C "$BYZ" cat-file -e "origin/main:$HOOK" 2>/dev/null || { echo "FAIL BYZ 리포 훅 없음 — $BYZ origin/main:$HOOK"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
NEW="$TMP/new-gate.sh"; OLD="$TMP/old-gate.sh"
git -C "$BYZ" show "origin/main:$HOOK" > "$NEW" || { echo "FAIL 대상 훅 추출 실패($BYZ origin/main)"; exit 1; }
git -C "$BYZ" show "$BASE_REV:$HOOK" > "$OLD" || { echo "FAIL 수정 전 훅 추출 실패($BYZ $BASE_REV)"; exit 1; }
mkdir -p "$TMP/bin"
printf '#!/bin/bash\necho "$FAKE_SESSION"\n' > "$TMP/bin/tmux"; chmod +x "$TMP/bin/tmux"

mk() {  # mk <tool> <input-key> <value> [extra-json-merge]
  python3 - "$@" <<'PY'
import json, sys
tool, key, val = sys.argv[1:4]
d = {"tool_name": tool, "tool_input": {key: val}, "session_id": "t-" + str(abs(hash(val)))}
if len(sys.argv) > 4: d.update(json.loads(sys.argv[4]))
print(json.dumps(d, ensure_ascii=False))
PY
}
run() {  # run <hook> <session|NONE> <json> -> exit code
  local hook=$1 sess=$2 json=$3
  if [ "$sess" = NONE ]; then
    printf '%s' "$json" | env -u TMUX_PANE TMPDIR="$TMP" bash "$hook" >/dev/null 2>&1
  else
    printf '%s' "$json" | env TMUX_PANE=%0 FAKE_SESSION="$sess" PATH="$TMP/bin:$PATH" TMPDIR="$TMP" bash "$hook" >/dev/null 2>&1
  fi
  echo $?
}

pass=0; fail=0
check() {  # check <이름> <기대> <실제>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1 → $3"; else fail=$((fail+1)); echo "FAIL $1 → 기대 $2 · 실제 $3"; fi
}

# ── master 케이스 (신 이름·옛 이름 둘 다) ──
for S in 'byz-v65-master-claude#143' 'ft-v65-master-claude#142'; do
  check "$S .worktrees ts Write"      2 "$(run "$NEW" "$S" "$(mk Write file_path '/r/.worktrees/x/a.ts')")"
  check "$S .worktrees html Edit"     2 "$(run "$NEW" "$S" "$(mk Edit file_path '/r/.worktrees/x/mock.html')")"
  check "$S 카드 진행 md Edit"        2 "$(run "$NEW" "$S" "$(mk Edit file_path '/r/design/v65/indices/진행/c.md')")"
  check "$S 카드 완성 md Edit"        2 "$(run "$NEW" "$S" "$(mk Edit file_path '/r/design/v65/indices/완성/c.md')")"
  check "$S 판정 문서 md Edit"        0 "$(run "$NEW" "$S" "$(mk Edit file_path '/r/design/harness/OPS-VERDICTS-20261006.md')")"
  check "$S 카드 대기 md Write"       0 "$(run "$NEW" "$S" "$(mk Write file_path '/r/design/v65/indices/대기/c.md')")"
  check "$S seats.json Edit"          0 "$(run "$NEW" "$S" "$(mk Edit file_path '/r/.fable-team/seats.json')")"
  check "$S Bash sed -i 코드"         2 "$(run "$NEW" "$S" "$(mk Bash command 'sed -i s/a/b/ .worktrees/x/a.py')")"
  check "$S Bash cp 훅 설치"          0 "$(run "$NEW" "$S" "$(mk Bash command 'cp a.sh ~/.claude/hooks/a.sh')")"
done

# ── 비-master: 신·구 훅 결과가 같아야 한다 (회귀 0) ──
echo "--- 회귀 대조표 (구 훅 = $BASE_REV) ---"
TOP='{"model":"claude-fable-5-1"}'
regress() {  # regress <이름> <기대> <session|NONE> <json> [env]
  local o n; o=$(run "$OLD" "$3" "$4"); n=$(run "$NEW" "$3" "$4")
  check "회귀 $1 (구=$o 신=$n)" "$2" "$n"; check "회귀 $1 구=신" "$o" "$n"
}
regress "arch html Edit"            0 'byz-harness-arch-claude#5' "$(mk Edit file_path '/r/.worktrees/x/mock.html')"
regress "arch ts Edit"              0 'byz-harness-arch-claude#5' "$(mk Edit file_path '/r/.worktrees/x/a.ts')"
regress "nano ts Edit"              0 'byz-harness-nano-foo#0'    "$(mk Edit file_path '/r/.worktrees/x/a.ts')"
regress "TMUX_PANE 없음 ts Edit"    0 NONE                        "$(mk Edit file_path '/r/.worktrees/x/a.ts')"
regress "agent_id 있는 ts Edit"     0 'byz-v65-master-claude#143' "$(mk Edit file_path '/r/a.ts' '{"agent_id":"w1"}')"
regress "TOP 모델 html Edit"        0 'byz-harness-arch-claude#5' "$(mk Edit file_path '/r/x/mock.html' "$TOP")"
regress "TOP 모델 .worktrees ts"    0 'byz-harness-arch-claude#5' "$(mk Edit file_path '/r/.worktrees/x/a.ts' "$TOP")"
OMC_GATE_MAX_CODE_FILES=0; export OMC_GATE_MAX_CODE_FILES
regress "TOP 모델 코드 한도 0 deny" 2 'byz-harness-arch-claude#5' "$(mk Edit file_path '/r/x/a.py' "$TOP")"
regress "TOP 모델 Bash sed -i deny" 2 'byz-harness-arch-claude#5' "$(mk Bash command 'sed -i s/a/b/ x/a.py' "$TOP")"
unset OMC_GATE_MAX_CODE_FILES

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
