#!/usr/bin/env bash
# test_postboot_measure_r868.sh — r868 ft-postboot-measure.sh: 재부팅 기준선 대비 2시간 주기 재측정(읽기 전용 · 명령 상한 · 상태 열 · 하루 요약).
# 명령 대역(PATH 앞 가짜 uptime·sysctl·memory_pressure·df·ps·tmux·git·lsof·colima)·FT_NOW 고정·임시 루트만 — 실 시스템 0.
# ⓐ 한 회 측정 = 기준선 9항목 + 원인 4 보조 → 상태 파일 1행 · ⓑ 7초 상한(lsof 크기 비례 · 70초 천장) 넘으면 «시간 초과»(0·빈 칸 0)
# ⓒ 읽기 전용(호출 목록 = 허용 명령만) · ⓓ 날이 바뀐 첫 회 = 전날 요약 1장(커밋 0) · ⓔ 기준선 대비 차이 열 · ⓕ 변이 2종 → ⓑ·ⓒ FAIL
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
TPL="$REPO/harness/kit/launchd/com.byz.ft-postboot-measure.plist.template"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; CALLS="$T/calls.log"; mkdir -p "$S" "$R/.fable-team/state"
export CALLS   # heredoc 대역(quoted)도 같은 로그에 적는다
# 대역: 모든 호출을 CALLS 에 «이름 인자…» 1줄로 남긴다 · FAKE_SLOW_<이름>=1 이면 exec sleep 3(손자 0 — 파이프 안 쥠)
mk() { printf '#!/bin/sh\necho "%s${*:+ $*}" >> "%s"\n[ -n "${FAKE_SLOW_%s:-}" ] && exec /bin/sleep ${FAKE_SLEEP:-3}\n%s\n' "$1" "$CALLS" "$1" "$2" > "$S/$1"; chmod 755 "$S/$1"; }
ln -s "$(command -v python3)" "$S/python3"; ln -s "$(command -v bash)" "$S/bash"   # 대역 PATH 는 $S 하나 — 실 명령이 섞이지 않게(빠진 대역 = «명령 없음»)
mk uptime 'echo " 2:00  up 2:01, 3 users, load averages: 20.00 18.50 15.25"'
mk sysctl 'case "$2" in kern.boottime) echo "{ sec = 1000000, usec = 0 } Sun Oct 25 00:22:00 2026";; vm.swapusage) echo "total = 2048.00M  used = 512.25M  free = 1535.75M  (encrypted)";; *) exit 1;; esac'
mk memory_pressure 'echo "System-wide memory free percentage: 70%"'
mk df 'echo "Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on"; echo "/dev/disk3s5 1948455240 1748607652 167772160 91% 1 1 1% /System/Volumes/Data"'
mk ps 'printf "%s\n" "  10  409600  20.0 /Users/x/.local/bin/claude --model a" "  11  204800  10.0 claude -p --model claude-haiku-5-5" "  12  102400   1.0 node /x/y.js" "  13  102400  50.0 next-server (v16.2.7)" "  14   51200   0.5 /opt/homebrew/bin/python3 a.py" "  15   51200   0.5 Python b.py" "  16   20480   3.0 pi --model x" "  17   10240   0.0 limactl hostagent" "  18    1024   0.0 /bin/zsh"'
cat > "$S/tmux" <<'STUB'
#!/bin/sh
echo "tmux $*" >> "$CALLS"
[ -n "${FAKE_SLOW_tmux:-}" ] && exec /bin/sleep ${FAKE_SLEEP:-3}
printf '%s\n' '$0' '$1' '$2'
STUB
chmod 755 "$S/tmux"
mk git 'printf "worktree /r\nHEAD 1\n\nworktree /r/.worktrees/a\nHEAD 2\n\nworktree /r/.worktrees/b\nHEAD 3\n"'
mk lsof 'echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NLINK NODE NAME"; echo "python 14 u 3w REG 1,18 1073741824 0 5 /tmp/big log.txt"; echo "python 14 u 4w REG 1,18 1048576 0 6 /tmp/x"; echo "claude 10 u 5w REG 1,18 2097152 0 7 /tmp/y"; echo "node 12 u 6r DIR 1,18 64 0 8 /tmp/d"'
mk colima 'echo "time=x level=info msg=\"colima is running using macOS Virtualization.Framework\"" >&2'
DAY1=$((1000000 + 7200)); DAY2=$((DAY1 + 86400))
SUMD="$T/summary"
run() { # run <FT_NOW> [env…] — 가짜 PATH · 임시 루트 · 1회
  local now="$1"; shift
  env PATH="$S" FT_ROOT="$R" FT_NOW="$now" TZ=Asia/Seoul FT_POSTBOOT_SUMMARY_DIR="$SUMD" "$@" \
    bash "${SUT:-$BIN/ft-postboot-measure.sh}" ${SUT_ARGS:+"${SUT_ARGS}"} >"$T/out" 2>&1; RC=$?; }
