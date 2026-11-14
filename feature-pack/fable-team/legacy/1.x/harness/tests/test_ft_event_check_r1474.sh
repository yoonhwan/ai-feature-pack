#!/usr/bin/env bash
# test_ft_event_check_r1474.sh — ft-event-check.sh(r1474) 계약 시험 T1~T7 (카드 «계약↔시험 대응표» 그대로).
#   T1 hil · expect running + «loaded · last exit 0 · state 없음» = 실패(DA 반례1 h7874) · «state=running+pid» = OK · exited0 + exit 0 = OK
#   T2 hil · 원 rc=1(h7877 꼴)이어도 진입 파일 훅이 1회 돈다 · [완료] 쪽지에 «재측정:» 칸 · h exit 1 그대로
#   T3 hil · expect 0줄 = 실패(expect 없음) · launchctl exit 3 = 판정 불가 rc=3 · 대상 3 중 OK1·실패1·불가1 칸
#   T4 notify done · FT_HIL_RECHECK 없음 = 본문 바이트 기존과 같음 · 있음 = 끝에 « · 재측정: …» 1칸
#   T5 spawn · 세션 0 = 실패 · 배정 줄 불일치 = 실패 · 전부 맞음 = OK · SPAWNED·KILLED 줄(훅 그대로 실행) 끝 칸 + exit 0 불변
#   T6 events tsv · 탭 6칸 1줄 · 날이 바뀐 첫 쓰기에 14일 지난 파일 삭제 · 기록 실패 = stderr «판정 불가(기록)» 1줄 + 칸은 그대로
#   T7 항목 스텁 sleep 9 = 그 대상 «판정 불가(시간 초과)» · 전체 25초 안 · 재시도 0 · 새 쪽지 0(done 1통뿐)
#   T8·T8b 보정 R1: «error connecting (Permission denied)» = 판정 불가 rc3 · «no server running» = 세션 없음 OK
#   T9·T9b 보정 R2: cmp0 LIVE_BIN = <루트>/LIVE_BIN 첫 줄(bin = shim) · 빈 LIVE_BIN = 판정 불가
#   T10·T10b 보정 R3: tsv «rc=» = 5칸 하나(요약 rc:) · ft-now events 블록 원문 = 실패 rc=1 MW2 · 판정 불가 rc=3 MW1
# 전부 합성(임시 HIL_DIR·쪽지함·가짜 launchctl/tmux/mbox·합성 카드·임시 git) · 실 h·실 좌석·실 launchctl·실 쪽지 0 · sleep 은 T7 스텁만.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R1474_BIN:-$HERE/../bin}"
S="$BIN/ft-event-check.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
[ -f "$S" ] || { echo "FAIL ft-event-check.sh 없음: $S"; echo "FAILED 1"; exit 1; }
bash -n "$S" && ok "bash -n" || bad "bash -n"

NOW=1794138422; TODAY="$(date -r "$NOW" +%F)"
mkdir -p "$T/fb" "$T/ev" "$T/hil" "$T/home" "$T/ft/comm"
cat > "$T/fb/launchctl" <<'EOS'
#!/usr/bin/env bash
l="${2##*/}"; k="$(sed -n "s/^$l //p" "$(dirname "$0")/lc.conf" | head -1)"
case "$k" in
  running) printf '\tstate = running\n\tpid = 4242\n\tlast exit code = 0\n';;
  loadednr|exited0) printf '\tstate = not running\n\tlast exit code = 0\n';;
  absent|"") echo "Could not find service \"$l\" in domain for user gui: 501" >&2; exit 113;;
  error:*) exit "${k#error:}";;
  sleep) exec sleep 9;;
