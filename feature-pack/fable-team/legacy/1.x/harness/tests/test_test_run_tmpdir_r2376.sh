#!/usr/bin/env bash
# test_test_run_tmpdir_r2376.sh — r2376: 시험 러너(ft-test-run.sh)가 시험마다 자기 임시 폴더($TMPDIR/tmp.ftpytest.XXXXXX)를 만들어
#   그 시험의 TMPDIR 로 주고, 묶음 정리(reap) 뒤 그 폴더 하나만 지운다. 러너 안에서 러너를 부르면(겹침) 새로 만들지 않고 그대로 쓴다.
#   케이스 ①~⑪(바깥 TMPDIR = 케이스마다 $T 아래 새 폴더 · 공용 TMPDIR 손 0) · 변이 M1~M7(사본에서만 · 변이마다 원본 같은 사례 1회) · ⑫ 회귀 = tmux 격리 시험 러너 2겹
#   상한 70초: 자기 자신을 다시 부르지 않는다 · 실 pytest 0 · 실 좌석 kill 0 · 고정 sleep 0(폴링만) · 남은 자식은 EXIT trap 이 $T 경로로만 끝낸다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"; BIN="$REPO/bin"; KIT="$REPO/kit/fable-team/bin"
RUN="$BIN/ft-test-run.sh"; SCRATCH="$KIT/ft-scratch-repo.sh"; TMUXISO="$REPO/tests/test_tmux_isolate.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
rx()  { printf '%s' "$1" | grep -Eq -- "$2" && ok "$3" || bad "$3 — 패턴 없음: «${2}» ← ${1:0:200}"; }
T="$(cd "$(mktemp -d)" && pwd -P)"; SHORT=""
trap 'pkill -9 -f -- "${T:?}/" 2>/dev/null; [ -z "$SHORT" ] || rm -rf "$SHORT"; rm -rf "$T"' EXIT   # $T 경로를 가진 자식만 끝낸다(실 좌석·남의 시험 0)

# ── 가짜 도구·가짜 시험(전부 $T 안 · 파일 이름에 .sh 를 안 붙여 러너 lint 를 안 태운다)
mkdir -p "$T/fx" "$T/fmk" "$T/frm"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/fx/quiesce"          # ft-seat-quiesce.sh 대역(정리할 LSP 없음)
printf '#!/usr/bin/env bash\necho "REENTRY %s:1" "$1"\nexit 1\n' > "$T/fx/lint_rej"   # lint 거절(rc≠3)
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/fmk/mktemp"          # mktemp 실패 대역
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/frm/rm"              # 지우기 실패 대역(하드 룰 19 갈래 아님 · rc1 주입)
chmod +x "$T/fx/quiesce" "$T/fx/lint_rej" "$T/fmk/mktemp" "$T/frm/rm"
QF="$T/fx/quiesce"
cat > "$T/f_echo" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$TMPDIR" > "${R2376_OUT:?}"
exit 0
F
cat > "$T/f_py" <<'F'
#!/usr/bin/env bash
python3 -c 'import tempfile; print(tempfile.mkdtemp())' > "${R2376_OUT:?}"
exit 0
F
cat > "$T/f_r0" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$TMPDIR" > "${R2376_OUT:?}"
: > "$TMPDIR/file1"; mkdir -p "$TMPDIR/sub/deep"; : > "$TMPDIR/sub/deep/file2"
exit 0
F
cat > "$T/f_r3" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$TMPDIR" > "${R2376_OUT:?}"
: > "$TMPDIR/file1"; mkdir -p "$TMPDIR/sub"
exit 3
F
cat > "$T/f_slow" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$TMPDIR" > "${R2376_OUT:?}"
trap '' TERM
python3 -c 'import signal,time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
for _ in range(200): time.sleep(0.1)' &
wait
F
cat > "$T/f_sleep" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$TMPDIR" > "${R2376_OUT:?}"
sleep 30
F
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bad.sh"              # ⑩ lint 대상(러너가 이 .sh 를 lint 에 넘긴다)
cat > "$T/f_env" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$TMPDIR" > "${R2376_INNER_OUT:?}"
mkdir -p "$TMPDIR/folder11"
exit 0
F
cat > "$T/f_outer11" <<'F'
#!/usr/bin/env bash
{ printf 'outer=%s\n' "$TMPDIR"
  bash "$R2376_RUN" bash "$R2376_INNER" > "$R2376_LOG" 2>&1; printf 'rc=%s\n' "$?"
  [ -d "$TMPDIR/folder11" ] && echo 'innerfolder=yes' || echo 'innerfolder=no'
} > "${R2376_OUT:?}"
exit 0
F
bash -n "$RUN" && ok "bash -n runner" || bad "bash -n runner"
cmp -s "$RUN" "$KIT/ft-test-run.sh" && ok "키트 사본 cmp 0" || bad "키트 사본 어긋남"
r() { # <러너> <바깥 TMPDIR> <로그> <시험…> → rc
  local rn="$1" o="$2" lg="$3"; shift 3
  TMPDIR="$o" FT_SEAT_QUIESCE_BIN="$QF" R2376_OUT="$o.out" bash "$rn" "$@" > "$lg" 2>&1
}

