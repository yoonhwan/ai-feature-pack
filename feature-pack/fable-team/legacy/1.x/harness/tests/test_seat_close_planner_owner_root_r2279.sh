#!/usr/bin/env bash
# test_seat_close_planner_owner_root_r2279.sh — r2279: manual_close 의 주인 판정(planner_owner)이 seats-planner.json 을
#   라이브 루트(LIVE_ROOT · ft_data_root)가 아니라 리포 공용 루트(env FT_ROOT · 없으면 ft_repo_root = cwd git 공용 루트)에서 읽는다.
#   카드 반례 ①~⑤ · 변이 M1(사본 · 원본 대조 1회). 대역 = r2075 꼴(가짜 tmux · 대리·자율·reap 스텁 · 임시 리포·라이브 폴더). 실 tmux kill 0 · sleep 0
#   R2279_BIN=<bin 폴더> = 그 판으로 돌림(기준판 Red 확인) · R2279_BASE=<기준판 bin> 이 있으면 ④ 를 그 판 출력·rc 와 바이트 대조
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX_PANE FT_SEAT_NAME FT_SEATS_JSON FT_PROXY_LEDGER FT_ROOT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="${R2279_BIN:-$HERE/../bin}"; BASE="${R2279_BASE:-}"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; trap 'rm -rf "$T0"' EXIT INT TERM; export R2279_TMP="$TMP"
R="$TMP/repo"; LV="$TMP/live"; R0="$TMP/root0"; NG="$TMP/nogit"; CF="$TMP/cf/seats.json"
mkdir -p "$R/.fable-team" "$R/sub" "$LV/.fable-team/state" "$R0/.fable-team/state" "$NG" "$TMP/cf/comm" "$TMP/fake" "$TMP/sess" "$TMP/resume" "$TMP/planner"
git -C "$R" init -q; printf '%s\n' "$LV" > "$R/.fable-team/LIVE_ROOT"
S="r2279s-$$#0"; PM="r2279-planner-master#3"; PD="r2279-planner-desk#2"; HM="r2279-harness-master#5"; WHY="r2279 시험 이유"
cat > "$TMP/fake/tmux" <<'EOS'
#!/bin/bash
D="$R2279_TMP"; echo "$*" >> "$D/tmux.log"
case "$1" in
has-session) [ -f "$D/sess/${3#=}" ];;
list-sessions) ls "$D/sess";;
display-message) case "$4" in "%77") cat "$D/by";; *:) echo 0;; *) echo;; esac;;
kill-session) rm -f "$D/sess/${3#=}";;
esac
EOS
printf '#!/bin/sh\necho "reap $1 found=0 left=0"\n' > "$TMP/reap.sh"
printf '#!/bin/sh\necho "$*" >> "%s/mbox.log"\n' "$TMP" > "$TMP/cf/comm/mbox.sh"
printf 'print("close-check stub")\n' > "$TMP/mbox.py"
printf '#!/bin/sh\necho x >> "%s/aut.log"; echo off\n' "$TMP" > "$TMP/aut.sh"
printf '#!/bin/sh\necho "$*" >> "%s/proxy.log"; echo "QUEUE 스텁"; exit 2\n' "$TMP" > "$TMP/proxy.sh"
chmod +x "$TMP/fake/tmux" "$TMP/reap.sh" "$TMP/cf/comm/mbox.sh" "$TMP/aut.sh" "$TMP/proxy.sh"
export PATH="$TMP/fake:$PATH" FT_AUTONOMY_STATE_DIR="$LV/.fable-team/state" FT_PLANNER_DIR="$TMP/planner" ZC_RESUME_DIR="$TMP/resume" FT_SEAT_RESUME_DIR="$TMP/resume" \
  FT_SEAT_REAP_BIN="$TMP/reap.sh" FT_MBOX_PY="$TMP/mbox.py" FT_CRITICAL_OFF=1 FT_TMUX_BIN="$TMP/fake/tmux" FT_PROXY_DECIDE_BIN="$TMP/proxy.sh" FT_AUTONOMY_BIN="$TMP/aut.sh"
