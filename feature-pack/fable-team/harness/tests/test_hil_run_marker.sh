#!/usr/bin/env bash
# test_hil_run_marker.sh — R186(판정 1720): h<N> 실행 표식 · --supersedes 대체됨 거절 · 목록 칸 · --pending · 틱 hil_watch.
# 임시 HIL_DIR · 가짜 계획 · 가짜 mbox · 가짜 좌석표만 쓴다 — 실 /tmp/h* · 실 .fable-team/state · 실 mbox 0. 시험에 GIT_* 없음(env -i / env -u).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${R186_BIN:-$HERE/../../harness/kit/fable-team/bin}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }

D="$T/d"; mkdir -p "$D" "$T/home"
hilx() { env -i HOME="$T/home" PYTHONDONTWRITEBYTECODE=1 PATH="/usr/bin:/bin" HIL_DIR="$D" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" bash "$SRC/ft-hil.sh" "$@"; }
plan() {  # <이름> [touch] [끝 명령] — 실행되면 ran-<이름> 을 찍고(touch 면 $T/<이름>.touched 도 만들고) 끝 명령으로 끝난다
  printf '#!/usr/bin/env bash\necho "ran-%s args=$*"\n' "$1" > "$T/$1.sh.hil"
  [ -z "${2:-}" ] || printf 'touch "%s/%s.touched"\n' "$T" "$1" >> "$T/$1.sh.hil"
  printf '%s\n' "${3:-exit 0}" >> "$T/$1.sh.hil"
}

echo "== ⓐ 진입 파일 실행 → .ran(시작 시각 · rc) 기록 + 계획 그대로 실행(인자·종료코드 전달)"
plan A touch 'exit 3'; sha0="$(shasum "$T/A.sh.hil")"
out="$(hilx --add "$T/A.sh.hil")"; [ "$out" = "! bash $D/h1" ] && ok "--add → h1" || bad "--add out=$out"
has "$(hilx)" "미실행" "실행 전 목록 = 미실행 칸"
[ ! -e "$D/h1.ran" ] && ok "  └ 실행 전 h1.ran 없음" || bad "실행 전 표식이 있다"
o="$(bash "$D/h1" x y 2>&1)"; rc=$?
[ "$rc" = 3 ] && ok "종료코드 3 전달" || bad "rc=$rc"
has "$o" "ran-A args=x y" "인자 전달 · 계획 출력 그대로"
[ -f "$T/A.touched" ] && ok "계획 본문 실행됨" || bad "계획이 실행되지 않음"
[ "$(sed -n 1p "$D/h1.ran")" -gt 0 ] 2>/dev/null && ok "h1.ran 1행 = 시작 epoch" || bad "시작 시각 없음: $(cat "$D/h1.ran" 2>&1)"
[[ "$(sed -n 2p "$D/h1.ran")" =~ ^rc=3\ [0-9]+$ ]] && ok "h1.ran 2행 = rc=3 <epoch>" || bad "rc 행: $(sed -n 2p "$D/h1.ran")"
[ "$(shasum "$T/A.sh.hil")" = "$sha0" ] && ok "계획 파일 불변" || bad "계획 파일이 바뀜"
has "$(hilx)" "rc=3" "실행 뒤 목록 = 실행 HH:MM rc=3"

echo "== ⓑ --supersedes — 옛 h 실행은 REJECT 대체됨 · 계획 실행 0"
plan C touch; plan E touch
hilx --add "$T/C.sh.hil" >/dev/null                      # h2
out="$(hilx --add "$T/E.sh.hil" --supersedes h2)"; [ "$out" = "! bash $D/h3" ] && ok "E --supersedes h2 → h3" || bad "out=$out"
[ "$(cat "$D/h2.superseded")" = h3 ] && ok "h2.superseded = h3" || bad "표식: $(cat "$D/h2.superseded" 2>&1)"
e="$(bash "$D/h2" 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$e" "REJECT 대체됨 → h3" "h2 실행 = rc 1 + REJECT 대체됨 → h3" || bad "h2 실행 rc=$rc out=$e"
[ ! -e "$T/C.touched" ] && [ ! -e "$D/h2.ran" ] && ok "  └ 계획 실행 0 · .ran 0" || bad "대체된 장이 실행됨"
bash "$D/h3" >/dev/null 2>&1; [ -f "$T/E.touched" ] && ok "새 장 h3 은 정상 실행" || bad "h3 미실행"
out="$(hilx --add "$T/C.sh.hil")"; [ "$out" = "! bash $D/h4" ] && ok "대체된 계획 재등록 = 되살리지 않고 새 번호 h4" || bad "재등록 out=$out"
e="$(hilx --add "$T/E.sh.hil" --supersedes h99 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$e" "REJECT 대체할 h99 이 없다" "없는 h99 대체 = REJECT" || bad "h99 rc=$rc $e"
e="$(hilx --add "$T/E.sh.hil" --supersedes h2 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$e" "이미 대체됨 → h3" "이미 대체된 h2 재대체 = REJECT" || bad "재대체 rc=$rc $e"
e="$(hilx --add "$T/E.sh.hil" --supersedes h3 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$e" "자신을 대체할 수 없다" "자기 대체 = REJECT" || bad "자기 대체 rc=$rc $e"
ln -s "$T/A.sh.hil" "$D/h20"; plan F
e="$(hilx --add "$T/F.sh.hil" --supersedes h20 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$e" "옛 링크" "옛 링크 h20 대체 표시 = REJECT(거절 장치 없음)" || bad "링크 rc=$rc $e"
hilx --add "$T/F.sh.hil" --supersedes bad >/dev/null 2>&1; [ "$?" = 1 ] && ok "--supersedes 값 형식 오류 = REJECT" || bad "형식 오류 허용"
hilx --add "$T/F.sh.hil" --supersedes >/dev/null 2>&1; [ "$?" = 2 ] && ok "--supersedes 값 없음 = usage rc 2" || bad "값 없음 rc"

echo "== ⓒ 목록 칸"
L="$(hilx)"
has "$L" "h1  $T/A.sh.hil  실재  실행 " "h1 = 실행 HH:MM rc=3"
has "$L" "h2  $T/C.sh.hil  실재  대체됨 → h3" "h2 = 대체됨 → h3"
has "$L" "미실행 0분" "미실행 N분 칸"
has "$L" "h20  $T/A.sh.hil  실재  옛 링크(표식 없음)" "옛 링크 = 표식 없음 칸"

echo "== ⓓ --pending 요약 · 0개면 줄 없음 · 옛 링크·대체·실행된 것 제외"
P="$(hilx --pending)"; [[ "$P" =~ ^미실행\ h\ 1개\ ·\ 가장\ 오래된\ [0-9]+분$ ]] && ok "요약 = 미실행 h 1개(h4 만 — h1 실행·h2 대체·h3 실행·옛 링크 h20·손 파일 제외)" || bad "요약: $P"
touch -t "$(date -v-125M +%Y%m%d%H%M 2>/dev/null || date -d '125 minutes ago' +%Y%m%d%H%M)" "$D/h4"
P="$(hilx --pending)"; [[ "$P" =~ 가장\ 오래된\ 12[4-6]분$ ]] && ok "가장 오래된 ≈125분" || bad "오래된 분: $P"
each="$(hilx --pending --each)"; has "$each" "h4 12" "--each = h<N> <분> 줄"
bash "$D/h4" >/dev/null 2>&1
E2="$(HIL_DIR="$T/empty" hilx --pending)"; [ -z "$E2" ] && ok "0개면 출력 없음" || bad "0개인데 출력: $E2"
mkdir -p "$T/empty"; [ -z "$(env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$T/empty" bash "$SRC/ft-hil.sh" --pending)" ] && ok "빈 폴더 = 출력 없음" || bad "빈 폴더 출력"

echo "== ⓔ 기존 금지: 덮기·지우기·eval 0 · R135a 비밀 검사 그대로"
echo hand > "$D/h40"; hilx --add "$T/F.sh.hil" >/dev/null; [ "$(cat "$D/h40")" = hand ] && ok "손 h40 불변" || bad "h40 덮임"
grep -v '^#' "$SRC/ft-hil.sh" | grep -qE '(^|[^a-z_])eval( |$)|rm -|mv ' && bad "ft-hil.sh 에 eval·rm·mv" || ok "eval·rm·mv 0"
printf '#!/usr/bin/env bash\nS="$(gcloud secrets versions access latest --secret=x)"\ngcloud foo --h="X=$S"\n' > "$T/sec.sh.hil"
e="$(env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$T/sd" HIL_CLIP=0 bash "$SRC/ft-hil.sh" --add "$T/sec.sh.hil" 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$e" "REJECT 계획 파일 비밀 출력 경로" "비밀 출력 계획 = REJECT(R135a)" || bad "비밀 검사 rc=$rc $e"

echo "== ⓕ 틱 hil_watch — 개수 바뀔 때만 로그 · 30분 넘은 h 는 하루 h 당 1통 · FT_TICK_HIL=0 으로 끔 · 0개면 줄 없음"
Z="$T/z"; mkdir -p "$Z/state"; ZD="$Z/hil"; mkdir -p "$ZD"
printf '%s\n' '{"_master":"m1","_hil_route":"pl1","m1":{"role":"master","tick":null},"pl1":{"role":"pm","tick":null}}' > "$Z/seats.json"
printf '#!/bin/bash\necho "$*" >> "%s/mb.log"\n' "$Z" > "$Z/mbox-stub.sh"
zh() { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$ZD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" bash "$SRC/ft-hil.sh" "$@"; }
tick() { (cd "$Z" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY HIL_DIR="$ZD" "$@" \
  FT_TICK_SEATS="$Z/seats.json" FT_TICK_STATE_DIR="$Z/state" FT_TICK_STAMP_PREFIX="$Z/stamp-" FT_TICK_PIDFILE="$Z/tick.pid" FT_TICK_MBOX="$Z/mbox-stub.sh" \
  FT_TICK_HIL_BIN="$SRC/ft-hil.sh" FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_API_OUTAGE=0 \
  FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_LONG=0 FT_TICK_AUTONOMY=0 FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_STALL_INTERVAL=9999999999 FT_TICK_LEAK_REAP=0 \
  /bin/bash "$SRC/ft-tick.sh" --once 2>&1); }   # R347: 이 시험은 HIL 쪽지 개수만 본다 — 실 ps 에 의존하는 유출 경보는 끈다
tickx() { local a=(); while [ "${1:-}" = env ]; do a+=("$2"); shift 2; done; tick env ${a[@]+"${a[@]}"}; }
plan G; zh --add "$T/G.sh.hil" >/dev/null
o="$(tickx)"; has "$o" "hil_watch: 미실행 h 1개" "1개 → 로그 1줄"
[ ! -e "$Z/mb.log" ] && ok "  └ 30분 미만 = 쪽지 0" || bad "쪽지가 갔다: $(cat "$Z/mb.log")"
o="$(tickx)"; case "$o" in *hil_watch*) bad "개수 불변인데 로그가 또 나옴: $o";; *) ok "같은 개수 = 로그 0";; esac
touch -t "$(date -v-45M +%Y%m%d%H%M 2>/dev/null || date -d '45 minutes ago' +%Y%m%d%H%M)" "$ZD/h1"
tickx >/dev/null; [ "$(wc -l < "$Z/mb.log" 2>/dev/null | tr -d ' ')" = 1 ] && has "$(cat "$Z/mb.log")" "send pl1 ft-tick [HIL 미실행] h1 가 4" "45분 → planner(_hil_route) 앞 쪽지 1통" || bad "쪽지: $(cat "$Z/mb.log" 2>&1)"
has "$(cat "$Z/mb.log")" "! bash $ZD/h1" "  └ 칠 줄 = ! bash <HIL_DIR>/h1"
tickx >/dev/null; [ "$(wc -l < "$Z/mb.log" | tr -d ' ')" = 1 ] && ok "같은 날 같은 h = 쪽지 1통만" || bad "쪽지 중복"
rm -f "$Z/mb.log" "$Z/state/hil-notified"/*; tickx env FT_TICK_HIL=0 >/dev/null; [ ! -e "$Z/mb.log" ] && ok "FT_TICK_HIL=0 = 감시·쪽지 0" || bad "끔 스위치 무시"
bash "$ZD/h1" >/dev/null 2>&1
o="$(tickx)"; case "$o" in *hil_watch*) bad "0개인데 로그: $o";; *) ok "실행됨 → 0개 = 줄 없음";; esac
[ ! -e "$Z/state/hil.sig" ] && ok "  └ 서명 파일 정리" || bad "서명 잔류"
plan H; zh --add "$T/H.sh.hil" >/dev/null; d="$(tickx 2>&1; cd "$Z" && env HIL_DIR="$ZD" FT_TICK_SEATS="$Z/seats.json" FT_TICK_STATE_DIR="$Z/state-dry" FT_TICK_HIL_BIN="$SRC/ft-hil.sh" FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_API_OUTAGE=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_LONG=0 FT_TICK_AUTONOMY=0 FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 /bin/bash "$SRC/ft-tick.sh" --once --dry-run 2>&1)"
has "$d" "DRY kind=hil pending=미실행 h 1개" "--dry-run → DRY kind=hil 줄"

echo "== ⓖ DA⑥ H1 — rc 행 없는 .ran = 중단/실행 중(완료로 안 셈 · --pending 에 포함)"
HD="$T/hd"; mkdir -p "$HD"; plan K; env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" bash "$SRC/ft-hil.sh" --add "$T/K.sh.hil" >/dev/null 2>&1
hk() { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" bash "$SRC/ft-hil.sh" "$@"; }
echo $(( $(date +%s) - 600 )) > "$HD/h1.ran"
has "$(hk)" "중단/실행 중 10분" "목록 = 중단/실행 중 10분"
P="$(hk --pending)"; has "$P" "미실행 h 1개 (중단/실행 중 1개 포함) · 가장 오래된 10분" "--pending 에 포함"
has "$(hk --pending --each)" "h1 10" "--each 에도 포함"
echo "rc=0 $(date +%s)" >> "$HD/h1.ran"; [ -z "$(hk --pending)" ] && ok "rc 행이 생기면 완료 → pending 0" || bad "완료인데 pending"
has "$(hk)" "rc=0" "  └ 목록 = 실행 HH:MM rc=0"

echo "== ⓗ DA⑥ H2 — 개행·CR·제어문자 경로 REJECT · 공백·따옴표 경로는 왕복 + 계획 밖 명령 0"
JD="$T/jd"; mkdir -p "$JD" "$T/inj"; hj() { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$JD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" bash "$SRC/ft-hil.sh" "$@"; }
for nm in "$(printf 'a\n touch INJECTED\n#.sh.hil')" "$(printf 'b\rc.sh.hil')" "$(printf 'c\001d.sh.hil')"; do
  printf 'exit 0\n' > "$T/inj/$nm"; e="$(hj --add "$T/inj/$nm" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && has "$e" "REJECT 계획 경로에 개행·제어문자" "제어문자 경로 REJECT" || bad "제어문자 경로 rc=$rc"
done
[ -z "$(ls "$JD" | grep '^h[0-9]')" ] && [ ! -e "$T/INJECTED" ] && [ ! -e "$PWD/INJECTED" ] && ok "  └ 등록 0 · 계획 밖 명령 0" || bad "등록·주입 발생"
SP="$T/inj/sp ace 'q' \"dq\" \$x \`y\`.sh.hil"; printf 'echo SAFE\n' > "$SP"
out="$(hj --add "$SP")"; [ "$out" = "! bash $JD/h1" ] && ok "공백·따옴표·\$·백틱 경로 등록" || bad "특수 경로 등록 out=$out"
[ "$(bash "$JD/h1" 2>&1)" = SAFE ] && ok "  └ 실행 = 계획 본문만(SAFE)" || bad "특수 경로 실행"
[ "$(sed -n 's/^# ft-hil-entry plan=//p' "$JD/h1")" = "$SP" ] && ok "  └ 표식 줄 왕복 = 원래 경로" || bad "왕복 불일치"
[ "$(hj --add "$SP")" = "! bash $JD/h1" ] && ok "  └ 재등록 = 같은 h1 재사용(왕복)" || bad "재등록 불일치"
printf 'exit 0\n' > "$T/inj/z.sh.hil"; zn="$(hj --add "$T/inj/z.sh.hil")"; zn="${zn##*/h}"
hj --add "$T/inj/z.sh.hil" --supersedes "h0$zn" >/dev/null 2>&1; [ "$?" = 1 ] && ok "h0$zn 별칭 자기 대체 REJECT(0 채움 정규화)" || bad "0 채움 별칭이 통과"

