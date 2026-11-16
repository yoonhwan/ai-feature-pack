#!/usr/bin/env bash
# test_seat_close_autonomy_r2075.sh — r2075 수동 닫기 지원: 표준승인 밖 좌석을 planner _master·_desk 가 닫을 때 자율 ON = «대리» 원장 1줄 뒤 닫기 · OFF = 질문 글 1줄 · 그 밖 좌석 = 기존 held 그대로.
#   카드 반례 ①~⑦ · 변이 M1~M4(사본 · 원본 대조 1회씩). 대역만: 가짜 tmux(PATH · FT_TMUX_BIN · 세션 = 파일) · reap·close-check·우편함 스텁 · 임시 FT_ROOT·명부·원장·자율 상태. 실 tmux kill 0 · sleep 0
#   R2075_BIN=<bin 폴더> = 그 판으로 돌림(기준판 Red 확인) · R2075_BASE=<기준판 bin> 이 있으면 ⑤⑦ 을 그 판 출력·rc·명부와 바이트 대조
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # 레벨 밖(실 슬랙 0 · test_proxy_decide_r188 과 같음)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX_PANE FT_SEAT_NAME FT_SEATS_JSON FT_PROXY_LEDGER
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; SRC="$HERE/../bin"; BIN="${R2075_BIN:-$SRC}"; KIT="$HERE/../kit/fable-team/bin"; BASE="${R2075_BASE:-}"
RT="$(command -v tmux || true)"; real() { [ -z "$RT" ] || "$RT" list-sessions -F '#{session_name}' 2>/dev/null | sort; }; REAL0="$(real)"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; trap 'rm -rf "$T0"' EXIT INT TERM; export R2075_TMP="$TMP"
R="$TMP/root"; ST="$R/.fable-team/state"; PL="$TMP/planner"; LED="$PL/VERDICTS-planner-1.md"; SP="$R/.fable-team/seats-planner.json"; CF="$TMP/cf/seats.json"
mkdir -p "$ST" "$PL" "$TMP/wt" "$TMP/resume" "$TMP/cf/comm" "$TMP/fake" "$TMP/sess" "$TMP/st"; git -C "$TMP/wt" init -q
S="r2075s-$$#0"; PM="r2075-planner-master#3"; PD="r2075-planner-desk#2"; HM="r2075-harness-master#5"; WHY="r2075 시험 이유"
printf '%s\n' '- **100** (오빠) x 착수 승인' > "$LED"
planner_json() { printf '{"_master": "%s", "_desk": "%s"}\n' "$1" "$2" > "$SP"; }; planner_json "$PM" "$PD"
cat > "$TMP/fake/tmux" <<'EOS'
#!/bin/bash
D="$R2075_TMP"; echo "$*" >> "$D/tmux.log"
case "$1" in
has-session) [ -f "$D/sess/${3#=}" ];;
list-sessions) ls "$D/sess";;
display-message) case "$4" in "%77") cat "$D/by";; *:) cat "$D/att"; exit "$(cat "$D/attrc")";; *) echo;; esac;;
kill-session) rm -f "$D/sess/${3#=}";;
esac
EOS
printf '#!/bin/sh\necho "reap $1 found=0 left=0"\n' > "$TMP/reap.sh"
printf '#!/bin/sh\necho "$*" >> "%s/mbox.log"\n' "$TMP" > "$TMP/cf/comm/mbox.sh"
printf 'print("close-check stub")\n' > "$TMP/mbox.py"
printf '#!/bin/bash\necho x >> "%s/aut.log"; exec bash "$(cat "%s/autpath")" "$@"\n' "$TMP" "$TMP" > "$TMP/aut.sh"
printf '#!/bin/bash\necho "$*" >> "%s/proxy.log"; [ ! -f "%s/proxyrc" ] || { echo "QUEUE 스텁"; exit "$(cat "%s/proxyrc")"; }; exec bash "$(cat "%s/curbin")/ft-proxy-decide.sh" "$@"\n' "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/proxy.sh"
for m in on off tamper; do printf '#!/bin/sh\necho %s\n' "$m" > "$TMP/st/$m"; done; printf '#!/bin/sh\necho ON\n' > "$TMP/st/upper"; printf '#!/bin/sh\n:\n' > "$TMP/st/empty"; printf '#!/bin/sh\necho on; exit 1\n' > "$TMP/st/rc1"
mkfifo "$TMP/fifo"; printf '#!/bin/sh\nread x < "%s/fifo"; echo on\n' "$TMP" > "$TMP/st/fifo"
chmod +x "$TMP/fake/tmux" "$TMP/reap.sh" "$TMP/cf/comm/mbox.sh" "$TMP/aut.sh" "$TMP/proxy.sh" "$TMP"/st/*
export PATH="$TMP/fake:$PATH" FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$ST" FT_PLANNER_DIR="$PL" FT_AUTONOMY_HOOK_LOG="$TMP/hook.log" ZC_RESUME_DIR="$TMP/resume" FT_SEAT_RESUME_DIR="$TMP/resume" \
  FT_SEAT_REAP_BIN="$TMP/reap.sh" FT_MBOX_PY="$TMP/mbox.py" FT_CRITICAL_OFF=1 FT_TMUX_BIN="$TMP/fake/tmux" FT_PROXY_DECIDE_BIN="$TMP/proxy.sh" FT_AUTONOMY_BIN="$TMP/aut.sh"
fail=0; chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
HELD="kill=held(표준승인 밖 — 나노는 ft-nano-close · 그 밖은 [HIL])"; Q="[오빠 질문 필요] $S 닫기 — 이유 $WHY · 되살리는 길 zombie-clean.sh resume '$S'"
setmode() { [ ! -f "$SP" ] || mv "$SP" "$SP.h"; env -u TMUX_PANE bash "$SRC/ft-autonomy.sh" "$1" >>"$TMP/setmode.log" 2>&1; [ ! -f "$SP.h" ] || mv "$SP.h" "$SP"; [ "$(bash "$SRC/ft-autonomy.sh" mode)" = "$1" ] || echo "setmode $1 실패" >&2; echo "$SRC/ft-autonomy.sh" > "$TMP/autpath"; }   # 실 도구 · 임시 상태 · 켜는 동안 seats-planner.json 을 비킴(R342 arch 생존 검사는 이 시험 밖)
stub() { echo "$TMP/st/$1" > "$TMP/autpath"; }
by() { if [ "$1" = - ]; then unset TMUX_PANE; else export TMUX_PANE=%77; printf '%s\n' "$1" > "$TMP/by"; fi; }
fresh() {  # 대역 초기화: 좌석 세션 1 · 재개 기록 · 명부 · 로그 0
  rm -f "$TMP"/sess/* "$TMP/proxyrc" "$ST/autonomy.queued"; : > "$TMP/sess/$S"; : > "$TMP/tmux.log"; : > "$TMP/proxy.log"; : > "$TMP/aut.log"; : > "$TMP/mbox.log"
  echo 0 > "$TMP/att"; echo 0 > "$TMP/attrc"; printf '{"name": "%s"}\n' "$S" > "$TMP/resume/$S.json"
  printf '{"_master": "%s", "%s": {"role": "tester", "agent": "claude", "tick": null}}\n' "$HM" "$S" > "$CF"; }
close() {  # close [bin] → out rc kills led pc ac q
  local b="${1:-$BIN}" l0; l0="$(grep -c '\[대리 · 자율 ON' "$LED")"; echo "$b" > "$TMP/curbin"
  out="$(cd "$TMP/wt" && bash "$b/ft-seat-close.sh" "$S" --reason "$WHY" --seats "$CF" 2>/dev/null)"; rc=$?
  kills="$(grep -c '^kill-session' "$TMP/tmux.log")"; led=$(( $(grep -c '\[대리 · 자율 ON' "$LED") - l0 )); pc="$(grep -c . "$TMP/proxy.log")"; ac="$(grep -c . "$TMP/aut.log")"; q="$(grep -cxF "$Q" <<<"$out")"; }
roster() { sed -E 's/"at": "[^"]*"/"at": "-"/' "$CF"; }

c1() {  # ① 모드 판독 한 곳(C1)
  local b="${1:-$BIN}" k got t0 t1; for k in on:on off:off tamper:off empty:off upper:off rc1:off; do
    got="$(bash -c '. "$1/ft-team-lib.sh" 2>/dev/null; ft_autonomy_mode "$2"' _ "$b" "$TMP/st/${k%%:*}" 2>&1)"; chk "① 자율 도구 ${k%%:*} → ${k#*:}" "$got" "${k#*:}"; done
  [ -n "${2:-}" ] && return; t0="$(date +%s)"; got="$(bash -c '. "$1/ft-team-lib.sh" 2>/dev/null; ft_autonomy_mode "$2"' _ "$b" "$TMP/st/fifo")"; t1="$(date +%s)"
  chk "① fifo 멈춤 → 7초+2초 안에 off" "$got $(( t1 - t0 <= 9 ))" "off 1"
  got="$(bash -c '. "$1/ft-team-lib.sh" 2>/dev/null; ft_autonomy_mode "$2"' _ "$b" "$TMP/st/없음")"; chk "① 도구 파일 없음 → off" "$got" off; }
c2() {  # ② 주인 판정(C2) — off 질문 글 = 주인 · 그 밖 = held 1줄
  local b="${1:-$BIN}"; stub off
  fresh; by "$PM"; close "$b"; chk "② BY=planner _master → 주인(질문 글)" "$rc $q" "3 1"
  fresh; by "$PD"; close "$b"; chk "② BY=planner _desk → 주인" "$rc $q" "3 1"
  fresh; by "$HM"; close "$b"; chk "② BY=harness master → 아님" "$rc $q $ac" "3 0 0"
  fresh; by -; close "$b"; chk "② TMUX_PANE 없음 → 아님" "$rc $q $ac" "3 0 0"
  fresh; by "$HM"; FT_SEAT_NAME="$PM" close "$b"; chk "② env FT_SEAT_NAME=planner master · 실제 세션 다름 → 아님" "$rc $q $ac" "3 0 0"
  rm -f "$SP"; fresh; by "$PM"; close "$b"; chk "② seats-planner.json 없음 → 아님" "$rc $q $ac" "3 0 0"
  echo '{not json' > "$SP"; fresh; close "$b"; chk "② seats-planner.json JSON 아님 → 아님" "$rc $q $ac" "3 0 0"
  planner_json "" "$PD"; fresh; by ""; close "$b"; chk "② _master 빈 글 · BY 빈 글 → 아님" "$rc $q $ac" "3 0 0"
  planner_json "$PM" "$PD"; }
c3() {  # ③ on 닫기(C3)
  local b="${1:-$BIN}"; setmode on; by "$PM"
  [ -n "${2:-}" ] || { fresh; close "$b"; chk "③ 주인·on·재개 기록 → 대리 1줄 · CLOSED-SESSION rc0 · 세션 없음 · 질문 0" "$rc $led $(grep -c "\[대리 · 자율 ON.*$S" "$LED") $(grep -c "^CLOSED-SESSION $S .*kill=ok" <<<"$out") $(ls "$TMP/sess" | grep -c .) $q" "0 1 1 1 0 0"; }
  fresh; rm -f "$TMP/resume/$S.json"; close "$b"; chk "③ 재개 기록 없음 → kill 0 · rc3 · 원장 0" "$rc $kills $led" "3 0 0"
  [ -n "${2:-}" ] && return
  fresh; echo 2 > "$TMP/proxyrc"; close "$b"; chk "③ 대리 도구 rc2 → kill 0 · rc3 · 대리 출력 첫 줄" "$rc $kills $(grep -c '^QUEUE 스텁$' <<<"$out")" "3 0 1"
  fresh; echo 1 > "$TMP/attrc"; echo "" > "$TMP/att"; close "$b"; chk "③ attached 판정 불가 → HELD · 대리 0 · 원장 0" "$rc $kills $pc $led $(grep -c "^HELD $S 판정 불가 attached" <<<"$out")" "3 0 0 0 1"
  planner_json "$PM" "$S"; fresh; by "$S"; close "$b"; chk "③ 부른 좌석 == 닫을 좌석 → REJECT rc1 · kill 0 · 대리 0" "$rc $kills $pc $led $(grep -c "^REJECT $S 은 지금" <<<"$out")" "1 0 0 0 1"; planner_json "$PM" "$PD"; }
c4() {  # ④ off 질문(C3)
  local b="${1:-$BIN}" k; by "$PM"; setmode off
  fresh; close "$b"; chk "④ 주인·off → kill 0 · rc3 · 질문 글 1줄 · 원장 0 · 쪽지 0 · 대리 0" "$rc $kills $q $led $(grep -c . "$TMP/mbox.log") $pc $(grep -cxF "CLOSED-SESSION $S file=$CF role_was=tester $HELD" <<<"$out")" "3 0 1 0 0 0 1"
  for k in tamper rc1; do stub "$k"; fresh; close "$b"; chk "④ 판독 $k → 같은 결과" "$rc $kills $q $led $pc" "3 0 1 0 0"; done; }
c5() {  # ⑤ 주인 아님(C3)
  local b="${1:-$BIN}" o r; setmode on; by "$HM"; fresh; close "$b"
  chk "⑤ harness master · on → 기존 held 줄 그대로 · rc3 · 대리 0 · 자율 도구 0" "$out|$rc $kills $pc $ac" "CLOSED-SESSION $S file=$CF role_was=tester $HELD|3 0 0 0"
  [ -z "$BASE" ] || { o="$out $rc $(roster)"; fresh; close "$BASE"; chk "⑤ 기준판과 출력·rc·명부 바이트 같음" "$o" "$out $rc $(roster)"; }; }
c6() {  # ⑥ 대리 종류 seat-close(C4)
  local b="${1:-$BIN}" n=0 w l0; echo "$b" > "$TMP/curbin"
  P() { n=$((n+1)); rm -f "$ST/autonomy.queued"; l0="$(grep -c '\[대리 · 자율 ON' "$LED")"; out="$(bash "$b/ft-proxy-decide.sh" --q "$S 닫기 $n" --choice 닫기 --why "${W:-근거}" --undo "zombie-clean.sh resume" "$@" 2>&1)"; rc=$?; led=$(( $(grep -c '\[대리 · 자율 ON' "$LED") - l0 )); }
  setmode on; fresh
  [ -n "${2:-}" ] || { P --kind seat-close --seat "$S"; chk "⑥ seat-close · on · 세션·재개 기록 → PROXY rc0 · 원장 1줄" "$rc $led $(grep -c '^PROXY' <<<"$out")" "0 1 1"; }
  for w in kill-server pkill "브랜치 삭제" "force push" "rm -rf x"; do W="$S $w" P --kind seat-close --seat "$S"; chk "⑥ 글에 «${w}» → QUEUE rc2" "$rc $led" "2 0"; done
  [ -n "${2:-}" ] && return
  W="세션 kill 1회" P --kind seat-close --seat "$S"; chk "⑥ 글에 낱말 «kill» 만 → PROXY" "$rc $led" "0 1"
  P --kind seat-close; chk "⑥ --seat 없음 → rc4" "$rc $led" "4 0"
  rm -f "$TMP/sess/$S"; P --kind seat-close --seat "$S"; chk "⑥ 세션 없음 → QUEUE rc2" "$rc $led" "2 0"; fresh
  rm -f "$TMP/resume/$S.json"; P --kind seat-close --seat "$S"; chk "⑥ 재개 기록 없음 → QUEUE rc2" "$rc $led" "2 0"; fresh
  printf '{"_arch": "%s"}\n' "$S" > "$R/.fable-team/seats-x.json"; P --kind seat-close --seat "$S"; chk "⑥ 좌석 = 어느 명부의 _arch 값 → QUEUE rc2" "$rc $led" "2 0"; rm -f "$R/.fable-team/seats-x.json"
  setmode off; P --kind seat-close --seat "$S"; chk "⑥ off → rc3 · 원장 0" "$rc $led" "3 0"
  for w in card-start press-order nano-reopen docs-push wt-clean; do chk "⑥ 종류 $w 글 «kill» → 기준판처럼 QUEUE · 평문 → PROXY" "$(python3 "$b/autonomy_classify.py" --kind "$w" --text "세션 kill"; python3 "$b/autonomy_classify.py" --kind "$w" --text "평문")" "QUEUE 제외 어휘 [kill]
PROXY"; done; }
c7() {  # ⑦ 불변(C5·C6) — 표준 닫기 · 죽은 좌석 · 역할 좌석 거절을 on 과 off 에서
  local b="${1:-$BIN}" m o0 c
  for c in lineage dead role; do o0=""; for m in on off; do setmode "$m"; by "$PM"; fresh
    case "$c" in lineage) : > "$TMP/sess/${S%#*}#1";; dead) rm -f "$TMP/sess/$S";; role) printf '{"_master": "%s", "%s": {"role": "tester", "agent": "claude", "tick": null}}\n' "$S" "$S" > "$CF";; esac
    close "$b"; chk "⑦ $c · $m → 대리 0 · 질문 0" "$pc $led $q" "0 0 0"
    [ "$c" != lineage ] || chk "⑦ lineage · $m 결과 줄 = 표준 닫기" "$rc $(grep -c "^CLOSED-SESSION $S .*kill=ok reap left=0 rc=0$" <<<"$out")" "0 1"
    [ -z "$BASE" ] || { local x="$out $rc $(roster)"; fresh; case "$c" in lineage) : > "$TMP/sess/${S%#*}#1";; dead) rm -f "$TMP/sess/$S";; role) printf '{"_master": "%s", "%s": {"role": "tester", "agent": "claude", "tick": null}}\n' "$S" "$S" > "$CF";; esac
      close "$BASE"; chk "⑦ $c · $m → 기준판과 출력·rc·명부 바이트 같음" "$x" "$out $rc $(roster)"; }
    [ -z "$o0" ] && o0="$out $rc" || chk "⑦ $c → on·off 출력·rc 같음" "$out $rc" "$o0"; done; done
  for c in ft-team-lib.sh ft-seat-close.sh ft-proxy-decide.sh autonomy_classify.py; do cmp -s "$SRC/$c" "$KIT/$c"; chk "⑦ kit 사본 cmp $c" $? 0; done
  chk "⑦ hard-rules-ft.md 수동 닫기 포인터 1줄" "$(grep -c '^- \*\*수동 닫기 지원\*\* = planner master·desk 몫 · 자율 ON = 질문 0 닫기 · 자율 OFF = 오빠 Slack 네/아니오 뒤 닫기 → `~/.claude/guides/hil.md` «수동 닫기 지원 표준승인»' "$HERE/../../skill/references/hard-rules-ft.md")" 1; }

t=$(date +%s); echo "== 반례"; c1; c2; c3; c4; c5; c6; c7; echo "단계 반례 $(( $(date +%s) - t ))초"
echo "== 변이(사본 · 잡히면 PASS · 원본 대조)"; t=$(date +%s)
mut() {  # mut <이름> <파일> <옛> <새> <사례>
  local d="$TMP/mb/$1" f0="$fail" n; mkdir -p "$d"; cp -R "$BIN"/. "$d"/
  python3 -c 'import sys;p,o,n=sys.argv[1:4];s=open(p).read();assert s.count(o)==1,o;open(p,"w").write(s.replace(o,n))' "$d/$2" "$3" "$4" || { chk "$1 치환" x ok; return; }
  "$5" "$d" short >/dev/null; n=$((fail - f0)); fail="$f0"; chk "$1 → $5 FAIL" "$(( n > 0 ))" 1
  "$5" "$BIN" short >/dev/null; n=$((fail - f0)); fail="$f0"; chk "$1 원본 대조 → $5 PASS" "$n" 0; }
mut M1 ft-team-lib.sh 'print("on" if p.returncode == 0 and' 'print("on" if p.returncode != 0 or' c1
mut M2 ft-seat-close.sh '  planner_owner || finish 3 "$h"' '  true || finish 3 "$h"' c5
mut M3 ft-proxy-decide.sh '[ -f "$rec" ] || queue_exit "②' 'true || queue_exit "②' c3
mut M4 autonomy_classify.py 'r"\bkill-server\b|\bpkill\b|죽이"' 'r"\bpkill\b|죽이"' c6
echo "단계 변이 $(( $(date +%s) - t ))초"
REAL1="$(real)"; echo "실 tmux 세션 수 앞 $(grep -c . <<<"$REAL0") · 뒤 $(grep -c . <<<"$REAL1")(다른 좌석이 여닫는 몫 포함)"
chk "실 tmux 에 시험 대역 이름 0(가짜 tmux 만 씀)" "$(grep -c "^r2075" <<<"$REAL1")" 0
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
