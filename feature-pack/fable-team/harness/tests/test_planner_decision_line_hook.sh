#!/usr/bin/env bash
# test_planner_decision_line_hook.sh — R214(판정 1804): planner Stop 훅 planner-decision-line.sh.
# 임시 FT_ROOT · 가짜 도구(ft-decision-count 대역) · 가짜 transcript 만 쓴다 — 실 인박스·실 tmux 0. 시험에 GIT_* 없음(env -i).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK="${R214_HOOK:-$HERE/../../scripts/harness-install/hooks/planner-decision-line.sh}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
empty() { [ -z "$1" ] && ok "$2" || bad "$2 — 출력이 있다: ${1:0:200}"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }

mkdir -p "$T/.fable-team/state"
echo '{"_master":"byz-planner-master-claude#50"}' > "$T/.fable-team/seats-planner.json"
LINE="결정 인터뷰 3건 · 스크립트 1건 · 팀 대기 0건"
printf '#!/usr/bin/env bash\necho "%s"\n' "$LINE" > "$T/tool.sh"
printf '#!/usr/bin/env bash\necho boom >&2; exit 4\n' > "$T/tool-fail.sh"

tr() {  # <파일> <uuid> — 사용자 턴 1개 (assistant 본문은 입력 JSON 의 last_assistant_message 로 준다)
  printf '{"type":"user","uuid":"%s","message":{"content":"상황 보고"}}\n' "$2" > "$1"
}
hook() {  # <좌석> <session> <uuid> <최종 답변> [extra JSON 키] [도구]
  tr "$T/tr-$2.jsonl" "$3"
  local extra="${5:-}"; [ -n "$extra" ] || extra='{}'  # bash 3.2(/bin/bash)에서 ${5:-{}} 는 깨진다
  local input; input="$(python3 -c 'import json,sys;print(json.dumps({"session_id":sys.argv[1],"transcript_path":sys.argv[2],"last_assistant_message":sys.argv[3],**json.loads(sys.argv[4])}))' "$2" "$T/tr-$2.jsonl" "$4" "$extra")"
  printf '%s' "$input" | env -i PATH="/usr/bin:/bin:/opt/homebrew/bin" HOME="$T" FT_ROOT="$T" FT_SEAT="$1" FT_DECISION_SH="${6:-$T/tool.sh}" bash "$HOOK" 2>&1
}

echo "== ⓐ 첫 줄이 도구 값과 같다 → 통과(무출력)"
empty "$(hook 'byz-planner-master-claude#51' s1 u1 "$LINE"$'\n본문')" "맞는 첫 줄"

echo "== ⓑ 첫 줄 없음 → block 1회 · 사유 = 도구 줄 그대로"
o="$(hook 'byz-planner-master-claude#51' s2 u2 $'이번 턴 정리입니다')"
has "$o" '"decision": "block"' "block"; has "$o" "$LINE" "사유에 도구 줄"

echo "== ⓒ 숫자가 틀리면 block"
has "$(hook 'byz-planner-master-claude#51' s3 u3 '결정 인터뷰 9건 · 스크립트 1건 · 팀 대기 0건')" '"decision": "block"' "n 불일치"
has "$(hook 'byz-planner-master-claude#51' s4 u4 '결정 인터뷰 3건 · 스크립트 0건')" '"decision": "block"' "m 불일치"

echo "== ⓓ 같은 턴 2회째 → 통과(루프 0)"
empty "$(hook 'byz-planner-master-claude#51' s2 u2 $'이번 턴 정리입니다')" "같은 턴 키"
has "$(hook 'byz-planner-master-claude#51' s2 u2b $'다른 턴')" '"decision": "block"' "새 턴은 다시 block 1회"
empty "$(hook 'byz-planner-master-claude#51' s5 u5 '없음' '{"stop_hook_active": true}')" "stop_hook_active 면 통과"

echo "== ⓔ planner 아닌 좌석 → 무출력 통과"
empty "$(hook 'byz-v65-master-claude#9' s6 u6 '아무 말')" "다른 팀 좌석"

echo "== ⓕ 도구 실패 → 통과 + hook-errors.log 1줄"
empty "$(hook 'byz-planner-master-claude#51' s7 u7 '아무 말' '{}' "$T/tool-fail.sh")" "도구 실패 통과"
[ "$(grep -c 'planner-decision-line' "$T/.fable-team/state/hook-errors.log" 2>/dev/null)" = 1 ] && ok "로그 1줄" || bad "로그: $(cat "$T/.fable-team/state/hook-errors.log" 2>&1)"

bash -n "$HOOK" && ok "bash -n 훅" || bad "bash -n 훅"
echo; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAIL $fail"; exit 1; }