STF="$R/.fable-team/state/postboot-measure.tsv"

bash -n "$BIN/ft-postboot-measure.sh" 2>/dev/null && ok "bash -n" || bad "bash -n"
for f in ft-postboot-measure.sh ft_postboot_measure.py ft_postboot_report.py; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "짝 사본 cmp 0 $f" || bad "짝 사본 어긋남 $f"; done

# ── ⓐ 한 회 측정 = 상태 파일 1행 · 9항목 + 보조 ──
: > "$CALLS"; run "$DAY1"
[ "$RC" = 0 ] && ok "ⓐ rc0" || bad "ⓐ rc=$RC $(cat "$T/out")"
[ "$(grep -vc '^#' "$STF" 2>/dev/null)" = 2 ] && ok "ⓐ 상태 파일 = 머리 1 + 행 1" || bad "ⓐ 상태 파일 줄 수 $(cat "$STF" 2>/dev/null | head -3)"
row="$(tail -1 "$STF" 2>/dev/null)"; hdr="$(grep -v '^#' "$STF" 2>/dev/null | head -1)"
col() { python3 -I -c 'import sys;h=sys.argv[1].split("\t");r=sys.argv[2].split("\t");print(r[h.index(sys.argv[3])] if sys.argv[3] in h else "<칸 없음>")' "$hdr" "$row" "$1"; }
for kv in boot_min=120 disk_avail_gib=160.0 swap_used_mib=512 mem_free_pct=70 load15=15.25 claude_n=2 tmux_n=3 worktrees_n=3 next_n=1 \
          next_cpu=50.0 pi_n=1 python_n=2 node_n=1 limactl_n=1 claude_rss_mib=600 deleted_mib=1027 colima=실행; do
  k="${kv%%=*}"; v="${kv#*=}"; got="$(col "$k")"
  [ "$got" = "$v" ] && ok "ⓐ $k=$v" || bad "ⓐ $k «${got}» ≠ «${v}»"; done
has "$(col deleted_top)" "python:14=1025" "ⓐ 지운 채 쥔 파일 상위 프로세스(python:14 1025MiB)"
has "$(cat "$T/out")" "postboot-measure" "ⓐ 로그 1줄"
[ "$(grep -c . "$T/out")" = 1 ] && ok "ⓐ 실행당 출력 1줄(launchd 로그 증가 최소)" || bad "ⓐ 출력 줄 수 $(grep -c . "$T/out")"

# ── ⓒ 읽기 전용: 호출 목록 = 허용 명령만 ──
ALLOW='^(uptime|sysctl -n kern\.boottime|sysctl -n vm\.swapusage|memory_pressure|df -k /System/Volumes/Data|ps -axo pid=,rss=,pcpu=,args=|tmux ls -F #\{session_id\}|git -C [^ ]+ worktree list --porcelain|lsof -nP \+L1|colima status)$'
bad_calls="$(grep -Ev "$ALLOW" "$CALLS")"
[ -z "$bad_calls" ] && [ "$(grep -c . "$CALLS")" = 10 ] && ok "ⓒ 호출 10개 전부 허용 목록(kill·rm·worktree 변경 0)" || bad "ⓒ 허용 밖 호출: «${bad_calls}» (총 $(grep -c . "$CALLS"))"