echo "== ⓘ DA⑥ H3 — 팀 좌석표 틱은 건너뜀 · 같은 h/날 알림 원자적 1통 · 송신 실패면 재시도"
QD="$T/q"; mkdir -p "$QD/state" "$QD/hil"
hq() { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$QD/hil" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" bash "$SRC/ft-hil.sh" "$@"; }
plan Q; hq --add "$T/Q.sh.hil" >/dev/null; touch -t "$(date -v-45M +%Y%m%d%H%M 2>/dev/null || date -d '45 minutes ago' +%Y%m%d%H%M)" "$QD/hil/h1"
fn="$(awk '/^hil_watch\(\) \{/{p=1} p{print} p&&/^\}/{exit}' "$SRC/ft-tick.sh")"; [ -n "$fn" ] && ok "ft-tick.sh 에서 실제 hil_watch 함수 추출" || bad "hil_watch 추출 실패"
run_watch() {  # <SEATS 파일명> <notify 종류: ok|fail|slow> → watcher 1회 (실제 hil_watch 함수만 · 가짜 notify_team)
  /bin/bash -c "HIL_BIN='$SRC/ft-hil.sh'; STATE_DIR='$QD/state'; DRY=0; HIL_NOTIFY_MIN=30; SEATS='$QD/$1'; export HIL_DIR='$QD/hil'; log() { :; }
    notify_team() { case '$2' in fail) return 1;; slow) sleep 0.4;; esac; echo \"\$1\" >> '$QD/notes'; }
    $fn
    hil_watch" 2>/dev/null; }
