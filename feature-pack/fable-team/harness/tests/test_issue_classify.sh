#!/usr/bin/env bash
# test_issue_classify.sh — C16 ft-issue-classify.sh · ft-issue-create-pair.sh 시험
# fixture JSON 과 --dry-run 만 쓴다 — gh 쓰기·mbox 발신·--apply 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
FX="$HERE/../fixtures/issue_classify"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_NOW=1791244800   # 2026-10-06T00:00:00Z — fixture 생성 2026-10-04T00:00:00Z 와 정확히 2일
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
row() { printf '%s\n' "$OUT" | grep "^#$1 "; }

bash -n "$BIN/ft-issue-classify.sh" && bash -n "$BIN/ft-issue-create-pair.sh" && ok "bash -n 2종" || bad "bash -n"

# 4 경로 fixture 를 한 배열로
jq -s 'add' "$FX"/path*.json > "$T/all.json"
OUT="$(bash "$BIN/ft-issue-classify.sh" --from-json "$T/all.json" 2>"$T/err")"; rc=$?
[ $rc -eq 0 ] && ok "분류기 rc=0" || bad "분류기 rc=$rc $(cat "$T/err")"
echo "$OUT"
row 101 | grep -q '| ① 기획 세션 | 그대로 | 미발견 · 나이 2일0시간 |' && ok "경로① 분류·분기·미발견 나이" || bad "경로① $(row 101)"
row 102 | grep -q '| ② 세션 에이전트 | 반려 | 발견 +5시간 |' && ok "경로② 반려 · 발견 지연 5시간" || bad "경로② $(row 102)"
row 103 | grep -q '| ③ 오빠 GitHub | 보완 | 미발견 · 나이 2일0시간 |' && ok "경로③ 보완 · 미발견" || bad "경로③ $(row 103)"
row 104 | grep -q '| ④ 사내 멤버 | 보완 | 발견 +5시간 |' && ok "경로④ 보완 · 발견 지연 5시간" || bad "경로④ $(row 104)"
row 102 | grep -q '라벨 from:member\|본문 마커 ft-origin: seat' && ok "근거 열 = 마커" || bad "근거 열 없음"
printf '%s\n' "$OUT" | grep -q '^SUMMARY total=4 ①=1 ②=1 ③=1 ④=1 미분류=0 보완=2 반려=1 그대로=1 미발견=2$' && ok "SUMMARY 한 줄" || bad "SUMMARY"

# login 은 판단에 쓰지 않는다 — author 를 바꿔도 결과 동일
sed 's/"login": *"yoonhwan"/"login":"someone-else"/' "$T/all.json" > "$T/author.json"
[ "$(bash "$BIN/ft-issue-classify.sh" --from-json "$T/author.json")" = "$OUT" ] && ok "login 무관" || bad "login 이 결과를 바꿈"

# 경계: 마커 없음=미분류 · body null · 라벨 6 계열이 다 있으면 그대로 · 사람 등록이 라벨 다 있어도 그대로
cat > "$T/edge.json" <<'EOF'
[{"number":201,"title":"마커 없음","labels":[],"body":null,"createdAt":"2026-10-05T12:00:00Z","comments":[]},
 {"number":202,"title":"라벨 완비 사내 멤버","labels":[{"name":"type:bug"},{"name":"status:needs-triage"},{"name":"team:v65"},{"name":"scope:main"},{"name":"phase:pre-completion"},{"name":"priority:p1"},{"name":"from:member"}],"body":"","createdAt":"2026-10-05T12:00:00Z","comments":[]}]
EOF
OUT="$(bash "$BIN/ft-issue-classify.sh" --from-json "$T/edge.json" 2>&1)"
row 201 | grep -q '| 미분류 | 그대로 | 미발견 · 나이 12시간 | 마커 없음 |' && ok "미분류 · body null · 나이 12시간" || bad "201: $(row 201)"
row 202 | grep -q '| ④ 사내 멤버 | 그대로 |' && ok "라벨 완비면 보완 0" || bad "202: $(row 202)"

# 경로① 변형: BOARD 행 표 「| 골좌표 |」 · 제목 줄 「## 골좌표 + 닫는 증거」(실측 모양)
cat > "$T/board.json" <<'EOF'
[{"number":301,"title":"BOARD 표","labels":[],"body":"| 항목 | 값 |\n|---|---|\n| 골좌표 | M7 ↑ |\n","createdAt":"2026-10-05T12:00:00Z","comments":[]},
 {"number":302,"title":"제목 줄","labels":[],"body":"## 골좌표 + 닫는 증거\nM5\n","createdAt":"2026-10-05T12:00:00Z","comments":[]}]
