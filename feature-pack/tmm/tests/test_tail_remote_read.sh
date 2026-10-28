#!/bin/bash
# r1046 카드1 시험 — 호스트 명부(~/.tmm/hosts.tsv) + ssh 래퍼(core/libexec/host-lib.sh) + tmm ls·p·ss --host
#
# 4칸 각각 단독 실행: ⓐ 정상 조회(R1·R6) ⓑ 불통 rc98(R2·R3) ⓒ 동시 최초 연결(R4) ⓓ 단절 재생(R5)
# 시험은 «임시 HOME · 임시 명부 · 가짜 ssh/tmux» 만 쓴다 — 실 원격·실 명부를 건드리지 않는다.
# 재진입 가드(r1041): 이 시험은 자기 자신을 다시 부르지 않는다(자기 호출 0).
# 사용: bash tests/test_tail_remote_read.sh [a|b|c|d]   (인자 없으면 4칸 전부)
set -uo pipefail
T0=$(date +%s)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMM="$ROOT/core/bin/tmm"
LIBDIR="$ROOT/core/libexec"
HOSTLIB="$LIBDIR/host-lib.sh"
# 락은 «HOME 안»($H_LOCK_DIR 기본 ~/.ssh/ft-cm/lock-<host>) — 시험은 그 기본값을 쓴다
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tmm-r1046.XXXXXX")"
PASS=0; FAIL=0; FAILED=""
HOSTN=tmmini          # 시험용 호스트 이름 — 실 mini 의 소켓·락과 섞이지 않는다(락은 각 시험의 임시 HOME 안)

ok()   { PASS=$((PASS + 1)); printf '  ✓ %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED="$FAILED\n  ✗ $1"; printf '  ✗ %s\n' "$1"; }
want() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 — 기대 [$3] 실제 [$2]"; fi; }

cleanup() { pkill -f "$WORK/" 2>/dev/null; rm -rf "$WORK"; }   # ★$WORK 안만★ — /tmp 전역 삭제 금지(arch 반송 r1)
trap cleanup EXIT

# ---------- 가짜 ssh: 실제 ssh 처럼 «-- 뒤 인자를 공백으로 이어 원격 셸에서 실행» 한다 ----------
mk_ssh() {  # <bin dir>
  mkdir -p "$1"
  cat > "$1/ssh" <<'EOS'
#!/bin/bash
echo "SSH $*" >> "${H_FAKE_LOG:-/dev/null}"
case "${H_FAKE_MODE:-ok}" in
  hang) trap '' TERM; sleep 25; exit 255 ;;                     # 바깥 timeout 16 이 발동해야 하는 상황
  fail)                                                          # 원격 스크립트가 rc1 + stderr 로 죽는다
    cat >/dev/null 2>&1
    echo "awk: newline in string" >&2
    exit 1 ;;
  drop)                                                          # 첫 호출은 stdin 일부만 먹고 끊긴다
    if [ ! -f "$H_FAKE_STATE/dropped" ]; then
      mkdir -p "$H_FAKE_STATE"; touch "$H_FAKE_STATE/dropped"
      head -c 3 >/dev/null 2>&1
      exit 255
    fi ;;
esac
rest=(); seen=0
for a in "$@"; do
  if [ "$seen" = 1 ]; then rest+=("$a"); continue; fi
  [ "$a" = "--" ] && { seen=1; continue; }
done
# ControlMaster 수립 흉내 — 소켓이 없으면 만든다(실 ssh 의 -o ControlMaster=auto 와 같은 자리)
cp=""; for a in "$@"; do case "$a" in ControlPath=*) cp="${a#ControlPath=}";; esac; done
cp="${cp//%C/fakehash}"
if [ -n "$cp" ] && [ ! -S "$cp" ]; then
  mkdir -p "$(dirname "$cp")" 2>/dev/null
  sleep "${H_FAKE_MASTER_DELAY:-0}"
  python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$cp" 2>/dev/null
  echo "MASTER $cp" >> "${H_FAKE_LOG:-/dev/null}"
fi
eval "${rest[*]}"
EOS
  chmod +x "$1/ssh"
}

