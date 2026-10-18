#!/usr/bin/env bash
# test_seat_request.sh — C19 좌석 요청 생성기(ft-seat-request.sh) 시험.
# 가짜 tmux(FT_TMUX) · 가짜 gh(FT_GH) · fixture 명부(FT_SEATS_DIR)만 쓴다 — 실제 tmux·gh·seats-*.json 은 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GEN="$HERE/../../harness/bin/ft-seat-request.sh"
FX="$HERE/../fixtures/seat_request"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$GEN" && ok "bash -n" || bad "bash -n"

# 가짜 tmux: 호출 인자를 기록하고 fixture 세션 목록을 낸다 · 가짜 gh: 호출을 기록한다
cat >"$T/fake-tmux" <<S
#!/usr/bin/env bash
echo "\$*" >>"$T/tmux.log"
[ "\$1" = "list-sessions" ] || exit 9
cat "$FX/tmux-sessions.txt"
S
cat >"$T/fake-gh" <<S
#!/usr/bin/env bash
echo "\$*" >>"$T/gh.log"
[ "\${GH_TOKEN:-}" = "" ] || exit 7
cat "$FX/issues.json"
S
chmod +x "$T/fake-tmux" "$T/fake-gh"
export FT_SEATS_DIR="$FX/seats" FT_TMUX="$T/fake-tmux" FT_GH="$T/fake-gh"
before="$(cd "$FX/seats" && shasum *.json)"

# 1 혼합 fixture — 좌석 없는 팀만 골라낸다
out="$(bash "$GEN" --from-json "$FX/issues.json" 2>"$T/err")"; rc=$?
echo "$out"
[ $rc -eq 0 ] && ok "rc=0" || bad "rc=$rc $(cat "$T/err")"
row() { echo "$out" | grep "^team:$1 " | head -1; }
echo "$(row cfo)"          | grep -q '4 .*없음' && ok "cfo: 정지·교체 행만 → 좌석 없음 (4건)" || bad "cfo 행: $(row cfo)"
echo "$(row kk)"           | grep -q '1 .*없음' && ok "kk: 명부 master 행 있어도 tmux 에 없으면 좌석 없음" || bad "kk 행: $(row kk)"
echo "$(row planner)"      | grep -q '1 .*없음' && ok "planner: nano 만 살아 있으면 좌석 없음" || bad "planner 행: $(row planner)"
echo "$(row v65)"          | grep -q '2 .*있음.*ft-v65-master-claude#1' && ok "v65: 명부 master + 살아 있음 → 좌석 있음" || bad "v65 행: $(row v65)"
echo "$(row ccu)"          | grep -q '1 .*있음.*byz-ccu-arch-claude#0' && ok "ccu: 명부 밖 세션은 이름 토큰(arch)으로 좌석 있음" || bad "ccu 행: $(row ccu)"
echo "$(row shared-harness)" | grep -q '2 .*있음.*ft-harness-ops#3' && ok "shared-harness 별칭 → harness 좌석 있음 (nano 는 안 셈)" || bad "shared-harness 행: $(row shared-harness)"
echo "$out" | grep -q 'team 라벨 없음.*#999' && ok "team 라벨 없는 Issue 는 별도 행" || bad "라벨 없음 행"
echo "$out" | grep -q '^SEAT_REQUEST teams=6 missing=3 issues=6 send=0$' && ok "요약 teams=6 missing=3 issues=6 send=0" || bad "요약: $(echo "$out" | tail -1)"

