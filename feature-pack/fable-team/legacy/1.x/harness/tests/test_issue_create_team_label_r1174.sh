#!/usr/bin/env bash
# test_issue_create_team_label_r1174.sh — ft-issue-create-pair.sh team 라벨(이슈팀 §5-2 순서) 반례 R1~R8 + 변이 1.
# 실 gh·실 우편함 0 — PATH 맨 앞 가짜 gh(인자 기록) · 가짜 mbox(FT_MBOX_CMD) · 가짜 봇 토큰 · 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PAIR="$HERE/../bin/ft-issue-create-pair.sh"
KIT="$HERE/../kit/fable-team/bin/ft-issue-create-pair.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"; LOG="$T/gh.log"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "issue create" ] && echo "https://github.com/o/r/issues/77"
exit 0
EOF
printf '#!/usr/bin/env bash\necho "QUEUED seq=5 stub"\n' > "$T/mbox.sh"
chmod +x "$T/bin/gh" "$T/mbox.sh"
echo '{"_master":"mgr#1"}' > "$T/seats-issues.json"
printf '증상: x\n' > "$T/plain.md"
printf '증상: x\n담당 팀: lecture\n' > "$T/lecture.md"
export STUB_LOG="$LOG" PATH="$T/bin:$PATH" FT_ISSUES_SEATS="$T/seats-issues.json" FT_MBOX_CMD="$T/mbox.sh" FT_ISSUE_BOT_TOKEN="stub-bot"
SEAT="byz-harness-master-claude#137"

# run <스크립트> <등록 좌석> <제목> <본문> [--apply] → out · rc · args(가짜 gh 의 issue create 인자)
run() { : > "$LOG"; out="$(FT_ME="$2" bash "$1" "$3" "$4" "${@:5}" 2>&1)"; rc=$?; args="$(grep '^issue create' "$LOG")"; }
# want_label <라벨> <이름> — rc0 · gh 인자에 --label 정확히 그 값 · PAIR 줄 team=
want_label() {
  [ $rc -eq 0 ] && grep -qF -- "--label team:$1 --body-file" <<<"$args" && grep -q "^PAIR issue=#77 team=$1 " <<<"$out" \
    && ! grep -q '^TEAM-HOLD' <<<"$out" && ok "$2 → team:$1" || bad "$2 → rc=$rc args=[$args] out=[$out]"
}
# want_hold <이름> — rc0 · --label 0 · TEAM-HOLD 정확히 1줄 · PAIR team=보류(알림은 그대로)
want_hold() {
  [ $rc -eq 0 ] && [ -n "$args" ] && ! grep -q -- '--label' <<<"$args" && [ "$(grep -c '^TEAM-HOLD ' <<<"$out")" = 1 ] \
    && grep -q '^PAIR issue=#77 team=보류 ' <<<"$out" && ok "$1 → 보류: $(grep '^TEAM-HOLD' <<<"$out")" || bad "$1 → rc=$rc args=[$args] out=[$out]"
}

bash -n "$PAIR" && ok "bash -n" || bad "bash -n"
run "$PAIR" "$SEAT" "[v65] x" "$T/lecture.md" --apply;          want_label lecture   "R1 본문 담당 팀(순 1)"
run "$PAIR" "$SEAT" "[harness] x" "$T/plain.md" --apply;        want_label harness-ops "R2 [harness] 별칭"
run "$PAIR" "$SEAT" "[Mobile] x" "$T/plain.md" --apply;         want_label room      "R3 [Mobile] 대소문자·별칭"
run "$PAIR" "$SEAT" "[v65][lecture] x" "$T/plain.md" --apply;   want_hold "R4 접두 2개";      grep -q '^TEAM-HOLD 제목 접두 2개' <<<"$out" && ok "R4 이유" || bad "R4 이유: $out"
run "$PAIR" "byz-ops-master-claude#73" "r1173 x" "$T/plain.md" --apply; want_label ops "R5 접두 0 · 좌석 팀(순 3)"
run "$PAIR" "byz-planner-desk-claude#84" "r1173 x" "$T/plain.md" --apply; want_hold "R6 접수자 좌석"; grep -q '^TEAM-HOLD 접수자 좌석' <<<"$out" && ok "R6 이유" || bad "R6 이유: $out"
run "$PAIR" "$SEAT" "[unknown] x" "$T/plain.md" --apply;        want_hold "R7 명단 밖 접두"; grep -q '^TEAM-HOLD 명단 밖 접두: \[unknown\]' <<<"$out" && ok "R7 이유" || bad "R7 이유: $out"
run "$PAIR" "$SEAT" "[harness] x" "$T/plain.md"
[ $rc -eq 0 ] && grep -qF "DRY gh issue create --title '[harness] x' --label team:harness-ops --body-file" <<<"$out" && [ ! -s "$LOG" ] \
  && ok "R8 DRY 줄 = 같은 라벨 · gh 호출 0" || bad "R8 DRY → rc=$rc out=[$out] log=[$(cat "$LOG")]"
# 순 3 좌석 이름: 나노(역할 뒤 긴 꼬리) · issues 팀 = 접수자
run "$PAIR" "byz-harness-nano-r1174-issue-create-pair-team-label#0" "r1174 x" "$T/plain.md" --apply; want_label harness-ops "순 3 나노 좌석 harness"
run "$PAIR" "byz-issues-master-claude#38" "r x" "$T/plain.md" --apply; want_hold "순 3 issues 좌석"

cmp -s "$PAIR" "$KIT" && ok "bin·kit cmp0" || bad "bin·kit 다름"

# 변이: gh 줄의 --label 인자를 지운 사본 → R2 가 FAIL 로 잡혀야 한다
sed 's/ \${LABEL\[@\]+"\${LABEL\[@\]}"}//' "$PAIR" > "$T/mut.sh"
if cmp -s "$PAIR" "$T/mut.sh"; then bad "변이 사본이 원본과 같다(sed 미적용)"; else
  before=$fail; run "$T/mut.sh" "$SEAT" "[harness] x" "$T/plain.md" --apply; want_label harness-ops "변이 R2" >/dev/null
  [ $fail -gt $before ] && { fail=$before; ok "변이(--label 삭제) → R2 FAIL 잡힘"; } || bad "변이가 R2 를 통과함"
fi

echo "fail=$fail"; [ $fail -eq 0 ]