# ── ⓑ 시간 초과 = «시간 초과» 칸(0·빈 칸 0) · lsof 크기 비례 상한 · 70초 천장 ──
run "$((DAY1 + 7200))" FT_POSTBOOT_CMD_TIMEOUT=1 FAKE_SLOW_lsof=1 FAKE_SLOW_tmux=1 FAKE_SLEEP=9
row="$(tail -1 "$STF")"
[ "$(col deleted_mib)" = "시간 초과" ] && [ "$(col tmux_n)" = "오류(시간 초과)" ] && ok "ⓑ 느린 lsof → «시간 초과» · 느린 tmux → «오류(시간 초과)»" || bad "ⓑ 시간 초과 칸 «$(col deleted_mib)»·«$(col tmux_n)»"
[ "$(col claude_n)" = 2 ] && ok "ⓑ 다른 칸은 정상 값" || bad "ⓑ 다른 칸 «$(col claude_n)»"
has "$(cat "$T/out")" "timeouts=1" "ⓑ 로그 줄에 시간 초과 수"
caps="$(cd "$BIN" && python3 -I -c 'import sys;sys.path.insert(0,".");import ft_postboot_measure as m;print(m.lsof_cap(100,7.0),m.lsof_cap(1200,7.0),m.lsof_cap(100000,7.0),m.lsof_cap(None,7.0))')"
[ "$caps" = "14.0 28.0 70.0 7.0" ] && ok "ⓑ lsof 상한 = 고정비 + 7초×ceil(프로세스/500) · 70초 천장 · 모름=7초" || bad "ⓑ lsof 상한 «${caps}»"
mv "$S/memory_pressure" "$S/mp.off"; run "$((DAY1 + 7400))"; mv "$S/mp.off" "$S/memory_pressure"
row="$(tail -1 "$STF")"; has "$(col mem_free_pct)" "실패" "ⓑ 명령 없음 → «실패…»(0 아님)"

# ── ⓓ·ⓔ 날이 바뀐 첫 회 = 전날 요약 1장 · 기준선 열 · 차이 열 · 커밋 0 ──
: > "$CALLS"; run "$DAY2"
d1="$(TZ=Asia/Seoul date -r "$DAY1" +%Y-%m-%d)"; SUMF="$SUMD/SUMMARY-postboot-$d1.md"
[ -f "$SUMF" ] && ok "ⓓ 전날 요약 1장 $d1" || bad "ⓓ 요약 없음: $(ls "$SUMD" 2>&1)"
[ "$(ls "$SUMD" 2>/dev/null | grep -c .)" = 1 ] && ok "ⓓ 요약 파일 1개(오늘 것 0)" || bad "ⓓ 요약 수 $(ls "$SUMD")"
sm="$(cat "$SUMF" 2>/dev/null)"
has "$sm" "기준선 (재부팅 직후 00:33)" "ⓔ 기준선 열"
has "$sm" "| 디스크 여유 GiB | 182 |" "ⓔ 기준선 값 디스크 182"
has "$sm" "−22.0" "ⓔ 차이 열(마지막 측정 − 기준선: 디스크 160−182)"
has "$sm" "시간 초과" "ⓔ 요약도 시간 초과를 그대로"
! grep -q '^git .*\(commit\|add\|push\)' "$CALLS" && ok "ⓓ 커밋·add·push 0" || bad "ⓓ git 쓰기 호출"
run "$((DAY2 + 7200))"; [ "$(ls "$SUMD" | grep -c .)" = 1 ] && ok "ⓓ 같은 날 두 번째 회 = 요약 추가 0" || bad "ⓓ 요약 중복 $(ls "$SUMD")"
SUT_ARGS=--summary run "$((DAY2 + 7300))"; d2="$(TZ=Asia/Seoul date -r "$DAY2" +%Y-%m-%d)"
[ -f "$SUMD/SUMMARY-postboot-$d2.md" ] && ok "ⓓ --summary = 오늘 요약 즉시(master 2·4시간 실측용)" || bad "ⓓ --summary 없음"