fail=0; chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
HELD="CLOSED-SESSION $S file=$CF role_was=tester kill=held(표준승인 밖 — 나노는 ft-nano-close · 그 밖은 [HIL])"; Q="[오빠 질문 필요] $S 닫기 — 이유 $WHY · 되살리는 길 zombie-clean.sh resume '$S'"
roster() { sed -E 's/"at": "[^"]*"/"at": "-"/' "$CF"; }
pj() { printf '{"_master": "%s", "_desk": "%s"}\n' "$2" "$3" > "$1/.fable-team/seats-planner.json"; }
by() { if [ "$1" = - ]; then unset TMUX_PANE; else export TMUX_PANE=%77; printf '%s\n' "$1" > "$TMP/by"; fi; }
fresh() { rm -f "$TMP"/sess/* "$R/.fable-team/seats-planner.json" "$LV/.fable-team/seats-planner.json" "$R0/.fable-team/seats-planner.json"; : > "$TMP/sess/$S"
  : > "$TMP/tmux.log"; : > "$TMP/proxy.log"; : > "$TMP/aut.log"; printf '{"name": "%s"}\n' "$S" > "$TMP/resume/$S.json"
  printf '{"_master": "%s", "%s": {"role": "tester", "agent": "claude", "tick": null}}\n' "$HM" "$S" > "$CF"; }
close() {  # close <bin> <cwd> <FT_ROOT 또는 -> → out rc kills q pc(대리 호출 수)
  local b="$1" w="$2" f="$3"
  if [ "$f" = - ]; then out="$(cd "$w" && env -u FT_ROOT bash "$b/ft-seat-close.sh" "$S" --reason "$WHY" --seats "$CF" 2>/dev/null)"; rc=$?
  else out="$(cd "$w" && FT_ROOT="$f" bash "$b/ft-seat-close.sh" "$S" --reason "$WHY" --seats "$CF" 2>/dev/null)"; rc=$?; fi
  kills="$(grep -c '^kill-session' "$TMP/tmux.log")"; q="$(grep -cxF "$Q" <<<"$out")"; pc="$(grep -c . "$TMP/proxy.log")"; }
c1() { local b="${1:-$BIN}"; fresh; pj "$R" "$HM" "$PD"; by "$PD"; close "$b" "$NG" "$R"
  chk "① FT_ROOT=리포 루트(LIVE_ROOT 있음 · 라이브 명부 0) · _desk = BY → 주인(off 질문 1줄 · rc3)" "$rc $q $kills $pc" "3 1 0 0"; }
c2() { local b="${1:-$BIN}"; fresh; pj "$R" "$PM" "$HM"; by "$PM"; close "$b" "$R/sub" -
  chk "② FT_ROOT 없음 · cwd = 리포(LIVE_ROOT 있음) · _master = BY → 주인" "$rc $q $kills $pc" "3 1 0 0"; }
c3() { local b="${1:-$BIN}" w f; for w in "$NG:$R" "$R/sub:-"; do f="${w#*:}"; w="${w%%:*}"
    fresh; pj "$LV" "$HM" "$PD"; by "$PD"; close "$b" "$w" "$f"
    chk "③ 명부가 라이브 폴더에만 · FT_ROOT=${f/#"$R"/리포 루트} → 주인 아님 held 줄 · rc3 · 질문 0" "$rc $q $kills $pc $(grep -cxF "$HELD" <<<"$out")" "3 0 0 0 1"; done; }
c4() {  # ④ r2075 반례 ② 묶음 — FT_ROOT=LIVE_ROOT 없는 루트(r2075 꼴)
  local b="${1:-$BIN}" k x; for k in mPM dPD aHM n- eHM jPM sPM zPD; do
    fresh; pj "$R0" "$PM" "$PD"; case "$k" in s*) rm -f "$R0/.fable-team/seats-planner.json";; j*) echo '{not json' > "$R0/.fable-team/seats-planner.json";; z*) pj "$R0" "" "$PD";; esac
    case "${k#?}" in PM) by "$PM";; PD) by "$PD";; HM) by "$HM";; -) by -;; esac; [ "$k" != zPD ] || by ""
    if [ "$k" = eHM ]; then FT_SEAT_NAME="$PM" close "$b" "$NG" "$R0"; else close "$b" "$NG" "$R0"; fi
    case "$k" in m*|d*) chk "④ $k → 주인(질문 1줄)" "$rc $q $kills $pc" "3 1 0 0";; *) chk "④ $k → 주인 아님 held" "$rc $q $kills $pc $(grep -cxF "$HELD" <<<"$out")" "3 0 0 0 1";; esac
    [ -z "$BASE" ] || { x="$out $rc $(roster)"; fresh; pj "$R0" "$PM" "$PD"; case "$k" in s*) rm -f "$R0/.fable-team/seats-planner.json";; j*) echo '{not json' > "$R0/.fable-team/seats-planner.json";; z*) pj "$R0" "" "$PD";; esac
      if [ "$k" = eHM ]; then FT_SEAT_NAME="$PM" close "$BASE" "$NG" "$R0"; else close "$BASE" "$NG" "$R0"; fi; chk "④ $k → 기준판과 출력·rc·명부 바이트 같음" "$x" "$out $rc $(roster)"; }; done; }
c5() { local b="${1:-$BIN}" y; fresh; pj "$R" "$PM" "$HM"; by "$PD"; close "$b" "$NG" "$R"; y="$(roster)"   # 같은 BY 의 주인 아님 held 기준
  fresh; pj "$R" "$PM" "$PD"; by "$PD"; close "$b" "$NG" -
  chk "⑤ FT_ROOT 없음 · cwd = git 리포 아님 → 주인 아님 held · rc3 · kill 0 · 대리 0" "$rc $q $kills $pc $(grep -cxF "$HELD" <<<"$out")" "3 0 0 0 1"
  chk "⑤ 쓰기 0 — cwd·라이브 폴더 새 파일 0 · 명부 = 주인 아님 held 와 같은 바이트" "$(find "$NG" "$LV" -newer "$TMP/by" -type f | grep -c .) $(find "$NG" -mindepth 1 | grep -c .) $( [ "$y" = "$(roster)" ] && echo same)" "0 0 same"; }

t=$(date +%s); echo "== 반례"; c1; c2; c3; c4; c5; echo "단계 반례 $(( $(date +%s) - t ))초"
echo "== 변이(사본 · 잡히면 PASS · 원본 대조)"; t=$(date +%s)
mut() {  # mut <이름> <옛> <새> <사례>
  local d="$TMP/mb/$1" f0="$fail" n; mkdir -p "$d"; cp -R "$BIN"/. "$d"/
  python3 -c 'import sys;p,o,n=sys.argv[1:4];s=open(p).read();assert s.count(o)==1,o;open(p,"w").write(s.replace(o,n))' "$d/ft-seat-close.sh" "$2" "$3" || { chk "$1 치환" x ok; return; }
  "$4" "$d" >/dev/null; n=$((fail - f0)); fail="$f0"; chk "$1 → $4 FAIL" "$(( n > 0 ))" 1
  "$4" "$BIN" >/dev/null; n=$((fail - f0)); fail="$f0"; chk "$1 원본 대조 → $4 PASS" "$n" 0; }
M1O='d="${FT_ROOT:-$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE" 2>/dev/null)}"'; M1N='d="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)"'
mut M1 "$M1O" "$M1N" c1; mut M1 "$M1O" "$M1N" c2
echo "단계 변이 $(( $(date +%s) - t ))초"
chk "실 tmux 에 시험 대역 이름 0(가짜 tmux 만 씀)" "$( { command -v tmux >/dev/null && env PATH="${PATH#"$TMP/fake:"}" tmux list-sessions -F '#{session_name}' 2>/dev/null; } | grep -c '^r2279')" 0
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