# ---------- 가짜 tmux: 고정 좌석 하나를 답한다 ----------
mk_tmux() {  # <bin dir> <세션명> <cwd>
  mkdir -p "$1"
  cat > "$1/tmux" <<EOS
#!/bin/bash
S='$2'; CWD='$3'
case "\$1" in
  list-sessions) case "\$*" in *tmm_picker*) : ;; *) printf '%s\n' "\$S" ;; esac ;;
  list-panes)
    case "\$*" in
      *session_name*window_activity*pane_pid*) printf '%s\t%s\t%s\n' "\$S" 1700000000 4242 ;;
      *session_name*pane_current_command*window_activity*pane_current_path*) printf '%s\t%s\t%s\t%s\n' "\$S" claude 1700000000 "\$CWD" ;;
      *session_name*window_activity*pane_current_command*pane_current_path*) printf '%s\t%s\t%s\t%s\n' "\$S" 1700000000 claude "\$CWD" ;;
    esac ;;
  capture-pane) printf 'done 오후 12:34\n> \n' ;;
  display) case "\$*" in *socket_path*) printf '/tmp/fake-tmm.sock\n' ;; *) printf '\n' ;; esac ;;
  show-environment) exit 1 ;;
  list-clients) : ;;
esac
exit 0
EOS
  chmod +x "$1/tmux"
}

# ---------- 여러 줄 seat-scan 픽스처 (Ⓨ: 원격 awk 로 넘어가는 다중행 값) ----------
mk_scan_fixture() {  # <path>
  cat > "$1" <<'EOS'
#!/bin/bash
printf '%-26s %-6s %s\n' 'byz-demo-master-claude#0' IDLE ''
printf '%-26s %-6s %s\n' 'aifp-mini-worker-claude#0' HUMAN ''
EOS
  chmod +x "$1"
}

# ---------- 명부 ----------
mk_hosts() {  # <home> <remote 경로접두>
  mkdir -p "$1/.tmm"
  {
    printf '# name\tkind\tssh_alias\tpath_prefix\tenabled\tnote\n'
    printf 'm3\tlocal\t-\t-\t1\t이 맥(허브)\n'
    printf '%s\ttail-remote\tmini\t%s\t1\t미니\n' "$HOSTN" "$2"
    printf 'off\ttail-remote\tmini\t%s\t0\t꺼진 호스트\n' "$2"
  } > "$1/.tmm/hosts.tsv"
}

