#!/usr/bin/env bash
# test_proposal_gate_issue_head_r1751.sh — ft-proposal-gate.sh --card 의 머리 「- Issue:」 번호는 «값 머리» `#N` 에서만 읽는다(r1751).
#   «없음 — … desk #289360» 같은 설명 속 쪽지 번호를 Issue 로 읽어 spawn 을 막던 결함의 반례 ①~④.
#   가짜 gh 만(_proposal_issue_env.sh 재사용 · Issue 8000 = proposal 라벨 · 8001 = 라벨 없음 · 그 밖 = rc1) — 실 gh·sleep 0.
#   GATE=<경로> 로 기준판·변이 사본을 돌린다(기본 = kit 판).
set -uo pipefail
# shellcheck source=_proposal_issue_env.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/_proposal_issue_env.sh"
GATE="${GATE:-$HERE/../../harness/kit/fable-team/bin/ft-proposal-gate.sh}"
bash -n "$GATE" && ok "bash -n" || bad "bash -n"

printf '#!/usr/bin/env bash\necho "$*" >> "%s/gh.log"; exec bash "%s/fake-gh.sh" "$@"\n' "$T" "$T" > "$T/gh-log.sh"
export FT_GH_READ="bash $T/gh-log.sh" FT_GATE_GH_TIMEOUT=2
printf '{"number":8000,"author":{"login":"byz-tank"},"labels":[{"name":"proposal"}],"body":"x","comments":[]}' > "$T/view-8000.json"
printf '{"number":8001,"author":{"login":"yoonhwan"},"labels":[],"body":"x","comments":[]}' > "$T/view-8001.json"

card() {  # card <Issue 줄> <제안서 줄>
  printf '# 인덱스: c\n%s\n%s\n- 상태: 대기\n## 구현 범위\nx\n' "$1" "$2" > "$T/c.md"; }
run() { : > "$T/gh.log"; out="$(bash "$GATE" --card "$T/c.md" 2>&1)"; rc=$?; ghn="$(wc -l < "$T/gh.log" | tr -d ' ')"; }
expect() {  # <이름> <rc> <출력 패턴> [gh 호출 수 · 생략 = 보지 않음]
  if [ "$rc" = "$2" ] && echo "$out" | grep -qE "$3" && { [ -z "${4:-}" ] || [ "$ghn" = "$4" ]; }; then ok "$1"; else bad "$1 :: rc=$rc gh=$ghn out=$out"; fi; }

card "- Issue: 없음 — 오빠 직접 지시(desk #289360) · master 가 이슈 생성/연결" "- 제안서: 없음 — 사유"; run
expect "① Issue 「없음 — … desk #289360」 → OK 제안서 없음 선언 · gh 0" 0 '^OK 제안서 없음 선언' 0
card "- Issue: (master) · 참고 #289360" "- 제안서: 없음 — 사유"; run
expect "② Issue 「(master) · 참고 #289360」 → OK · gh 0" 0 '^OK 제안서 없음 선언' 0
card "- Issue: #8000" "- 제안서: 없음 — 사유"; run
expect "③ Issue #8000(proposal 라벨) → REJECT 우회 차단 그대로" 1 '^REJECT 머리 - Issue: #8000 가 proposal 라벨 Issue' 1
card "- Issue: #8001 (오빠 착수 «네»)" "- 제안서: 없음 — 사유"; run
expect "④ Issue 「#8001 (…)」(라벨 없음) → OK 그대로" 0 '^OK 제안서 없음 선언' 1

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