esac
EOS
cat > "$T/fb/tmux" <<'EOS'
#!/usr/bin/env bash
[ "$1" = has-session ] || exit 9
grep -qxF "${3#=}" "$(dirname "$0")/alive" 2>/dev/null && exit 0
echo "can't find session: ${3#=}" >&2; exit 1
EOS
chmod +x "$T/fb/launchctl" "$T/fb/tmux"; : > "$T/fb/alive"
ec() { env FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" bash "$S" "$@"; }
lc() { printf '%s\n' "$@" > "$T/fb/lc.conf"; }
entry() {  # entry <이름> <expect 줄…> → 합성 진입 파일 $T/<이름> (계획 = $T/<이름>.plan)
  local n="$1" e; shift
  { echo '#!/usr/bin/env bash'; for e in "$@"; do echo "# ft-hil-expect $e"; done; echo 'echo 작업'; } > "$T/$n.plan"
  printf '#!/usr/bin/env bash\n# ft-hil-entry plan=%s\n' "$T/$n.plan" > "$T/$n"; : > "$T/$n.out"
}

echo "== T1 running = state=running+pid 둘 다 · loaded+exit0 만으로 OK 0"
lc "com.t.a loadednr"; entry e1 "com.t.a running"
o="$(ec hil "$T/e1" 0 "$T/e1.out")"; rc=$?
has "$o" "재측정: 실패 · 대상 1 중 실패 1 · 불가 0" "loaded·exit0·state 없음 → 실패(h7874)"; [ "$rc" = 1 ] && ok "  └ rc1" || bad "rc=$rc"
lc "com.t.a running"; o="$(ec hil "$T/e1" 0 "$T/e1.out")"; rc=$?
has "$o" "재측정: OK · 대상 1 중 실패 0 · 불가 0" "state=running+pid → OK"; [ "$rc" = 0 ] && ok "  └ rc0" || bad "rc=$rc"
lc "com.t.o exited0"; entry e1b "com.t.o exited0"
has "$(ec hil "$T/e1b" 0 "$T/e1b.out")" "재측정: OK" "exited0 · last exit 0 → OK"

echo "== T2 원 rc=1 이어도 훅 1회 · 쪽지 칸 · h exit 1 그대로"
PM='byz-planner-master-claude#166'; C="$T/ft/comm"
printf '{"_master": "%s"}\n' "$PM" > "$T/ft/seats-planner.json"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"
{ echo '#!/usr/bin/env bash'; echo '# ft-hil-expect com.t.a running'; echo "echo '=== 결과 === bootstrap 실패'"; echo 'exit 1'; } > "$T/p2.sh.hil"
env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$T/hil" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$C" bash "$BIN/ft-hil.sh" --add "$T/p2.sh.hil" >/dev/null 2>&1
lc "com.t.a absent"; rm -f "$C/sent.log"
env -i HOME="$T/home" PATH="/usr/bin:/bin" FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" bash "$T/hil/h1" >/dev/null 2>"$T/e2"; rc=$?
[ "$rc" = 1 ] && ok "h1 exit 1 그대로" || bad "h1 rc=$rc $(cat "$T/e2")"
s="$(cat "$C/sent.log" 2>/dev/null)"
has "$s" "[완료 h1] rc=1 · === 결과 === bootstrap 실패 · 계획 $T/p2.sh.hil · 재측정: 실패 · 대상 1 중 실패 1 · 불가 0" "[완료] 쪽지 끝 «재측정:» 칸"
[ "$(grep -c . "$C/sent.log")" = 1 ] && ok "  └ 쪽지 1통(새 쪽지 0)" || bad "쪽지 수: $s"
[ "$(grep -c "	hil	h1	" "$T/ev/$TODAY.tsv" 2>/dev/null)" = 1 ] && ok "  └ events 1줄(훅 1회)" || bad "events: $(cat "$T/ev/$TODAY.tsv" 2>&1)"

echo "== T3 expect 0줄 · exit 3 = 판정 불가 rc=3 · 3대상 칸"
entry e3
o="$(ec hil "$T/e3" 0 "$T/e3.out")"; rc=$?
has "$o" "재측정: 실패(expect 없음)" "expect 0줄 → 실패(expect 없음)"; [ "$rc" = 1 ] && ok "  └ rc1" || bad "rc=$rc"
lc "com.t.e error:3"; entry e3b "com.t.e running"
o="$(ec hil "$T/e3b" 0 "$T/e3b.out")"; rc=$?
has "$o" "판정 불가 rc=3" "launchctl exit 3 → 판정 불가 rc=3"; [ "$rc" = 3 ] && ok "  └ rc3" || bad "rc=$rc"
lc "com.t.a running" "com.t.b absent" "com.t.e error:3"; entry e3c "com.t.a running" "com.t.b running" "com.t.e running"
has "$(ec hil "$T/e3c" 0 "$T/e3c.out")" "재측정: 실패 · 대상 3 중 실패 1 · 불가 1" "OK1·실패1·불가1 → 대상 3 중 실패 1 · 불가 1"

echo "== T4 notify done 선택 칸"
mkdir -p "$T/n4"; M="$T/n4/h9"; printf '# ft-hil-entry plan=/x/p.sh\n' > "$M"; echo '=== 결과 === 끝' > "$M.out"; printf '1\nrc=0 2\n' > "$M.ran"
rm -f "$C/sent.log"; env -u FT_HIL_RECHECK bash "$BIN/ft-hil-notify.sh" done "$M" 0 "$C" >/dev/null 2>&1
want="$PM	ft-hil-h9	[완료 h9] rc=0 · === 결과 === 끝 · 계획 /x/p.sh"
[ "$(cat "$C/sent.log")" = "$want" ] && ok "칸 없음 → 본문 바이트 기존과 같음" || bad "본문: $(cat "$C/sent.log")"
rm -f "$C/sent.log"; FT_HIL_RECHECK="재측정: OK · 대상 1 중 실패 0 · 불가 0" bash "$BIN/ft-hil-notify.sh" done "$M" 0 "$C" >/dev/null 2>&1
[ "$(cat "$C/sent.log")" = "$want · 재측정: OK · 대상 1 중 실패 0 · 불가 0" ] && ok "칸 있음 → 끝에 « · 재측정: …» 1칸" || bad "본문: $(cat "$C/sent.log")"

echo "== T5 spawn·close 재측정 + 훅 줄(부른 쪽 exit 불변)"
SEAT='byz-harness-nano-x#3'; W="$T/wt"
git init -q "$W" && git -C "$W" -c user.email=t@t -c user.name=t commit -q --allow-empty -m a && git -C "$W" update-ref refs/remotes/origin/main HEAD
printf '# 카드\n- 배정: 좌석 %s\n- 상태: 진행\n## 상태\n' "$SEAT" > "$T/card.md"
o="$(ec spawn "$SEAT" "$T/card.md" "$W")"; has "$o" "재측정: 실패 · 대상 3 중 실패 1" "세션 0 → 실패"
echo "$SEAT" > "$T/fb/alive"
printf '# 카드\n- 배정: 좌석 byz-other#1\n## 상태\n' > "$T/card2.md"
o="$(ec spawn "$SEAT" "$T/card2.md" "$W")"; has "$o" "재측정: 실패 · 대상 3 중 실패 1" "배정 줄 불일치 → 실패"
o="$(ec spawn "$SEAT" "$T/card.md" "$W")"; rc=$?; has "$o" "재측정: OK · 대상 3 중 실패 0 · 불가 0" "전부 맞음 → OK"
l="$(grep -n 'echo "SPAWNED \$NAME' "$BIN/ft-nano-spawn.sh")"
o="$(env FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" HERE="$BIN" _src=0 NAME="$SEAT" NEW_IDX=card.md IDX_WT="$T" WTDIR="$W" bash -c "${l#*:}")"; rc=$?
case "$o" in "SPAWNED $SEAT index=card.md wt=$W · 재측정: OK"*) ok "SPAWNED 줄 끝 «재측정: OK»";; *) bad "SPAWNED: $o";; esac
[ "$rc" = 0 ] && ok "  └ 부른 쪽 exit 0 불변" || bad "rc=$rc"
: > "$T/fb/alive"; n=0
while IFS= read -r l; do n=$((n+1))
  o="$(env FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" HERE="$BIN" SEAT="$SEAT" CARD="$T/card.md" bash -c "set -u; ${l#*:}")"; rc=$?
  case "$o" in "KILLED $SEAT (@zc_v65_active 해제 · 세션 kill · 브랜치 보존) · 재측정: OK"*) ok "KILLED 줄 $n 끝 «재측정: OK»";; *) bad "KILLED $n: $o";; esac
  [ "$rc" = 0 ] && ok "  └ exit 0" || bad "rc=$rc"