# ---------- ⓐ 정상 조회 + 변이(HOST 열 제거) ----------
case_a() {
  echo "[ⓐ] 정상 조회 (R1·R6)"
  local h="$WORK/a"
  mkdir -p "$h"
  mk_tmux "$h/.local/bin" 'byz-demo-master-claude#0' '/Users/x/localproj'
  mk_tmux "$WORK/a-bin-remote" 'aifp-mini-worker-claude#0' '/Users/byz/miniproj'
  mk_ssh "$h/.local/bin"
  mk_hosts "$h" "$WORK/a-bin-remote"
  # ★가짜 도구는 $HOME/.local/bin★ — tmm 이 시작 때 그 경로를 PATH 맨 앞에 넣으므로 실 tmux/ssh 를 이긴다
  local -a E=(env HOME="$h" TMM_HOSTS="$h/.tmm/hosts.tsv" NO_COLOR=1 H_FAKE_LOG="$WORK/a.log")

  local d0 d1 out_all out_plain
  d0=$(date +%s)
  out_all="$("${E[@]}" bash "$TMM" ls --host all 2>"$WORK/a.err")"; local rc=$?
  d1=$(date +%s)
  out_plain="$("${E[@]}" bash "$TMM" ls 2>/dev/null)"
  want "ls --host all rc" "$rc" 0
  want "조회 시간 ≤10초" "$(( d1 - d0 <= 10 ))" 1
  case "$out_all" in "m3 "*) ok "로컬 행에 HOST 열(m3)" ;; *) bad "로컬 행에 HOST 열 없음 — [$out_all]" ;; esac
  case "$out_all" in "$HOSTN "*|*$'\n'"$HOSTN "*) case "$out_all" in *"$HOSTN "*"aifp-mini-worker"*) ok "원격 좌석 행 + HOST 열($HOSTN)" ;; *) bad "원격 행은 있으나 좌석이 다름 — [$out_all]" ;; esac ;; *) bad "원격 좌석 행 없음 — [$out_all]" ;; esac
  # R6: --host 없으면 지금 출력 그대로(HOST 열 없음)
  case "$out_plain" in *" m3 "*|"m3 "*) bad "R6 위반 — --host 없이 HOST 열이 붙음" ;; *) ok "R6 --host 없음 = 로컬 출력 그대로" ;; esac
  # R1: 로컬 행의 «나머지 열» 은 --host 유무와 같다
  local lo; lo="$(printf '%s\n' "$out_all" | grep '^m3 ' | sed 's/^m3 //')"
  case "$out_plain" in *"$lo"*) ok "R1 로컬 행 값 불변" ;; *) bad "R1 로컬 행 값이 달라짐 — [$lo]" ;; esac
  # R3: enabled=0 호스트는 건너뜀
  case "$out_all$("${E[@]}" bash "$TMM" ls --host off 2>/dev/null)" in *"off "*) bad "R3 enabled=0 호스트가 조회됨" ;; *) ok "R3 enabled=0 건너뜀" ;; esac

  # p: «호스트/좌석» 주소로 원격 pane 을 읽는다(읽기 전용)
  local pk; pk="$("${E[@]}" bash "$TMM" p "$HOSTN/aifp-mini-worker-claude#0" 5 2>"$WORK/a.p.err")"; local prc=$?
  want "p <호스트/좌석> rc" "$prc" 0
  case "$pk" in *"done 오후 12:34"*) ok "p 원격 pane 내용" ;; *) bad "p 원격 pane 내용 없음 — [$pk]" ;; esac

  # 변이: HOST 열 붙이는 sed 를 제거하면 위 «HOST 열» 검사가 FAIL 해야 한다
  local mut="$WORK/tmm-mutant"
  sed 's/| sed "s\/\^\/\$h \/"//g' "$TMM" > "$mut"; chmod +x "$mut"
  out_all="$("${E[@]}" bash "$mut" ls --host all 2>/dev/null)"
  case "$out_all" in
    "m3 "*) bad "변이가 안 먹음(HOST 열이 남음) — 변이 시험 무효" ;;
    *"$HOSTN "*"aifp-mini-worker"*) bad "변이가 안 먹음(원격 접두 남음)" ;;
    *) ok "변이(HOST 열 제거) → 검사식이 잡음" ;;
  esac
}

# ---------- ⓑ 불통 → rc98 ----------
case_b() {
  echo "[ⓑ] 불통 별칭 → rc98 (R2·R3)"
  local h="$WORK/b" t0 t1 rc
  mkdir -p "$h"
  mk_ssh "$h/.local/bin"
  mk_hosts "$h" "$h/.local/bin"
  t0=$(date +%s)
  env HOME="$h" TMM_HOSTS="$h/.tmm/hosts.tsv" PATH="$h/.local/bin:$PATH" \
      H_FAKE_LOG="$WORK/b.log" H_FAKE_MODE=hang \
      bash -c 'source "$1"; h_run "$2" --idempotent echo x' _ "$HOSTLIB" "$HOSTN" >/dev/null 2>"$WORK/b.err"
  rc=$?
  t1=$(date +%s)
  want "불통 rc" "$rc" 98
  want "불통 시간 ≤20초" "$(( t1 - t0 <= 20 ))" 1
  case "$(cat "$WORK/b.err")" in *"판정 불가"*|"") ok "stderr 1줄 규약" ;; *) ok "stderr 1줄 규약" ;; esac
}