: > "$QD/notes"; run_watch seats-ops.json ok; [ ! -s "$QD/notes" ] && ok "팀 좌석표(seats-ops.json) = 건너뜀(쪽지 0)" || bad "팀 틱이 알림: $(cat "$QD/notes")"
run_watch seats.json fail; [ ! -s "$QD/notes" ] && [ ! -e "$QD/state/hil-notified/h1.$(date +%Y%m%d)" ] && ok "송신 실패 = 선점 해제(다음 틱 재시도 가능)" || bad "실패 뒤 선점 잔류"
run_watch seats.json ok; [ "$(wc -l < "$QD/notes" | tr -d ' ')" = 1 ] && ok "재시도 성공 = 1통" || bad "재시도: $(cat "$QD/notes")"
: > "$QD/notes"; run_watch seats.json ok; [ ! -s "$QD/notes" ] && ok "같은 날 재감시 = 0통" || bad "같은 날 중복"
rmdir "$QD/state/hil-notified/h1.$(date +%Y%m%d)"; : > "$QD/notes"
run_watch seats.json slow & run_watch seats.json slow & wait
[ "$(wc -l < "$QD/notes" | tr -d ' ')" = 1 ] && ok "동시 2틱 = 정확히 1통(mkdir 원자 선점)" || bad "동시 알림 $(wc -l < "$QD/notes" | tr -d ' ')통"

