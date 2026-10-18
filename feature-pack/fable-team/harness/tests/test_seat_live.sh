#!/usr/bin/env bash
# test_seat_live.sh — C2 명부 생성기(ft-seat-live.sh) · test_bundle lint 시험.
# 가짜 tmux(FT_TMUX) · 임시 명부 디렉터리(FT_SEATS_DIR)만 쓴다 — 실제 tmux 세션·seats-*.json 은 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
GEN="$BIN/ft-seat-live.sh"; TBL="$BIN/ft-test-bundle-lint.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$GEN" && bash -n "$TBL" && ok "bash -n" || bad "bash -n"

# --- 픽스처: 명부 2개 + 가짜 tmux (회원 3 · 비회원 2)
mkdir -p "$T/seats"
cat >"$T/seats/seats-x.json" <<'J'
{"_name":"x","ft-x-master#1":{"role":"master","agent":"claude","model":"m1"},
 "ft-x-nano#2":{"role":"stop-ready","agent":"claude","_replaced_by":"ft-x-nano#3"}}
J
cat >"$T/seats/seats.json" <<'J'
{"_version":"1","ft-v65-arch#5":{"role":"arch","agent":"claude","model":"m2"}}
J
cat >"$T/fake-tmux" <<'S'
#!/usr/bin/env bash
case "$1" in
  list-sessions) case "$*" in *session_created*) fmt='%s\t1700000000\t0\n';; *) fmt='%s\n';; esac
                 printf "$fmt" "ft-x-master#1" "ft-x-nano#3" "byz-x-nano-slug#0" "ft-x-da#1" "KakaoBot#1" "tmm";;
  list-panes)    printf '%s\t%s\n' "ft-x-master#1" 111 "ft-x-nano#3" 222 "ft-x-da#1" 444 "byz-x-nano-slug#0" 333;;
  *) exit 9;;
esac
S
chmod +x "$T/fake-tmux"
sum_in() { (cd "$T/seats" && shasum seats-x.json seats.json); }
before="$(sum_in)"

export FT_SEATS_DIR="$T/seats" FT_STATE_DIR="$T/state" FT_TMUX="$T/fake-tmux"

# 1 생성 — 회원 4(명부 베이스 일치 2 + 팀 접두 ft-x- 1 + P6 1) · 제외 2
out="$(bash "$GEN" 2>"$T/err")"; rc=$?
[ $rc -eq 0 ] && ok "생성 rc=0 ($out)" || bad "생성 rc=$rc $(cat "$T/err")"
echo "$out" | grep -q '^LIVE rows=4 members=4 tmux_total=6 excluded=2 ' && ok "행 4 == 접두 세션 4" || bad "요약: $out"
L="$T/state/seats.live.json"
[ "$(jq '.rows|length' "$L")" = 4 ] && ok "산출 행 수 4" || bad "산출 행 수"
[ "$(jq -r '.excluded|sort|join(",")' "$L")" = "KakaoBot#1,tmm" ] && ok "제외 = 동거 세션" || bad "excluded: $(jq -c .excluded "$L")"

# 2 행 내용 — 명부 값 · P6 파싱 · pid · 교체 표시
r() { jq -c --arg s "$1" '.rows[]|select(.session==$s)' "$L"; }
r "ft-x-master#1" | jq -e '.role=="master" and .model=="m1" and .grammar=="legacy" and .pane_pid==111 and .gen==1' >/dev/null && ok "명부 행 병합" || bad "master 행: $(r ft-x-master#1)"
r "ft-x-nano#3" | jq -e '.base=="ft-x-nano" and .config_file==null' >/dev/null && ok "명부에 없는 후계 세션도 베이스 일치로 회원" || bad "nano#3: $(r ft-x-nano#3)"
r "ft-x-da#1" | jq -e '.grammar=="legacy" and .config_file==null and .pane_pid==444' >/dev/null && ok "명부 행 없는 같은 팀 접두 세션도 회원" || bad "da#1: $(r ft-x-da#1)"
r "byz-x-nano-slug#0" | jq -e '.grammar=="p6" and .team=="x" and .role=="nano" and .agent==null' >/dev/null && ok "P6 이름 파싱" || bad "p6 행: $(r byz-x-nano-slug#0)"

# 3 입력 명부 수정 0 · 임시 파일 잔재 0
[ "$before" = "$(sum_in)" ] && ok "입력 명부 불변" || bad "입력 명부가 바뀜"
[ "$(ls -A "$T/state" | wc -l | tr -d ' ')" = 1 ] && ok "산출 파일 1개만(임시파일 잔재 0)" || bad "state: $(ls -A "$T/state")"

# 4 tmux 서버 없음 = 세션 0 행 0 · 명부 없음 = REJECT
printf '#!/usr/bin/env bash\necho "no server running on /tmp/x" >&2; exit 1\n' >"$T/fake-tmux"
out="$(bash "$GEN" 2>&1)"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q 'rows=0 members=0 tmux_total=0' && ok "서버 없음 → 행 0" || bad "서버 없음: rc=$rc $out"
printf '#!/usr/bin/env bash\necho "boom" >&2; exit 1\n' >"$T/fake-tmux"
bash "$GEN" >/dev/null 2>&1 && bad "tmux 오류가 통과함" || ok "tmux 오류 REJECT"
FT_SEATS_DIR="$T/none" bash "$GEN" >/dev/null 2>&1 && bad "명부 없음 통과" || ok "명부 디렉터리 없음 REJECT"

# --- test_bundle lint
tb() { printf '%s' "$2" >"$T/$1.json"; bash "$TBL" "$T/$1.json" 2>&1; }
exp_pass() { out="$(tb "$1" "$2")"; [ $? -eq 0 ] && echo "$out" | grep -q '^PASS' && ok "bundle 통과 $1" || bad "bundle 통과여야 함 $1: $out"; }
exp_rej()  { out="$(tb "$1" "$2")"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q "REJECT .*: .*$3" && ok "bundle REJECT $1 ($3)" || bad "bundle REJECT 여야 함 $1: rc=$rc $out"; }

exp_pass p1 '{"test_bundle":{"mode":"press-mic","card":"c1","seat":"s#1","open_event":"57001","state":"open"}}'
exp_pass p2 '{"test_bundle":{"mode":"alt","alt_axes":["API 응답","PG 행"]}}'
exp_pass p3 '{"test_bundle":{"mode":"none"}}'
exp_rej  r1 '{"_name":"x"}' "선언 칸 없음"
exp_rej  r2 '{"test_bundle":{"mode":""}}' "mode 빈칸"
exp_rej  r3 '{"test_bundle":{"mode":"press-api","card":"c1","seat":"","open_event":"1"}}' "빈칸: seat"
exp_rej  r4 '{"test_bundle":{"mode":"press"}}' "press-mic"
exp_rej  r5 '{"test_bundle":{"mode":"alt","alt_axes":[]}}' "alt_axes"
exp_rej  r6 '{"test_bundle":{"mode":"none","state":"zzz"}}' "state"
exp_rej  r7 '{"test_bundle":"x"}' "객체가 아니다"
bash "$TBL" "$T/nope.json" >/dev/null 2>&1; [ $? -eq 2 ] && ok "파일 없음 exit 2" || bad "파일 없음 exit"
printf '{bad' >"$T/bad.json"; bash "$TBL" "$T/bad.json" >/dev/null 2>&1; [ $? -eq 2 ] && ok "JSON 깨짐 exit 2" || bad "JSON 깨짐 exit"

echo "fail=$fail"; [ $fail -eq 0 ]