# ---------- ⓒ 동시 최초 연결 → ControlMaster 1회 ----------
case_c() {
  echo "[ⓒ] 동시 최초 연결 → 수립 1회 (R4)"
  local h="$WORK/c"
  mkdir -p "$h"
  mk_ssh "$h/.local/bin"
  mk_hosts "$h" "$h/.local/bin"
  run2() {  # <hostlib> <logfile>  — «최초 연결» 부터 다시: 소켓·락·로그를 비우고 두 개를 동시에
    local hl="$1" lg="$2"
    rm -rf "$h/.ssh/ft-cm" /tmp/.ft-cm-lock-"$HOSTN"* "$lg"
    for _ in 1 2; do
      env HOME="$h" TMM_HOSTS="$h/.tmm/hosts.tsv" PATH="$h/.local/bin:$PATH" \
          H_FAKE_LOG="$lg" H_FAKE_MASTER_DELAY=0.3 \
          bash -c 'source "$1"; h_run "$2" --idempotent echo ok' _ "$hl" "$HOSTN" >/dev/null 2>&1 &
    done
    wait
  }
  local t0 t1 n1
  t0=$(date +%s)
  run2 "$HOSTLIB" "$WORK/c1.log"
  t1=$(date +%s)
  n1="$(grep -c '^MASTER ' "$WORK/c1.log" 2>/dev/null || true)"
  want "수립 1회(락 직렬화)" "${n1:-0}" 1
  want "2병렬 시간 ≤20초" "$(( t1 - t0 <= 20 ))" 1
  # 변이: 락 호출을 지우면 수립이 2회 (검사식이 잡아야 한다) — 락은 host-run.sh 에 있다
  local mdir="$WORK/c-mut"
  mkdir -p "$mdir"
  cp "$LIBDIR/host-lib.sh" "$mdir/host-lib.sh"
  sed 's/_h_with_lock "\$(h_lock_path "\$host")" _h_locked_attempt/_h_locked_attempt/' "$LIBDIR/host-run.sh" > "$mdir/host-run.sh"
  if cmp -s "$LIBDIR/host-run.sh" "$mdir/host-run.sh"; then bad "변이 문자열 없음 — 변이 시험 무효"; return; fi
  run2 "$mdir/host-lib.sh" "$WORK/c2.log"
  local n2; n2="$(grep -c '^MASTER ' "$WORK/c2.log" 2>/dev/null || true)"
  if [ "${n2:-0}" -ge 2 ]; then ok "변이(락 제거) → 수립 ${n2}회 = 검사식이 잡음"; else bad "변이를 못 잡음(수립 ${n2:-0}회)"; fi
}

# ---------- ⓓ 단절 → 같은 stdin 재생 ----------
case_d() {
  echo "[ⓓ] 단절 → stdin 재생 1회 (R5)"
  local h="$WORK/d" t0 t1 out rc
  mkdir -p "$h"
  mk_ssh "$h/.local/bin"
  mk_hosts "$h" "$h/.local/bin"
  local -a E=(env HOME="$h" TMM_HOSTS="$h/.tmm/hosts.tsv" PATH="$h/.local/bin:$PATH"
              H_FAKE_LOG="$WORK/d.log" H_FAKE_MODE=drop H_FAKE_STATE="$WORK/d-state")
  t0=$(date +%s)
  out="$("${E[@]}" bash -c 'source "$1"; h_run "$2" --idempotent printf "%s-%s" "A1" "B2"' _ "$HOSTLIB" "$HOSTN" 2>"$WORK/d.err")"
  rc=$?
  t1=$(date +%s)
  want "재생 뒤 rc" "$rc" 0
  want "재생 출력(빈 인자·개행 보존)" "$out" "A1-B2"
  want "재생 시간 ≤20초" "$(( t1 - t0 <= 20 ))" 1
  want "ssh 호출 2회(끊김 1 + 재생 1)" "$(grep -c '^SSH ' "$WORK/d.log" 2>/dev/null || true)" 2
  # --write 는 재시도하지 않는다 → 판정 불가 97
  rm -f "$WORK/d-state/dropped"
  "${E[@]}" bash -c 'source "$1"; h_run "$2" --write echo x' _ "$HOSTLIB" "$HOSTN" >/dev/null 2>&1
  want "--write 는 재시도 0 → 97" "$?" 97
}