# ① 시험이 echo $TMPDIR → 바깥 TMPDIR 바로 아래 tmp.ftpytest.* (기준판 = 바깥 그대로 → Red)
c1() { local rn="$1" o="$T/1"; rm -rf "$o" "$o.out"; mkdir -p "$o"; r "$rn" "$o" "$T/1.log" bash "$T/f_echo"
  case "$(head -1 "$o.out" 2>/dev/null)" in "$o"/tmp.ftpytest.*) return 0;; esac; return 1; }
c1 "$RUN" && ok "① 시험 TMPDIR = 바깥 바로 아래 tmp.ftpytest.*" || bad "① 시험 TMPDIR «$(head -1 "$T/1.out" 2>/dev/null)» 가 tmp.ftpytest.* 아님"

# ② bash 감싼 python tempfile.mkdtemp() → 만든 폴더가 ① 폴더 안
o2="$T/2"; mkdir -p "$o2"; r "$RUN" "$o2" "$T/2.log" bash "$T/f_py"
case "$(head -1 "$o2.out")" in "$o2"/tmp.ftpytest.*/*) ok "② tempfile.mkdtemp 도 그 폴더 안";; *) bad "② «$(head -1 "$o2.out")» 가 그 폴더 안 아님";; esac

# ③ mktemp 실패 → 판정 불가 1줄 · rc 20 · 시험 명령 부름 0
c3() { local rn="$1" o="$T/3"; rm -rf "$o" "$o.out"; mkdir -p "$o"
  PATH="$T/fmk:$PATH" TMPDIR="$o" FT_SEAT_QUIESCE_BIN="$QF" R2376_OUT="$o.out" bash "$rn" bash "$T/f_echo" > "$T/3.log" 2>&1; echo $?; }
eq "$(c3 "$RUN")" 20 "③ mktemp 실패 rc 20"
rx "$(cat "$T/3.log")" '판정 불가 — 임시 폴더를 못 만듦' "③ 판정 불가 1줄"
[ -s "$T/3.out" ] && bad "③ 시험 명령이 불렸다" || ok "③ 시험 명령 부름 0"

# ④ 시험이 파일·하위 폴더를 쓰고 rc 0 → 러너 뒤 폴더 0 (기준판 = 남음 → Red) · ⑤ rc 3 → 폴더 0 · rc 3
c4() { local rn="$1" o="$T/4"; rm -rf "$o" "$o.out"; mkdir -p "$o"; r "$rn" "$o" "$T/4.log" bash "$T/f_r0"; echo $?; }
eq "$(c4 "$RUN")" 0 "④ rc 0 그대로"
[ -d "$(head -1 "$T/4.out")" ] && bad "④ 끝나고 임시 폴더 남음 $(head -1 "$T/4.out")" || ok "④ 끝나고 임시 폴더 0"
[ -z "$(ls -A "$T/4")" ] && ok "④ 바깥 TMPDIR 잔여 0" || bad "④ 바깥 TMPDIR 에 남음: $(ls -A "$T/4" | tr '\n' ' ')"
c5() { local rn="$1" o="$T/5"; rm -rf "$o" "$o.out"; mkdir -p "$o"; r "$rn" "$o" "$T/5.log" bash "$T/f_r3"; echo $?; }
eq "$(c5 "$RUN")" 3 "⑤ 시험 rc 3 그대로"
[ -d "$(head -1 "$T/5.out")" ] && bad "⑤ rc3 인데 폴더 남음" || ok "⑤ rc3 여도 폴더 0"

# ⑥ 상한(2초) 넘김 + TERM 무시 자식 → timeout rc · reap 뒤 폴더 0 (기준판 = 남음 → Red)
c6() { local rn="$1" o="$T/6"; rm -rf "$o" "$o.out"; mkdir -p "$o"
  TMPDIR="$o" FT_SEAT_QUIESCE_BIN="$QF" FT_TEST_TIMEOUT_SEC=2 R2376_OUT="$o.out" bash "$rn" bash "$T/f_slow" > "$T/6.log" 2>&1; echo $?; }
SECONDS=0; r6="$(c6 "$RUN")"; e6=$SECONDS
case "$r6" in 124|137) ok "⑥ 상한 초과 timeout rc $r6";; *) bad "⑥ 상한 초과 rc «$r6» — 124/137 아님";; esac
[ "$e6" -le 15 ] && ok "⑥ 상한+5초 안에 끝(${e6}초)" || bad "⑥ 너무 늦음 ${e6}초"
[ -d "$(head -1 "$T/6.out")" ] && bad "⑥ KILL 뒤 폴더 남음" || ok "⑥ KILL 뒤 폴더 0"
rx "$(cat "$T/6.log")" '남은 묶음 0' "⑥ 묶음 정리 줄 그대로"

# ⑦ 지우기 실패(가짜 rm rc1) → «WARN 시험 임시 폴더 남음» 1줄 · rc = 시험 rc
c7() { local rn="$1" o="$T/7"; rm -rf "$o" "$o.out"; mkdir -p "$o"
  PATH="$T/frm:$PATH" TMPDIR="$o" FT_SEAT_QUIESCE_BIN="$QF" R2376_OUT="$o.out" bash "$rn" bash "$T/f_r0" > "$T/7.log" 2>&1; echo $?; }
eq "$(c7 "$RUN")" 0 "⑦ 지우기 실패해도 rc = 시험 rc(0)"
rx "$(cat "$T/7.log")" 'WARN 시험 임시 폴더 남음 ' "⑦ WARN 시험 임시 폴더 남음 1줄"

# ⑧ 바깥 TMPDIR 에 미리 둔 다른 폴더 2개 → 러너 뒤 그대로
o8="$T/8"; mkdir -p "$o8/tmp.other" "$o8/pytest-of-x"; r "$RUN" "$o8" "$T/8.log" bash "$T/f_echo"
[ -d "$o8/tmp.other" ] && [ -d "$o8/pytest-of-x" ] && ok "⑧ 다른 항목 2개 그대로" || bad "⑧ 바깥 다른 항목이 사라짐: $(ls -A "$o8" | tr '\n' ' ')"
[ -z "$(find "$o8" -mindepth 1 -maxdepth 1 -name 'tmp.ftpytest.*' -type d 2>/dev/null)" ] && ok "⑧ tmp.ftpytest.* 잔여 0" || bad "⑧ tmp.ftpytest.* 잔여 있음"

# ⑨ 러너 자신을 SIGKILL → 남은 폴더 1개 · 이름꼴 ^tmp\. · ft-scratch-repo --gate --kind tmp 의 G1·G2 통과
c9() { local rn="$1" o="$T/9"; rm -rf "$o" "$o.out"; mkdir -p "$o"; local i=0
  TMPDIR="$o" FT_SEAT_QUIESCE_BIN="$QF" R2376_OUT="$o.out" bash "$rn" bash "$T/f_sleep" > "$T/9.log" 2>&1 & local rp=$!
  while [ "$i" -lt 100 ] && [ ! -s "$o.out" ]; do sleep 0.05; i=$((i+1)); done
  kill -9 "$rp" 2>/dev/null; wait "$rp" 2>/dev/null
  local p; p="$(head -1 "$o.out" 2>/dev/null)"; p="${p%/}"
  [ -n "$p" ] && [ -d "$p" ] && [ "${p%/*}" = "$o" ] || { echo "GONE"; return 1; }
  printf '%s\n' "${p##*/}" | grep -Eq '^tmp\.[A-Za-z0-9_.-]+$' || { echo "NAME ${p##*/}"; return 1; }
  TMPDIR="$o" bash "$SCRATCH" --gate "$p" --kind tmp > "$T/9.gate" 2>&1
  grep -q '^G1 ok' "$T/9.gate" && grep -q '^G2 ok' "$T/9.gate" || { echo "GATE $(tr '\n' ' ' < "$T/9.gate")"; return 1; }
  return 0; }
