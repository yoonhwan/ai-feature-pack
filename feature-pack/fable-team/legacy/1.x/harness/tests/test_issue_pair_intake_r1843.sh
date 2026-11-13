#!/usr/bin/env bash
# test_issue_pair_intake_r1843.sh — 2.0 전환 팀 이슈 접수자 = 전환 표식 intake 칸(I1~I3) · 역할 intake 자기 알림 = 현역 풀기(I6) 반례 ①~⑤ ⑧~⑪ + 변이 M1~M8.
# 실 gh·실 우편함·실 명부·실 표식 0 — 임시 git 루트(FT_ROOT) · PATH 맨 앞 가짜 gh · 가짜 mbox(FT_MBOX_CMD · 인자 기록) · 가짜 봇 토큰 · sleep 0.
# 기준판 대조: FT_T_PAIR=<옛 판 경로> 를 주면 같은 반례를 옛 판에 돌린다(변이·cmp 는 건너뜀).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PAIR="${FT_T_PAIR:-$HERE/../bin/ft-issue-create-pair.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/root"; FT="$R/.fable-team"; SW="$FT/state/ft20-switch"; SENDS="$T/sends.log"
mkdir -p "$T/bin" "$SW"; git init -q "$R" || { echo "FAIL git init"; exit 1; }
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "issue create" ] && echo "https://github.com/o/r/issues/91"
exit 0
EOF
cat > "$T/mbox.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = send ] && printf '%s\t%s\n' "$2" "$3" >> "$FAKE_SENDS"
echo "QUEUED seq=7 stub"
EOF
chmod +x "$T/bin/gh" "$T/mbox.sh"
printf '증상: x\n담당 팀: harness-ops\n' > "$T/body.md"
unset FT_ISSUES_SEATS FT_ME
export PATH="$T/bin:$PATH" FAKE_SENDS="$SENDS" FT_ROOT="$R" FT_MBOX_CMD="$T/mbox.sh" FT_ISSUE_BOT_TOKEN="stub-bot"
NANO="byz-harness-nano-x#5"; PM="byz-planner-master-pi"

# world <표식 내용|NONE> <issues _master> — 표식·명부를 새로 쓴다
world() { rm -f "$SW"/issues.json*; [ "$1" = NONE ] || printf '%s' "$1" > "$SW/issues.json"
  printf '{"_master":"%s"}' "$2" > "$FT/seats-issues.json"; }
# run <스크립트> <등록 좌석> [--apply] → out · rc · n(send 줄 수)
run() { : > "$SENDS"; out="$(FT_ME="$2" bash "$1" "[harness] x" "$T/body.md" "${@:3}" 2>&1)"; rc=$?; n="$(wc -l < "$SENDS" | tr -d ' ')"; }
roster() { printf '{"_master":"","%s#200":{"role":"master"},"%s#199":{"role":"master","_replaced_by":"%s#200"}%s}' "$PM" "$PM" "$PM" "${1:-}" > "$FT/seats-planner.json"; }
I6='{"team":"issues","intake":"'"$PM"'"}'

c1() { world '{"team":"issues","intake":"byz-planner-desk-pi"}' ""; run "$1" "$NANO"
  [ $rc -eq 0 ] && grep -q "^DRY send to=byz-planner-desk-pi from=$NANO " <<<"$out"; }
c2() { world '{"team":"issues"}' X; run "$1" "$NANO"
  [ $rc -eq 2 ] && grep -q "^REJECT issue 접수자 없음 — 전환 팀 표식 .*/root/.fable-team/state/ft20-switch/issues.json 의 intake (사람 h 로 기록)$" <<<"$out" && ! grep -q 'to=X' <<<"$out"; }
c3() { world '{"team":"issues","intake":' X; run "$1" "$NANO"
  [ $rc -eq 2 ] && grep -q '^REJECT issue 접수자 없음 — 전환 팀 표식' <<<"$out" && ! grep -q 'to=X' <<<"$out"; }