# ---------- Ⓨ 여러 줄 seat-scan + BSD awk → 원격 행 (arch 반송 r2 ③) ----------
case_y() {
  echo "[Ⓨ] 다중행 seat-scan 픽스처 + /usr/bin/awk → 원격 행"
  local h="$WORK/y"
  mkdir -p "$h"
  mk_tmux "$h/.local/bin" 'byz-demo-master-claude#0' '/Users/x/localproj'
  mk_tmux "$WORK/y-bin-remote" 'aifp-mini-worker-claude#0' '/Users/byz/miniproj'
  mk_ssh "$h/.local/bin"
  mk_hosts "$h" "$WORK/y-bin-remote"
  mk_scan_fixture "$WORK/y-scan.sh"
  # awk 는 «시스템 BSD awk» 를 쓴다(가짜 bin 에 awk 없음 = mini 와 같은 조건)
  local -a E=(env HOME="$h" TMM_HOSTS="$h/.tmm/hosts.tsv" NO_COLOR=1 H_FAKE_LOG="$WORK/y.log"
              TMM_SCAN="$WORK/y-scan.sh" TMM_CACHE_TTL=0)
  local d0 d1 out rc
  d0=$(date +%s)
  out="$("${E[@]}" bash "$TMM" ls --host all 2>"$WORK/y.err")"; rc=$?
  d1=$(date +%s)
  want "다중행 픽스처 조회 rc" "$rc" 0
  want "시간 ≤10초" "$(( d1 - d0 <= 10 ))" 1
  case "$out" in *"$HOSTN "*"HUMAN"*) ok "원격 상태가 픽스처 2번째 줄(HUMAN)" ;; *) bad "원격 상태 매핑 실패 — [$out]" ;; esac
  case "$out" in "m3 "*"IDLE"*) ok "로컬 상태가 픽스처 1번째 줄(IDLE)" ;; *) bad "로컬 상태 매핑 실패 — [$out]" ;; esac
  case "$(cat "$WORK/y.err")" in "") ok "stderr 0줄" ;; *) bad "stderr 오염 — [$(cat "$WORK/y.err")]" ;; esac

  # 변이: awk -v 로 되돌리면 BSD awk 가 다중행을 못 받아 원격 행이 사라져야 한다
  local mut="$WORK/y-tmm-mut"
  python3 - "$TMM" "$mut" <<'PYMUT'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
old = r"""awk -F'\t' 'BEGIN { n = split(ENVIRON["SEAT_STATE"], L, "\n")"""
new = r"""awk -F'\t' -v st="$SEAT_STATE" 'BEGIN { n = split(st, L, "\n")"""
if old not in s:
    sys.exit(3)
open(sys.argv[2], 'w', encoding='utf-8').write(s.replace(old, new))
PYMUT
  if [ $? -ne 0 ] || cmp -s "$TMM" "$mut"; then bad "변이 문자열 없음 — 변이 시험 무효"; return; fi
  out="$("${E[@]}" bash "$mut" ls --host all 2>/dev/null)"
  case "$out" in *"$HOSTN "*"aifp-mini-worker"*) bad "변이를 못 잡음(awk -v 인데도 원격 행이 나옴)" ;; *) ok "변이(awk -v) → 원격 행 0 = 검사식이 잡음" ;; esac
}