done < <(grep -n 'echo "KILLED \$SEAT' "$BIN/ft-nano-close.sh" | sed 's/^\([0-9]*:\)[[:space:]]*/\1/')
[ "$n" = 2 ] && ok "KILLED 줄 2곳" || bad "KILLED 줄 $n곳"

echo "== T6 events tsv 꼴 · 14일 회전 · 기록 실패"
rm -rf "$T/ev"; mkdir -p "$T/ev"
old="$(date -r $((NOW - 15*86400)) +%F)"; keep="$(date -r $((NOW - 13*86400)) +%F)"; : > "$T/ev/$old.tsv"; : > "$T/ev/$keep.tsv"
ec close "$SEAT" "$T/card.md" >/dev/null
[ "$(awk -F'\t' 'NF==6 && $2=="close" && $5 ~ /^rc=[0-9]+$/' "$T/ev/$TODAY.tsv" | grep -c .)" = 1 ] && ok "탭 6칸 1줄(rc=N)" || bad "tsv: $(cat -t "$T/ev/$TODAY.tsv" 2>&1)"
[ ! -e "$T/ev/$old.tsv" ] && ok "15일 전 파일 삭제" || bad "15일 전 파일 남음"
[ -e "$T/ev/$keep.tsv" ] && ok "13일 전 파일 보존" || bad "13일 전 파일이 지워졌다"
: > "$T/afile"
o="$(env FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" FT_EVENT_DIR="$T/afile/ev" bash "$S" close "$SEAT" "$T/card.md" 2>"$T/e6")"
[ "$(grep -c '판정 불가(기록)' "$T/e6")" = 1 ] && ok "기록 실패 → stderr 판정 불가(기록) 1줄" || bad "stderr: $(cat "$T/e6")"
has "$o" "재측정: OK" "  └ 칸은 그대로"