c9 "$RUN" && ok "⑨ 러너 KILL → 잔여 폴더 1 · 이름꼴 · gate G1·G2 ok" || bad "⑨ 잔여 폴더/gate 불통과"
[ "$(find "$T/9" -maxdepth 1 -name 'tmp.ftpytest.*' -type d 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && ok "⑨ 잔여 = 1개" || bad "⑨ 잔여 개수가 1 아님"

# ⑩ lint 거절(rc≠3) → 시험 0 · 임시 폴더 만듦 0
o10="$T/10"; mkdir -p "$o10"; FT_TEST_REENTRY_LINT_BIN="$T/fx/lint_rej" TMPDIR="$o10" FT_SEAT_QUIESCE_BIN="$QF" R2376_OUT="$o10.out" bash "$RUN" bash "$T/bad.sh" > "$T/10.log" 2>&1; rc=$?
eq "$rc" 1 "⑩ lint rc 그대로(1)"
[ -z "$(ls -A "$o10")" ] && ok "⑩ lint 가 먼저 — 임시 폴더 만듦 0" || bad "⑩ lint 인데 폴더 생김: $(ls -A "$o10" | tr '\n' ' ')"
[ -e "$o10.out" ] && bad "⑩ lint 인데 시험 명령 불림" || ok "⑩ 시험 명령 부름 0"

# ⑪a 러너 안 러너(바깥 TMPDIR 끝 «/» 있음) → 안쪽 TMPDIR = 바깥 폴더 그대로 · 안쪽이 만든 폴더 남음 · 바깥 끝 0
o11="$T/11"; mkdir -p "$o11"
TMPDIR="$o11" FT_SEAT_QUIESCE_BIN="$QF" R2376_OUT="$T/11.out" R2376_RUN="$RUN" R2376_INNER="$T/f_env" \
  R2376_INNER_OUT="$T/11.inner" R2376_LOG="$T/11.log" bash "$RUN" bash "$T/f_outer11" > "$T/11.outer.log" 2>&1; rc=$?
eq "$rc" 0 "⑪a 겹침 러너 2겹 rc 0"
out11="$(sed -n 's/^outer=//p' "$T/11.out")"
in11="$(head -1 "$T/11.inner")"
eq "${in11%/}" "${out11%/}" "⑪a 안쪽 시험 TMPDIR = 바깥 폴더 그대로(끝 «/»)"
rx "$(cat "$T/11.out")" '^innerfolder=yes$' "⑪a 안쪽이 만든 폴더는 안쪽이 안 지운다"
[ -n "$out11" ] && [ ! -e "$out11" ] && ok "⑪a 바깥 끝에 0(바깥 러너 몫)" || bad "⑪a 바깥 폴더 남음: $out11"
[ -z "$(ls -A "$o11")" ] && ok "⑪a 바깥 TMPDIR 잔여 0" || bad "⑪a 바깥 TMPDIR 에 남음: $(ls -A "$o11" | tr '\n' ' ')"

# ⑪b 겹침 검사(바깥 TMPDIR 끝 «/» 없음) → 새 폴더 0 · 안쪽 TMPDIR = 바깥 폴더 그대로
o11b="$T/o11b/tmp.ftpytest.noslash"; mkdir -p "$o11b"
TMPDIR="$o11b" FT_SEAT_QUIESCE_BIN="$QF" R2376_INNER_OUT="$T/11b.inner" bash "$RUN" bash "$T/f_env" > "$T/11b.log" 2>&1; rc=$?
eq "$rc" 0 "⑪b 겹침(끝 «/» 없음) rc 0"
eq "$(head -1 "$T/11b.inner")" "$o11b/" "⑪b 안쪽 시험 TMPDIR = 바깥 폴더 그대로"
[ -d "$o11b/folder11" ] && ok "⑪b 겹침이면 지움 0(안쪽이 만든 폴더 남음)" || bad "⑪b 겹침인데 안쪽 폴더가 지워짐"
[ -z "$(find "$o11b" -mindepth 1 -maxdepth 1 -name 'tmp.ftpytest.*' -type d 2>/dev/null)" ] && ok "⑪b 새 폴더 0" || bad "⑪b 새 폴더 생김"

# ── 변이(사본에서만) — 변이마다 «원본으로 같은 사례 1회» 는 ①·③·④·⑤·⑦·⑨·⑪b 에서 이미 쟀다
mut() { sed "$2" "$RUN" > "$T/mut_$1.sh"; cmp -s "$RUN" "$T/mut_$1.sh" && { bad "변이 $1 적용 안 됨(sed 불일치)"; return 1; }; ok "변이 $1 적용됨"; return 0; }
mut m1 's/TMPDIR="\$TD"; export TMPDIR; //' && { c1 "$T/mut_m1.sh" && bad "M1(TMPDIR 안 줌)인데 ① 통과" || ok "M1 TMPDIR 안 줌 → ① FAIL"; }
mut m2 's/else echo "TEST-RUN 판정 불가 — 임시 폴더를 못 만듦(시험 0)" >&2; exit 20; fi/else TD=""; fi/' && {
  [ "$(c3 "$T/mut_m2.sh")" = 20 ] && bad "M2(mktemp 실패 무시)인데 ③ 통과" || ok "M2 mktemp 실패 무시 → ③ FAIL"; }
mut m3 's/^  rm -rf -- .*$/  :/' && {
  c4 "$T/mut_m3.sh" > /dev/null; [ -d "$(head -1 "$T/4.out" 2>/dev/null)" ] && ok "M3 끝 rm 지움 → ④ FAIL" || bad "M3(rm 끔)인데 ④ 통과"; }
mut m4 's/^tdrm  *# r2376.*$/[ "$rc" = 0 ] \&\& tdrm/' && {
  c5 "$T/mut_m4.sh" > /dev/null; [ -d "$(head -1 "$T/5.out" 2>/dev/null)" ] && ok "M4 rc0 일 때만 지움 → ⑤ FAIL" || bad "M4(rc 조건)인데 ⑤ 통과"; }
mut m5 's/^  rm -rf -- \(.*\) || echo "WARN .*$/  \1/' && {
  c7 "$T/mut_m5.sh" > /dev/null; grep -q 'WARN 시험 임시 폴더 남음 ' "$T/7.log" && bad "M5(WARN 지움)인데 ⑦ 통과" || ok "M5 rm 실패 WARN 지움 → ⑦ FAIL"; }
mut m6 's/tmp\.ftpytest\./ftpytest./g' && {
  c9 "$T/mut_m6.sh" > /dev/null && bad "M6(이름 머리 tmp. 없음)인데 ⑨ 통과" || ok "M6 이름 머리 ftpytest. → ⑨ FAIL"; }
mut m7 's/in tmp\.ftpytest\.\*) TD=/in __nomatch__) TD=/' && {
  o11b2="$T/o11b2/tmp.ftpytest.noslash"; mkdir -p "$o11b2"
  TMPDIR="$o11b2" FT_SEAT_QUIESCE_BIN="$QF" R2376_INNER_OUT="$T/11b2.inner" bash "$T/mut_m7.sh" bash "$T/f_env" > "$T/11b2.log" 2>&1
  [ "$(head -1 "$T/11b2.inner" 2>/dev/null)" = "$o11b2/" ] && bad "M7(겹침 검사 지움)인데 ⑪ 통과" || ok "M7 겹침 검사 지움 → ⑪ FAIL"; }

# ⑫ 회귀 — tmux 격리 시험(tmux_isolate · 소켓 ${TMPDIR}/r957-tmux.*/sock) 을 러너 2겹으로 돌려 PASS · 바깥 끝 잔여 0
#   mac 유닉스 소켓 상한 = 104바이트: /var/folders 밑 TMPDIR(49자) + 시험 폴더 1단(20자) + /r957-tmux.XXXXXX/sock(23자) = 92자로 들어간다.
#   그래서 이 칸은 상한 여유를 보려고 «짧은 뿌리»(/tmp/r2376.XXXXXX)를 쓴다 — 2겹은 겹침이라 한 단만 는다.
o12="$(mktemp -d /tmp/r2376.XXXXXX)"; SHORT="$o12"; SECONDS=0
TMPDIR="$o12" FT_SEAT_QUIESCE_BIN="$QF" bash "$RUN" bash "$RUN" bash "$TMUXISO" > "$T/12.log" 2>&1; rc=$?; e12=$SECONDS
eq "$rc" 0 "⑫ tmux_isolate 러너 2겹 rc 0 (${e12}초)"
rx "$(cat "$T/12.log")" '^ALL PASS$' "⑫ tmux_isolate ALL PASS"
[ -z "$(ls -A "$o12")" ] && ok "⑫ 바깥 끝 잔여 0" || bad "⑫ 바깥 TMPDIR 에 남음: $(ls -A "$o12" | tr '\n' ' ')"
rm -rf "$o12"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAIL $fail 건"; exit 1