# 2 planner 본문 — 3~5줄 · 좌석 있는 팀 미포함 · Issue 번호
body="$(echo "$out" | sed -n '/^--- planner/,/^SEAT_REQUEST/p' | sed '1d;$d')"
n=$(echo "$body" | wc -l | tr -d ' ')
[ "$n" -ge 3 ] && [ "$n" -le 5 ] && ok "본문 3~5줄 ($n)" || bad "본문 줄 수 $n"
echo "$body" | head -1 | grep -q '^\[좌석 필요\].* 3개 · Issue 6건' && ok "본문 첫 줄 = 좌석 필요 3팀 6건" || bad "본문 첫 줄: $(echo "$body" | head -1)"
echo "$body" | grep -q 'team:cfo 4건: #101,#102,#103,#602' && ok "본문에 cfo Issue 번호" || bad "본문 cfo 줄"
echo "$body" | grep -qE 'team:(v65|ccu|shared-harness)' && bad "좌석 있는 팀이 본문에 섞임" || ok "좌석 있는 팀은 본문에 없음"

# 3 읽기 전용 — gh 는 issue list 만 · tmux 는 list-sessions 만 · 명부 불변 · GH_TOKEN 제거 확인(fake-gh 가 있으면 exit 7)
GH_TOKEN=x bash "$GEN" >"$T/live.out" 2>"$T/err"; rc=$?
[ $rc -eq 0 ] && ok "gh 경로 rc=0 (GH_TOKEN 을 gh 에 넘기지 않음)" || bad "gh 경로 rc=$rc $(cat "$T/err")"
[ "$(sort -u "$T/gh.log")" = "issue list --state open --limit 1000 --json number,title,labels" ] && ok "gh 호출 = issue list 만" || bad "gh.log: $(sort -u "$T/gh.log")"
[ "$(sort -u "$T/tmux.log")" = "list-sessions -F #{session_name}" ] && ok "tmux 호출 = list-sessions 만" || bad "tmux.log: $(sort -u "$T/tmux.log")"
[ "$before" = "$(cd "$FX/seats" && shasum *.json)" ] && ok "입력 명부 불변" || bad "명부가 바뀜"

# 4 모든 팀에 좌석 있음 → 본문 없음
printf '[{"number":1,"title":"x","labels":[{"name":"team:v65"}]}]' >"$T/one.json"
o2="$(bash "$GEN" --from-json "$T/one.json" 2>&1)"
echo "$o2" | grep -q '좌석 필요 없음' && echo "$o2" | grep -q 'missing=0 issues=0 send=0' && ok "전 팀 좌석 있음 → 본문 없음" || bad "전 팀 좌석 있음: $o2"

# 5 실패는 REJECT (조용한 폴백 0): tmux 오류 · 깨진 JSON · 명부 없음 · usage
printf '#!/usr/bin/env bash\necho boom >&2; exit 1\n' >"$T/boom"; chmod +x "$T/boom"
FT_TMUX="$T/boom" bash "$GEN" --from-json "$FX/issues.json" >/dev/null 2>&1 && bad "tmux 오류가 통과함" || ok "tmux 오류 → exit 1"
printf '#!/usr/bin/env bash\necho "no server running on /tmp/x" >&2; exit 1\n' >"$T/noserver"; chmod +x "$T/noserver"
FT_TMUX="$T/noserver" bash "$GEN" --from-json "$FX/issues.json" 2>&1 | grep -q 'teams=6 missing=6 ' && ok "tmux 서버 없음 → 세션 0 (6팀 전부 좌석 없음)" || bad "서버 없음"
printf '{bad' >"$T/bad.json"
bash "$GEN" --from-json "$T/bad.json" >/dev/null 2>&1; [ $? -eq 1 ] && ok "JSON 깨짐 → exit 1" || bad "JSON 깨짐"
FT_SEATS_DIR="$T/none" bash "$GEN" --from-json "$FX/issues.json" >/dev/null 2>&1; [ $? -eq 1 ] && ok "명부 디렉터리 없음 → exit 1" || bad "명부 없음"
printf '#!/usr/bin/env bash\nexit 4\n' >"$T/ghfail"; chmod +x "$T/ghfail"
FT_GH="$T/ghfail" bash "$GEN" >/dev/null 2>&1; [ $? -eq 1 ] && ok "gh 실패 → exit 1" || bad "gh 실패"
bash "$GEN" --zzz >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage → exit 2" || bad "usage"

echo "fail=$fail"; [ $fail -eq 0 ]