c4() { world NONE Y; printf '{"intake":"W"}' > "$SW/issues.json.unmarked-20261113T000000"; run "$1" "$NANO"
  [ $rc -eq 0 ] && grep -q "^DRY send to=Y from=$NANO " <<<"$out"; }
c5() { world '{"team":"issues","intake":"byz-planner-desk-pi"}' ""; printf '{"_master":"Z"}' > "$T/alt.json"
  : > "$SENDS"; out="$(FT_ISSUES_SEATS="$T/alt.json" FT_ME="$NANO" bash "$1" "[harness] x" "$T/body.md" 2>&1)"; rc=$?
  [ $rc -eq 0 ] && grep -q "^DRY send to=Z from=$NANO " <<<"$out"; }
c8() { world "$I6" ""; roster; run "$1" "$PM#200" --apply
  [ $rc -eq 0 ] && [ "$n" = 0 ] && grep -q "^PAIR issue=#91 team=harness-ops manager=$PM 알림 0" <<<"$out"; }
c9() { world "$I6" ""; roster; run "$1" "$NANO" --apply
  [ $rc -eq 0 ] && [ "$n" = 1 ] && [ "$(cat "$SENDS")" = "$PM	$NANO" ]; }
c10() { world "$I6" ""; roster; run "$1" "$PM#199" --apply
  [ $rc -eq 0 ] && [ "$n" = 1 ] && [ "$(cat "$SENDS")" = "$PM	$PM#199" ]; }
c11() { world "$I6" ""; roster ',"'"$PM"'#201":{"role":"master"}'; run "$1" "$PM#200" --apply
  [ $rc -eq 0 ] && [ "$n" = 1 ] && [ "$(grep -c '^WARN intake 현역 판정 불가 — 알림 1$' <<<"$out")" = 1 ]; }

bash -n "$PAIR" && ok "bash -n" || bad "bash -n"
for c in 1 2 3 4 5 8 9 10 11; do c$c "$PAIR" && ok "반례 c$c" || bad "반례 c$c rc=$rc send=$n out=[$out]"; done
[ -n "${FT_T_PAIR:-}" ] && { echo "fail=$fail (기준판 · 변이 건너뜀)"; [ $fail -eq 0 ]; exit; }
cmp -s "$HERE/../bin/ft-issue-create-pair.sh" "$HERE/../kit/fable-team/bin/ft-issue-create-pair.sh" && ok "bin·kit cmp0" || bad "bin·kit 다름"

# mut <이름> <반례> <옛 글자> <새 글자> — 사본에서 글자 1곳을 바꾸고 그 반례가 FAIL 로 잡혀야 한다
mut() { python3 - "$PAIR" "$T/mut.sh" "$3" "$4" <<'EOF' || { bad "$1 사본 못 만듦(글자 1곳 아님)"; return; }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
sys.exit(1) if s.count(sys.argv[3]) != 1 else open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
EOF
  "c$2" "$T/mut.sh" && bad "$1 이 c$2 를 통과함" || ok "$1 → c$2 FAIL 잡힘"; }
mut M1 1 '[ -e "$SW" ]' 'false'
mut M2 2 '[ -n "$MANAGER" ] || die "issue 접수자 없음' '[ -n "$MANAGER" ] || MANAGER="$(jq -r "._master // empty" "$ISSUES_SEATS")"; [ -n "$MANAGER" ] || die "issue 접수자 없음'
mut M3 3 '[ -e "$SW" ]' 'jq -e . "$SW" >/dev/null 2>&1'
mut M4 4 '[ -e "$SW" ]' 'compgen -G "$SW*" >/dev/null'
mut M5 5 '[ -z "${FT_ISSUES_SEATS:-}" ] && ' ''
mut M6 8 '[ "$FROM" = "$LIVE" ]' '[ "$FROM" = "$MANAGER" ]'
mut M7 10 '[ "$FROM" = "$LIVE" ]' '[ "${FROM%#*}" = "$MANAGER" ]'
mut M8 11 '알림 1" >&2; }' '알림 1" >&2; exit 0; }'
echo "fail=$fail"; [ $fail -eq 0 ]
