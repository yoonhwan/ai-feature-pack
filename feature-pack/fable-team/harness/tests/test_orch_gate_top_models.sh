#!/bin/bash
# 시험: orchestration-gate 키트·두 번째 사본의 TOP_MODELS 기본값 정합 + 팩 안 사본 전부 = 정본(키트) cmp0
# Sonnet 5 · Fable = 오케(3번째 코드 파일 Edit exit 2) / Sonnet 5.5 · agent_id 있음 = 면제(exit 0).
# PROJ = 팩 안 두 번째 사본(skill/templates) — 1.1.0 재배치(3b25f81d) 뒤 옛 <팩>/.claude/hooks 자리는 없다(r699).
#   프로젝트에 설치된 사본을 보려면 ORCH_GATE_PROJ=<리포>/.claude/hooks/orchestration-gate.sh 로 준다.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$ROOT/harness/kit/fable-team/templates/hooks/orchestration-gate.sh"
PROJ="${ORCH_GATE_PROJ:-$ROOT/skill/templates/hooks/orchestration-gate.sh}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

transcript() {  # transcript <model> -> 경로 (마지막 assistant model 한 줄)
  local f="$TMP/tr-$1.jsonl"
  printf '{"type":"assistant","message":{"model":"%s"}}\n' "$1" > "$f"
  echo "$f"
}

edit_json() {  # edit_json <sid> <file> <transcript> [agent_id]
  python3 - "$@" <<'PY'
import json, sys
sid, path, tr = sys.argv[1:4]
d = {"tool_name": "Edit", "tool_input": {"file_path": path}, "session_id": sid, "transcript_path": tr}
if len(sys.argv) > 4: d["agent_id"] = sys.argv[4]
print(json.dumps(d))
PY
}

third_edit_rc() {  # third_edit_rc <hook> <model> [agent_id] -> 3번째 코드 파일 Edit 의 exit code
  local hook=$1 model=$2 agent=$3 tr sid rc
  tr=$(transcript "$model"); sid="s-$RANDOM-$RANDOM"
  for f in a b c; do
    edit_json "$sid" "/r/x/$f.py" "$tr" $agent | env -u TMUX_PANE -u TMUX TMPDIR="$TMP" /bin/bash "$hook" >/dev/null 2>&1
    rc=$?
  done
  echo "$rc"
}

pass=0; fail=0
check() {  # check <이름> <기대> <실제>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1 → $3"; else fail=$((fail+1)); echo "FAIL $1 → 기대 $2 · 실제 $3"; fi
}

for NAME in KIT PROJ; do
  HOOK="${!NAME}"
  bash -n "$HOOK" && check "$NAME bash -n" 0 0 || check "$NAME bash -n" 0 1
  check "$NAME Sonnet 5 3번째 Edit"     2 "$(third_edit_rc "$HOOK" 'claude-sonnet-5[1m]')"
  check "$NAME Sonnet 5.5 3번째 Edit"   0 "$(third_edit_rc "$HOOK" 'claude-sonnet-5-5[1m]')"
  check "$NAME Fable 3번째 Edit"        2 "$(third_edit_rc "$HOOK" 'claude-fable-5-1')"
  check "$NAME agent_id 있음 3번째 Edit" 0 "$(third_edit_rc "$HOOK" 'claude-fable-5-1' w1)"
done

# 팩 안 orchestration-gate.sh 사본(git ls-files) 전부 = 정본(KIT) cmp0 — 사본이 1벌뿐이면 단언이 빈 것이라 FAIL
copies=0; diff_copies=""
while IFS= read -r p; do
  copies=$((copies+1))
  cmp -s "$KIT" "$ROOT/$p" || diff_copies="$diff_copies $p"
done < <(git -C "$ROOT" ls-files -- '*orchestration-gate.sh')
check "사본 수 ≥ 2" yes "$([ "$copies" -ge 2 ] && echo yes || echo "no($copies)")"
check "팩 안 사본 전부 = 정본 cmp0" "" "$diff_copies"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