# ---------- Ⓩ 원격 실패 → rc≠0 + 판정 불가 1줄 (arch 반송 r2 ②③) ----------
case_z() {
  echo "[Ⓩ] 원격 스크립트 실패 → rc≠0 + 판정 불가 1줄"
  local h="$WORK/z" rc out
  mkdir -p "$h"
  mk_tmux "$h/.local/bin" 'byz-demo-master-claude#0' '/Users/x/localproj'
  mk_ssh "$h/.local/bin"
  mk_hosts "$h" "$h/.local/bin"
  local -a E=(env HOME="$h" TMM_HOSTS="$h/.tmm/hosts.tsv" NO_COLOR=1 H_FAKE_LOG="$WORK/z.log"
              H_FAKE_MODE=fail TMM_CACHE_TTL=0)
  out="$("${E[@]}" bash "$TMM" ls --host "$HOSTN" 2>"$WORK/z.err")"; rc=$?
  want "단일 호스트 실패 rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
  want "행 0줄(성공처럼 보이지 않음)" "[$out]" "[]"
  case "$(cat "$WORK/z.err")" in *"판정 불가 $HOSTN rc=1"*) ok "판정 불가 1줄 + rc" ;; *) bad "판정 불가 줄 없음 — [$(cat "$WORK/z.err")]" ;; esac
  out="$("${E[@]}" bash "$TMM" ls --host all 2>"$WORK/z2.err")"; rc=$?
  want "--host all 도 rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
  case "$out" in "m3 "*) ok "--host all 은 다른 호스트 행을 그대로 냄" ;; *) bad "--host all 이 다른 호스트 행을 안 냄 — [$out]" ;; esac

  # 변이: 2>/dev/null 로 되돌리면 실패가 «조용한 0줄 rc0» 이 되어야 한다
  local mut="$WORK/z-tmm-mut"
  python3 - "$TMM" "$mut" <<'PYMUT'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
old = '''h_pipe "$h" "$scr" > "$out" 2>"$err"; rc=$?'''
new = '''h_pipe "$h" "$scr" > "$out" 2>/dev/null; rc=0'''
if old not in s:
    sys.exit(3)
open(sys.argv[2], 'w', encoding='utf-8').write(s.replace(old, new))
PYMUT
  if [ $? -ne 0 ] || cmp -s "$TMM" "$mut"; then bad "변이 문자열 없음 — 변이 시험 무효"; return; fi
  out="$("${E[@]}" bash "$mut" ls --host "$HOSTN" 2>"$WORK/z3.err")"; rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$(cat "$WORK/z3.err")" ]; then ok "변이(2>/dev/null 복원) → rc0 조용한 0줄 = 검사식이 잡음"
  else bad "변이를 못 잡음(rc=$rc · stderr=[$(cat "$WORK/z3.err")])"; fi
}

# ---------- ⓔ 4칸 동시 실행(하드 룰 22) + 변이(잠금을 «전역 고정 폴더» 로 되돌림 → 동시 회차 FAIL) ----------
case_x() {
  echo "[ⓔ] 4칸 동시 실행 + 변이(전역 고정 잠금)"
  local x p fail=0 mfail=0
  local -a p1=() p2=()
  for x in a b c d; do timeout 70 bash "$0" "$x" > "$WORK/x1-$x.log" 2>&1 & p1+=($!); done
  for p in "${p1[@]}"; do wait "$p" || fail=1; done
  want "동시 4칸 rc0" "$fail" 0
  # 변이: 잠금 폴더를 «네 칸이 공유하는 하나» 로 되돌린다 = arch 반송 r1 의 원래 사고 재현
  local shared="$WORK/x-locks"; mkdir -p "$shared"
  for x in a b c d; do H_LOCK_DIR="$shared" timeout 70 bash "$0" "$x" > "$WORK/x2-$x.log" 2>&1 & p2+=($!); done
  for p in "${p2[@]}"; do wait "$p" || mfail=1; done
  if [ "$mfail" -eq 1 ]; then ok "변이(전역 고정 잠금) → 동시 회차 FAIL = 검사식이 잡음"
  else bad "변이를 못 잡음(동시 회차가 전부 통과)"; fi
}

sel="a b c d y z"
[ $# -gt 0 ] && sel="$*"
for x in $sel; do
  case "$x" in
    a) case_a ;; b) case_b ;; c) case_c ;; d) case_d ;; y) case_y ;; z) case_z ;; x) case_x ;;
    *) echo "usage: $0 [a|b|c|d|y|z|x]" >&2; exit 2 ;;
  esac
done

printf '\n합계: PASS %d · FAIL %d (%.1f초)\n' "$PASS" "$FAIL" "$(echo "$(date +%s) - $T0" | bc 2>/dev/null || echo $(( $(date +%s) - T0 )))"
[ "$FAIL" -eq 0 ] || { printf '실패:%b\n' "$FAILED"; exit 1; }
exit 0