# ── ⓖ DA r1 반례 4: 오류를 0 으로 숨김 0(tmux·lsof) · 상한 7초(env 80 → 7) · 로그가 닫는 사건 없이 자람 ──
cp "$S/tmux" "$T/tmux.ok"; cp "$S/lsof" "$T/lsof.ok"
tmux_err() { printf '#!/bin/sh\necho "tmux${*:+ $*}" >> "%s"\necho "error connecting to /tmp/tmux-501/default (Permission denied)" >&2\nexit 1\n' "$CALLS" > "$S/tmux"; chmod 755 "$S/tmux"; }
lsof_part() { printf '#!/bin/sh\necho "lsof${*:+ $*}" >> "%s"\necho "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NLINK NODE NAME"\necho "python 14 u 3w REG 1,18 1073741824 0 5 /tmp/big log.txt"\necho "lsof: WARNING: Output information may be incomplete." >&2\nexit 1\n' "$CALLS" > "$S/lsof"; chmod 755 "$S/lsof"; }
tmux_err; run "$((DAY2 + 10800))"
row="$(tail -1 "$STF")"
has "$(col tmux_n)" "오류" "ⓖ R1 tmux 접속 실패(rc1 Permission denied) → «오류(사유)»(세션 0 아님)"
lsof_part; run "$((DAY2 + 11000))"
row="$(tail -1 "$STF")"
has "$(col deleted_mib)" "불완전" "ⓖ R2 lsof rc1 + «Output information may be incomplete» → «불완전(사유)»"
has "$(col deleted_mib)" "참고=" "ⓖ R2 셈은 참고값으로 남김(0 으로 숨김 0)"
has "$(col deleted_top)" "python:14" "ⓖ R2 상위 프로세스도 남김"
cp "$T/tmux.ok" "$S/tmux"; cp "$T/lsof.ok" "$S/lsof"
capv="$(cd "$BIN" && python3 -I -c 'import sys;sys.path.insert(0,".");import ft_postboot_measure as m;print(m.base_cap("80"),m.base_cap("3"),m.base_cap("x"),m.lsof_cap(100000,7.0))')"
[ "$capv" = "7.0 3.0 7.0 70.0" ] && ok "ⓖ R3 env 80 → 7 · env 3 → 3 · 해석 불가 → 7 · lsof 천장 70" || bad "ⓖ R3 상한 «${capv}»"
LOG="$R/.fable-team/state/postboot-measure.log"
python3 -I -c 'import sys;open(sys.argv[1],"w").write("x"*1200000)' "$LOG"
run "$((DAY2 + 20000))"
[ "$(wc -c < "$LOG")" -lt 1048576 ] && grep -q '회전' "$LOG" && ok "ⓖ R4 1MiB 넘은 로그 → 회전(닫는 사건)" || bad "ⓖ R4 로그 $(wc -c < "$LOG") bytes · «$(head -1 "$LOG" | cut -c1-40)»"
python3 -I -c 'import sys;open(sys.argv[1],"w").write("y"*5000)' "$LOG"
SUT_ARGS=--summary run "$((DAY2 + 20100))"
[ "$(wc -c < "$LOG")" -lt 200 ] && grep -q '비움' "$LOG" && ok "ⓖ R4 하루 요약 → 로그 비움" || bad "ⓖ R4 요약 뒤 로그 $(wc -c < "$LOG") bytes"