echo "== T7 항목 시간 초과 · 전체 25초 · 재시도 0 · 새 쪽지 0"
{ echo '#!/usr/bin/env bash'; echo '# ft-hil-expect com.t.s running'; echo '# ft-hil-expect com.t.a running'; echo 'echo ok'; } > "$T/p7.sh.hil"
env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$T/hil" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$C" bash "$BIN/ft-hil.sh" --add "$T/p7.sh.hil" >/dev/null 2>&1
lc "com.t.s sleep" "com.t.a running"; rm -f "$C/sent.log"; t0="$(date +%s)"
env -i HOME="$T/home" PATH="/usr/bin:/bin" FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" bash "$T/hil/h2" >/dev/null 2>&1; rc=$?; dt=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && ok "h2 exit 0 그대로" || bad "h2 rc=$rc"
[ "$dt" -lt 25 ] && ok "전체 ${dt}초 < 25" || bad "전체 ${dt}초"
s="$(cat "$C/sent.log" 2>/dev/null)"
has "$s" "재측정: 판정 불가 · 대상 2 중 실패 0 · 불가 1" "대상 2 중 불가 1"
has "$s" "com.t.s 판정 불가(시간 초과)" "  └ 그 대상 «판정 불가(시간 초과)»"
[ "$(grep -c . "$C/sent.log")" = 1 ] && ok "쪽지 = done 1통뿐" || bad "쪽지: $s"

echo "== T8 DA 반례 R1 — has-session rc1 + «error connecting … (Permission denied)» = 판정 불가 rc3"
mkdir -p "$T/fb8"
printf '#!/bin/bash\necho "error connecting to /private/tmp/tmux-501/default (Permission denied)" >&2\nexit 1\n' > "$T/fb8/tmux"
printf '#!/bin/bash\necho "no server running on /private/tmp/tmux-501/default" >&2\nexit 1\n' > "$T/fb8/tmux-ns"; chmod +x "$T/fb8/tmux" "$T/fb8/tmux-ns"
o="$(env FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" FT_EVENT_TMUX="$T/fb8/tmux" bash "$S" close "$SEAT" "$T/card.md")"; rc=$?
has "$o" "재측정: 판정 불가 · 대상 2 중 실패 0 · 불가 1" "권한 거부 = 세션 판정 불가(OK 둔갑 0)"; [ "$rc" = 3 ] && ok "  └ rc3" || bad "rc=$rc"
echo "== T8b «no server running» rc1 = 세션 없음 OK(지금처럼)"
o="$(env FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" FT_EVENT_TMUX="$T/fb8/tmux-ns" bash "$S" close "$SEAT" "$T/card.md")"; rc=$?
has "$o" "재측정: OK" "no server running → OK"; [ "$rc" = 0 ] && ok "  └ rc0" || bad "rc=$rc"