EOF
OUT="$(bash "$BIN/ft-issue-classify.sh" --from-json "$T/board.json" 2>&1)"
row 301 | grep -q '| ① 기획 세션 | 그대로 |.*| BOARD 행 표 골좌표 |' && ok "BOARD 표 행 = ①" || bad "301: $(row 301)"
row 302 | grep -q '| ① 기획 세션 | 그대로 |.*| planner_task 칸 골좌표 + 닫는 증거 |' && ok "제목 줄 = ①" || bad "302: $(row 302)"

# 오류: 없는 파일 · 배열 아닌 JSON · 모르는 옵션
bash "$BIN/ft-issue-classify.sh" --from-json "$T/none.json" >/dev/null 2>&1; [ $? -eq 2 ] && ok "없는 파일 exit 2" || bad "없는 파일 rc"
echo '{"a":1}' > "$T/obj.json"; bash "$BIN/ft-issue-classify.sh" --from-json "$T/obj.json" >/dev/null 2>&1; [ $? -eq 2 ] && ok "배열 아님 exit 2" || bad "배열 아님 rc"
bash "$BIN/ft-issue-classify.sh" --bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "모르는 옵션 exit 2" || bad "옵션 rc"

# 쌍 래퍼 — 기본 dry-run
echo '{"_master":"ft-issue-manager#0"}' > "$T/seats-issues.json"
printf '증상: x\n' > "$T/body.md"
export FT_ISSUES_SEATS="$T/seats-issues.json" FT_ME="ft-test-seat#0"
OUT="$(bash "$BIN/ft-issue-create-pair.sh" "[bug] 시험 제목" "$T/body.md" 2>"$T/err")"; rc=$?
[ $rc -eq 0 ] && ok "pair dry-run rc=0" || bad "pair rc=$rc $(cat "$T/err")"
printf '%s\n' "$OUT" | grep -q "^DRY gh issue create --title '\[bug\] 시험 제목' --body-file" && ok "gh 명령 줄" || bad "gh 줄: $OUT"
printf '%s\n' "$OUT" | grep -q '^DRY send to=ft-issue-manager#0 from=ft-test-seat#0 body=\[Issue 등록\] Issue #<번호> 등록' && ok "알림 1통 · 번호 자리표시" || bad "알림 줄: $OUT"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 3 ] && printf '%s\n' "$OUT" | grep -q '^TEAM-HOLD 명단 밖 접두: \[bug\]' && ok "출력 3줄(r1174 TEAM-HOLD 1 · 명령 1 · 알림 1)" || bad "줄 수"
printf '%s\n' "$OUT" | grep -q '`' && bad "백틱(mbox 가드 위반)" || ok "백틱 0"

# 쌍 래퍼 — 수신자 없음 raise(폴백 0) · 입력 오류
FT_ISSUES_SEATS="$T/none.json" bash "$BIN/ft-issue-create-pair.sh" "t" "$T/body.md" >/dev/null 2>&1; [ $? -eq 2 ] && ok "매니저 행 없음 REJECT" || bad "매니저 행 없음 허용됨"
echo '{}' > "$T/empty-seats.json"
FT_ISSUES_SEATS="$T/empty-seats.json" bash "$BIN/ft-issue-create-pair.sh" "t" "$T/body.md" >/dev/null 2>&1; [ $? -eq 2 ] && ok "_master 비면 REJECT" || bad "_master 비어도 허용됨"
bash "$BIN/ft-issue-create-pair.sh" "t" "$T/nope.md" >/dev/null 2>&1; [ $? -eq 2 ] && ok "본문 파일 없음 exit 2" || bad "본문 파일 rc"
bash "$BIN/ft-issue-create-pair.sh" >/dev/null 2>&1; [ $? -eq 2 ] && ok "인자 없음 exit 2" || bad "인자 없음 rc"
# 쌍 래퍼 — --apply 에 봇 토큰이 없으면 raise(오빠 계정 폴백 0)
env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE="$T/no-token-file" bash "$BIN/ft-issue-create-pair.sh" "t" "$T/body.md" --apply >/dev/null 2>"$T/err2"; rc=$?
[ $rc -eq 2 ] && grep -q '봇 토큰 없음' "$T/err2" && ok "봇 토큰 없음 --apply REJECT" || bad "봇 토큰 없는데 진행됨 rc=$rc"
# 보내는 좌석 불명이면 raise (tmux 밖 · FT_ME 없음)
env -u FT_ME -u TMUX FT_ISSUES_SEATS="$T/seats-issues.json" bash "$BIN/ft-issue-create-pair.sh" "t" "$T/body.md" >/dev/null 2>&1; [ $? -eq 2 ] && ok "보내는 좌석 불명 REJECT" || bad "좌석 불명 허용됨"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