# ── ⓗ DA r2 반례 7건: 오판(tmux 경로 글자·개행 이름) · 표식 빠짐(lsof rc0 경고·rc1 무출력) · 로그 자람(상태 폴더 쓰기 불가) · 쓰기 범위(요약 자리) ──
tmux_path_err() { cat > "$S/tmux" <<'STUB'
#!/bin/sh
echo "error connecting to /tmp/no server running/default (Permission denied)" >&2
exit 1
STUB
chmod 755 "$S/tmux"; }
tmux_nosrv() { cat > "$S/tmux" <<'STUB'
#!/bin/sh
echo "no server running on /tmp/tmux-501/default" >&2
exit 1
STUB
chmod 755 "$S/tmux"; }
lsof_rc0_warn() { cat > "$S/lsof" <<'STUB'
#!/bin/sh
echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NLINK NODE NAME"
echo "python 14 u 3w REG 1,18 1073741824 0 5 /tmp/big log.txt"
echo "lsof: WARNING: Output information may be incomplete." >&2
exit 0
STUB
chmod 755 "$S/lsof"; }
lsof_empty() { cat > "$S/lsof" <<'STUB'
#!/bin/sh
echo "lsof: WARNING: Output information may be incomplete." >&2
exit 1
STUB
chmod 755 "$S/lsof"; }
tmux_path_err; run "$((DAY2 + 40000))"; row="$(tail -1 "$STF")"
has "$(col tmux_n)" "오류" "ⓗ R1 tmux stderr 경로 속 «no server running» 글자 → 오류(서버 없음 오판 0)"
tmux_nosrv; run "$((DAY2 + 40200))"; row="$(tail -1 "$STF")"; got="$(col tmux_n)"
[ "$got" = 0 ] && ok "ⓗ R1 진짜 «no server running»(줄 머리) → 세션 0" || bad "ⓗ R1 서버 없음 «${got}»"
lsof_rc0_warn; run "$((DAY2 + 40600))"; row="$(tail -1 "$STF")"
has "$(col deleted_mib)" "불완전" "ⓗ R2 lsof rc0 + incomplete 경고 → 불완전 표식 유지"
has "$(col deleted_mib)" "참고=1024" "ⓗ R2 rc0 경고도 참고값을 남김"
lsof_empty; run "$((DAY2 + 40800))"; row="$(tail -1 "$STF")"
has "$(col deleted_mib)" "참고=0" "ⓗ R5 lsof rc1 출력 없음 → 참고=0(계약) "
cp "$T/tmux.ok" "$S/tmux"; cp "$T/lsof.ok" "$S/lsof"
env PATH="$S" FT_ROOT="$R" FT_NOW="$((DAY2 + 86400 + 100))" TZ=Asia/Seoul bash "$BIN/ft-postboot-measure.sh" >"$T/out7" 2>&1; rc7=$?
[ "$rc7" = 0 ] && [ -f "$R/.fable-team/state/SUMMARY-postboot-$d2.md" ] && [ ! -d "$R/design" ] && ok "ⓗ R7 요약 기본 자리 = 상태 폴더(추적 경로 design/teams/planner 쓰기 0)" || bad "ⓗ R7 rc=$rc7 상태폴더=$(ls "$R/.fable-team/state" | tr '\n' ' ')"

# ── 상태 파일 닫는 사건: FT_POSTBOOT_KEEP_DAYS 지난 행은 다음 기록 때 빠진다 ──
run "$((DAY2 + 86400 * 20))"; [ "$(grep -v '^#' "$STF" | grep -c .)" = 2 ] && ok "닫는 사건: 14일 지난 행 정리(머리 + 새 행 1)" || bad "보관 정리 안 됨 $(grep -vc '^#' "$STF")"
env -u FT_ROOT PATH="$S" bash "$BIN/ft-postboot-measure.sh" >"$T/o2" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q 'FT_ROOT' "$T/o2" && ok "FT_ROOT 없음 → ERROR rc≠0(#0 RULE)" || bad "FT_ROOT 없음 rc=$rc"