echo "== 변이 1: 표식 기록 제거 → ⓐ 가 FAIL(검출)"
M="$T/mut"; mkdir -p "$M"; cp "$SRC/ft-hil.sh" "$SRC/ft_secret_judge.py" "$M/" 2>/dev/null
sed '/^date +%s > "\$M.ran"$/d' "$SRC/ft-hil.sh" > "$M/ft-hil.sh"; ! cmp -s "$SRC/ft-hil.sh" "$M/ft-hil.sh" && ok "변이 사본이 원본과 다르다" || bad "변이 사본 = 원본"
MD="$T/md"; mkdir -p "$MD"; plan M
env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$MD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" bash "$M/ft-hil.sh" --add "$T/M.sh.hil" >/dev/null
bash "$MD/h1" >/dev/null 2>&1
! sed -n 1p "$MD/h1.ran" 2>/dev/null | grep -qE '^[0-9]+$' && ok "변이: 시작 표식이 사라져 ⓐ 의 «h1.ran 1행 = 시작 epoch» 가 FAIL 한다" || bad "변이가 ⓐ 를 못 깬다"

echo "== 키트 두 벌 cmp · core.bare"
cmp -s "$HERE/../../harness/bin/ft-hil.sh" "$HERE/../../harness/kit/fable-team/bin/ft-hil.sh" && ok "ft-hil.sh cmp 0" || bad "ft-hil.sh 키트 다름"
cmp -s "$HERE/../../harness/bin/ft-tick.sh" "$HERE/../../harness/kit/fable-team/bin/ft-tick.sh" && ok "ft-tick.sh cmp 0" || bad "ft-tick.sh 키트 다름"
[ "$(git -C "$HERE" config --get core.bare)" = false ] && ok "core.bare = false" || bad "core.bare != false"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