echo "== T9 DA 반례 R2 — <루트>/LIVE_BIN 첫 줄 = 실제 설치본(bin = shim) · env 미지정 → cmp0 OK"
R9="$T/r9"; mkdir -p "$R9/ft/comm" "$R9/ft/bin" "$R9/live"
cp "$BIN/ft-hil.sh" "$R9/live/ft-hil.sh"; printf '#!/bin/bash\nexec bash "%s/live/ft-hil.sh" "$@"\n' "$R9" > "$R9/ft/bin/ft-hil.sh"
printf '%s/live\n' "$R9" > "$R9/ft/LIVE_BIN"; entry e9 "ft-hil.sh cmp0"
o="$(env -u FT_EVENT_LIVE_BIN FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" FT_EVENT_COMM="$R9/ft/comm" bash "$S" hil "$T/e9" 0 "$T/e9.out")"; rc=$?
has "$o" "재측정: OK · 대상 1 중 실패 0 · 불가 0" "LIVE_BIN 파일이 가리키는 설치본과 cmp0 → OK"; [ "$rc" = 0 ] && ok "  └ rc0" || bad "rc=$rc"
echo "== T9b LIVE_BIN 파일 비었음 → 판정 불가(shim 폴더로 내려가지 않음)"
: > "$R9/ft/LIVE_BIN"
o="$(env -u FT_EVENT_LIVE_BIN FT_EVENT_LAUNCHCTL="$T/fb/launchctl" FT_EVENT_TMUX="$T/fb/tmux" FT_EVENT_NOW="$NOW" FT_EVENT_DIR="$T/ev" FT_EVENT_COMM="$R9/ft/comm" bash "$S" hil "$T/e9" 0 "$T/e9.out")"; rc=$?
has "$o" "재측정: 판정 불가 · 대상 1 중 실패 0 · 불가 1" "빈 LIVE_BIN → 판정 불가"; [ "$rc" = 3 ] && ok "  └ rc3" || bad "rc=$rc"

echo "== T10 DA 반례 R3 — 원 rc0 + 재측정 실패 → tsv rc=1 하나 · ft-now events 블록 = 실패 rc=1 MW2"
NOWB="$T/now-events.sh"   # ft-now.sh events 블록 원문 그대로(ev= 줄 ~ «없음» 줄) + mnote
{ echo 'MT=""; MW=0'; grep '^mnote()' "$BIN/ft-now.sh"; sed -n '/^ev="\$EVENTS\/\$TODAY.tsv"/,/^else mnote events "없음"/p' "$BIN/ft-now.sh"; echo 'printf "%s\nMW=%s\n" "$MT" "$MW"'; } > "$NOWB"
nowev() { EVENTS="$T/ev" TODAY="$TODAY" bash "$NOWB"; }
lc "com.t.a loadednr"; entry e10 "com.t.a running"; ec hil "$T/e10" 0 "$T/e10.out" >/dev/null
last="$(tail -n 1 "$T/ev/$TODAY.tsv")"
[ "$(printf '%s' "$last" | awk -F'\t' '{print $5}')" = rc=1 ] && ok "tsv 5칸 = rc=1" || bad "tsv: $last"
[ "$(printf '%s' "$last" | grep -o 'rc=' | grep -c .)" = 1 ] && ok "  └ 줄 안 «rc=» 1개(요약 = rc:)" || bad "rc= 수: $last"
has "$last" "원 rc:0" "  └ 원 rc 정보 보존(원 rc:0)"
o="$(nowev)"; has "$o" "events 신선도=오늘 원결과=실패 rc=1" "ft-now events = 실패 rc=1"; has "$o" "MW=2" "  └ MW2"
echo "== T10b 판정 불가 줄(rc=3) → ft-now «판정 불가 rc=3» MW1"
lc "com.t.e error:3"; ec hil "$T/e3b" 0 "$T/e3b.out" >/dev/null
o="$(nowev)"; has "$o" "events 신선도=오늘 원결과=판정 불가 rc=3" "ft-now events = 판정 불가 rc=3"; has "$o" "MW=1" "  └ MW1"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