# ── plist 틀: 2시간 · 루트 shim · 자리표시 ──
if [ -f "$TPL" ]; then
  plutil -lint "$TPL" >/dev/null && ok "plist lint" || bad "plist lint"
  [ "$(plutil -extract StartInterval raw "$TPL")" = 7200 ] && ok "plist StartInterval 7200" || bad "plist 주기"
  [ "$(plutil -extract ProgramArguments.1 raw "$TPL")" = "__FT_BIN__/ft-postboot-measure.sh" ] && ok "plist 실행 = __FT_BIN__ shim" || bad "plist 실행 경로"
  [ "$(plutil -extract Label raw "$TPL")" = com.byz.ft-postboot-measure ] && ok "plist Label" || bad "plist Label"
  outp="$(plutil -extract StandardOutPath raw "$TPL")"; errp="$(plutil -extract StandardErrorPath raw "$TPL")"
  [ "$outp" = "__BYZ_ROOT__/.fable-team/state/postboot-measure.log" ] && [ "$errp" = "$outp" ] && ok "ⓖ R4 plist 로그 = 상태 파일 옆 1개(닫는 사건 있는 자리)" || bad "ⓖ R4 plist 로그 «${outp}»·«${errp}»"
else bad "plist 틀 없음"; fi

# ── ⓕ 변이 2종: 사본에서 바꾸면 ⓑ·ⓒ 가 잡는다 ──
M="$T/mut"; mkdir -p "$M"; cp "$BIN"/ft-postboot-measure.sh "$BIN"/ft_postboot_*.py "$M/"
sed -i '' 's/^TIMEOUT_CELL = "시간 초과"/TIMEOUT_CELL = "0"/' "$M/ft_postboot_measure.py"
rm -f "$STF"; SUT="$M/ft-postboot-measure.sh" run "$DAY1" FT_POSTBOOT_CMD_TIMEOUT=1 FAKE_SLOW_lsof=1 FAKE_SLEEP=9; row="$(tail -1 "$STF")"
[ "$(col deleted_mib)" != "시간 초과" ] && ok "ⓕ 변이1(시간 초과→0) → ⓑ FAIL 로 잡힘" || bad "ⓕ 변이1 이 안 잡힘"
cp "$BIN"/ft_postboot_measure.py "$M/"; sed -i '' 's/\["colima", "status"\]/["colima", "stop"]/' "$M/ft_postboot_measure.py"
: > "$CALLS"; SUT="$M/ft-postboot-measure.sh" run "$DAY1"
[ -n "$(grep -Ev "$ALLOW" "$CALLS")" ] && ok "ⓕ 변이2(쓰기 명령 colima stop) → ⓒ FAIL 로 잡힘" || bad "ⓕ 변이2 가 안 잡힘"

# ── ⓖ 변이 3~6: 고침 넷에 각각 1개(되살리면 그 시험이 빨강) ──
py_mut() { python3 -I - "$M/ft_postboot_measure.py" "$1" "$2" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if a not in s:
    sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
}
cp "$BIN/ft_postboot_measure.py" "$M/"
if py_mut '    return "오류(rc=%d %s)" % (rc, (txt.splitlines()[0] if txt else "사유 없음")[:40])' '    return 0'; then
  tmux_err; SUT="$M/ft-postboot-measure.sh" run "$((DAY2 + 30000))"; row="$(tail -1 "$STF")"
  got="$(col tmux_n)"; [ "$got" = 0 ] && ok "ⓕ 변이3(tmux 오류→0 되돌림) → ⓖ R1 FAIL 로 잡힘" || bad "ⓕ 변이3 이 안 잡힘 «${got}»"
else bad "ⓕ 변이3 자리 못 찾음"; fi
cp "$T/tmux.ok" "$S/tmux"; cp "$BIN/ft_postboot_measure.py" "$M/"
if py_mut '    return "불완전(rc=%d %s) 참고=%d" % (rc, why, mib), top' '    return 0, "없음"'; then
  lsof_part; SUT="$M/ft-postboot-measure.sh" run "$((DAY2 + 30200))"; row="$(tail -1 "$STF")"
  got="$(col deleted_mib)"; [ "$got" = 0 ] && ok "ⓕ 변이4(lsof 불완전→0 숨김 되돌림) → ⓖ R2 FAIL 로 잡힘" || bad "ⓕ 변이4 가 안 잡힘 «${got}»"
else bad "ⓕ 변이4 자리 못 찾음"; fi
cp "$T/lsof.ok" "$S/lsof"; cp "$BIN/ft_postboot_measure.py" "$M/"
if py_mut '    return min(base + MAX_BASE * math.ceil(procs / BATCH), MAX_CAP)' '    return base * math.ceil(procs / BATCH)'; then
  mcap="$(cd "$M" && python3 -I -c 'import sys;sys.path.insert(0,".");import ft_postboot_measure as m;print(m.lsof_cap(1200,7.0))')"
  [ "$mcap" != "28.0" ] && ok "ⓕ 변이5(상한 식 되돌림) → ⓖ R3 FAIL 로 잡힘" || bad "ⓕ 변이5 가 안 잡힘"
else bad "ⓕ 변이5 자리 못 찾음"; fi
cp "$BIN/ft_postboot_measure.py" "$M/"
if py_mut '    elif size > LOG_MAX:' '    elif False:'; then
  python3 -I -c 'import sys;open(sys.argv[1],"w").write("x"*1200000)' "$LOG"; SUT="$M/ft-postboot-measure.sh" run "$((DAY2 + 30400))"
  [ "$(wc -c < "$LOG")" -ge 1048576 ] && ok "ⓕ 변이6(로그 회전 제거) → ⓖ R4 FAIL 로 잡힘" || bad "ⓕ 변이6 이 안 잡힘"
else bad "ⓕ 변이6 자리 못 찾음"; fi

# ── ⓗ 변이 7~8·11: r2 반례 고침 셋에 각각 1개 ──
cp "$BIN/ft_postboot_measure.py" "$M/"
if py_mut 're.search(r"(?m)^\s*no server running\b", txt)' 're.search(r"no server running", txt)'; then
  tmux_path_err; SUT="$M/ft-postboot-measure.sh" run "$((DAY2 + 50000))"; row="$(tail -1 "$STF")"; got="$(col tmux_n)"
  [ "$got" = 0 ] && ok "ⓕ 변이7(줄머리 앙커 제거) → ⓗ R1 FAIL 로 잡힘" || bad "ⓕ 변이7 이 안 잡힘 «${got}»"
else bad "ⓕ 변이7 자리 못 찾음"; fi
cp "$T/tmux.ok" "$S/tmux"; cp "$BIN/ft_postboot_measure.py" "$M/"
if py_mut 'if rc == 0 and not re.search(r"incomplete", txt, re.I):' 'if rc == 0:'; then
  lsof_rc0_warn; SUT="$M/ft-postboot-measure.sh" run "$((DAY2 + 50200))"; row="$(tail -1 "$STF")"; got="$(col deleted_mib)"
  [ "$got" = 1024 ] && ok "ⓕ 변이8(rc0 경고 무시) → ⓗ R2 FAIL 로 잡힘" || bad "ⓕ 변이8 이 안 잡힘 «${got}»"
else bad "ⓕ 변이8 자리 못 찾음"; fi
if py_mut 'os.environ.get("FT_POSTBOOT_SUMMARY_DIR") or os.path.dirname(state)' 'os.environ.get("FT_POSTBOOT_SUMMARY_DIR") or os.path.join(root, "design", "teams", "planner", "postboot")'; then
  rm -rf "$R/design"; env PATH="$S" FT_ROOT="$R" FT_NOW="$((DAY2 + 86400 * 2 + 100))" TZ=Asia/Seoul bash "$M/ft-postboot-measure.sh" >"$T/out11" 2>&1
  [ -d "$R/design" ] && ok "ⓕ 변이11(요약을 추적 경로에 씀) → ⓗ R7 FAIL 로 잡힘" || bad "ⓕ 변이11 이 안 잡힘"
else bad "ⓕ 변이11 자리 못 찾음"; fi

echo "($fail failed)"; [ "$fail" = 0 ]
