#!/usr/bin/env bash
# test_tmux_isolate.sh — r957 격리 도우미(lib/tmux_isolate.sh) 자체 시험.
#   ⓐ source → TMUX·TMUX_PANE 없음 · PATH 맨 앞 tmux shim · 격리 소켓이 격리 폴더 안
#   ⓑ shim 경유 진짜 tmux 로 세션을 만들어도 실 서버 목록 불변 · 격리 소켓에는 생긴다
#   ⓒ 누수 검사는 «늘면» FAIL · 그 이름을 지우면 PASS (대조 이름은 격리 폴더 아래 대역 소켓에서만)
#   ⓣ1 DA⑥ r2 반례 — TMPDIR=없는 폴더: 격리 준비 실패 → ERROR + rc2 · 본문 진입 0 · 실 서버 쓰기 0
#   ⓣ2 환경 묶음(TMUX_TMPDIR='' · TMPDIR=파일 · -L default · -S <실 소켓> · env -i 자식) → 격리 소켓뿐이거나 거절
#   ⓥ 전역 옵션 꼴(묶음·따로·붙임·..·심볼릭·-L·모르는 옵션) → 전부 거절 또는 격리 소켓뿐
#   ⓦ 변이 묶음 «-S 그대로» 도 기록 대역이 막는다(실 서버 쓰기 0)
#   ⓦ' DA⑥ r4 반례 — tmux «밖» 실행(실 소켓 값이 빈 경우)에도 격리 폴더 밖 쓰기는 막힌다(대역 소켓 목록 불변) · 변이 «값 비교 되살림»(R957_MUT_VALUECMP=1) 이 이 칸을 FAIL 로 잡는다
#   ⓒ3 기록 대역: «진짜 tmux 자리» 에 기록 wrapper 를 두고 이 시험 전체를 그 아래에서 돈다
#        → 원래 실 서버 소켓 대상 동사가 ls 뿐인지 확인(쓰기 0). 재귀 재실행 없음.
#   ⓓ tmux_isolate_end 는 격리 소켓의 세션만 지운다(실 서버·남의 세션 0 · kill-server 0)
# ★계약: 이 시험·도우미 어디에도 «실 서버 소켓» 대상 new-session·kill-session·kill-server 가 없다 — 실 서버는 ls 읽기 한 곳뿐.
set -uo pipefail
_r957_orig_tmux="${TMUX-}"        # ★도우미를 source 하기 «전» 에 잡는다
_r957_orig_pane="${TMUX_PANE-}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/r957-work.XXXXXX")"

TRUE_TMUX="$(command -v tmux)"
# ── 기록 대역: 진짜 tmux 자리에 둔다 — «쓰기 동사는 기록만 하고 넘기지 않는다»(계약 ⑥).
#    쓰기 차단 기준 = «허용 목록»: 격리 폴더(R957_ISO_ALLOW) 아래 소켓만 통과 · 나머지는 WRITE-BLOCK rc1(정리용 격리 쓰기만 통과).
#    ★실 소켓 «값 비교» 를 쓰지 않는다(DA⑥ r4 반례 R1)★ — tmux 밖 실행이면 실 소켓 값이 비어 비교가 통째로 건너뛰어 진짜 바이너리로 new-session 이 넘어갔다.
#    R957_MUT_VALUECMP=1 = 변이 «값 비교 되살림» 재현용 · R957_REC_PASSTHRU=1 = 변이 «기록 대역이 쓰기를 넘김» 재현용(대역 소켓으로 돌려 실 서버 보호).
cat > "$WORK/rec-tmux" <<'REC'
#!/usr/bin/env bash
sock="<none>"; verb=""; i=1
while [ "$i" -le "$#" ]; do
  a="${!i}"
  case "$a" in
    -S) j=$((i+1)); sock="${!j}"; i=$((i+2)); continue;;
    -S*) sock="${a#-S}"; i=$((i+1)); continue;;
    -*) i=$((i+1)); continue;;
    *) verb="$a"; break;;
  esac
done
log="${R957_REC_LOG:-/dev/null}"
real="${R957_TRUE_TMUX:-tmux}"
case "$verb" in
  ls|list-sessions|list-panes|has-session|display-message|show-options|show-option|capture-pane|show-environment|display)
    printf '%s\t%s\tREAD\n' "$sock" "$verb" >> "$log"; exec "$real" "$@";;
esac
allowed=0; allow="${R957_ISO_ALLOW:-}"
if [ -n "$allow" ] && [ -n "$sock" ]; then
  wd="$(cd -P "$(dirname -- "$sock")" 2>/dev/null && pwd -P)"; ad="$(cd -P "$allow" 2>/dev/null && pwd -P)"
  if [ -n "$wd" ] && [ -n "$ad" ]; then case "$wd/" in "$ad"/*) allowed=1;; esac; fi
fi
if [ "${R957_MUT_VALUECMP:-0}" = 1 ]; then   # 변이: r4 판 «실 소켓 값 비교» 되살림(빈 값이면 건너뛴다)
  if [ -n "${R957_REAL_SOCK:-}" ] && [ "$sock" = "${R957_REAL_SOCK}" ]; then allowed=0; else allowed=1; fi
fi
if [ "$allowed" = 1 ]; then
  printf '%s\t%s\tWRITE\n' "$sock" "$verb" >> "$log"   # 격리 폴더 아래 소켓 향 쓰기(정리·시험 픽스처)
  exec "$real" "$@"
fi
if [ "${R957_REC_PASSTHRU:-0}" = 1 ]; then
  printf '%s\t%s\tWRITE-PASS\n' "$sock" "$verb" >> "$log"; exec "$real" "$@"
fi
printf '%s\t%s\tWRITE-BLOCK\n' "$sock" "$verb" >> "$log"
echo "BLOCK r957-rec: 격리 폴더 밖 소켓 쓰기 막음($verb $sock)" >&2; exit 1
REC
chmod 755 "$WORK/rec-tmux"
REC_LOG="$WORK/verbs.log"; : > "$REC_LOG"
export R957_REAL_TMUX_OVERRIDE="$WORK/rec-tmux" R957_REC_LOG="$REC_LOG" R957_TRUE_TMUX="$TRUE_TMUX" R957_REAL_SOCK="${_r957_orig_tmux%%,*}"   # R957_REAL_SOCK = 변이 재현용 값만(차단 기준 아님)
. "$HERE/lib/tmux_isolate.sh"   # 시험 대상(준비 실패면 여기서 exit 2)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
GUARD_SEAT='byz-alpha-r957guard#0'

# ── ⓐ source 효과 ──
_a=1
[ -z "${TMUX-}" ] || _a=0
[ -z "${TMUX_PANE-}" ] || _a=0
[ -n "$TMUX_ISOLATE_DIR" ] && [ -d "$TMUX_ISOLATE_DIR" ] || _a=0
[ -n "$_ti_shim" ] && [ -x "$_ti_shim/tmux" ] || _a=0
[ "$(command -v tmux)" = "$_ti_shim/tmux" ] || _a=0
case "$_ti_iso_sock" in "$TMUX_ISOLATE_DIR"/*) : ;; *) _a=0 ;; esac
{ [ "$_a" = 1 ]; } && ok "ⓐ source → TMUX·TMUX_PANE 없음 · PATH 맨 앞 shim · 격리 소켓이 격리 폴더 안" \
  || bad "ⓐ TMUX=${TMUX-} shim=$_ti_shim sock=$_ti_iso_sock FT_TMUX_BIN=${FT_TMUX_BIN-}"

# ── ⓑ shim 경유 세션 생성 → 실 서버 불변 ──
real_before="$(tmux_isolate_real_ls | sed 's/:.*//' | sort)"
tmux new-session -d -s "$GUARD_SEAT" -x 80 -y 24 'sleep 5' </dev/null >/dev/null 2>&1
iso_now="$("$TRUE_TMUX" -S "$_ti_iso_sock" ls 2>/dev/null | sed 's/:.*//' | sort)"
real_after="$(tmux_isolate_real_ls | sed 's/:.*//' | sort)"
{ [ "$iso_now" = "$GUARD_SEAT" ]; } && ok "ⓑ shim 경유 new-session → 격리 소켓에만 생김($GUARD_SEAT)" \
  || bad "ⓑ 격리 소켓 목록=[$(echo $iso_now)]"
{ [ "$real_after" = "$real_before" ]; } && ok "ⓑ 실 서버 세션 목록 불변 — 새 세션이 실 서버에 0" \
  || bad "ⓑ 실 서버가 변했다: [$(comm -13 <(printf '%s\n' "$real_before") <(printf '%s\n' "$real_after") | tr '\n' ' ')]"

# ── ⓒ 누수 검사 «늘면 FAIL» 대조 — 대역 소켓도 격리 폴더 아래 ──
_orig_ti_sock="$_ti_sock"
FIXTURE_SOCK="$TMUX_ISOLATE_DIR/fixture-sock"
"$TRUE_TMUX" -S "$FIXTURE_SOCK" new-session -d -s "$GUARD_SEAT" -x 80 -y 24 'sleep 5' </dev/null >/dev/null 2>&1
_ti_sock="$FIXTURE_SOCK"; _ti_before=""      # «이 소켓이 실 서버였다면» 을 흉내 — 비어 있던 것으로 친다
out_c="$(tmux_isolate_leak_check 2>&1)"; rc_c=$?
{ [ "$rc_c" = 1 ] && [[ "$out_c" == *"FAIL 실 tmux 서버 세션 누수"* ]] && [[ "$out_c" == *"$GUARD_SEAT"* ]]; } \
  && ok "ⓒ 대조 소켓에 늘면 누수 검사 FAIL(rc1 · 이름 지목)" || bad "ⓒ 대조 rc=$rc_c $out_c"
"$TRUE_TMUX" -S "$FIXTURE_SOCK" kill-session -t "=$GUARD_SEAT" 2>/dev/null
out_c2="$(tmux_isolate_leak_check 2>&1)"; rc_c2=$?
{ [ "$rc_c2" = 0 ] && [[ "$out_c2" == *"PASS 누수 0"* ]]; } \
  && ok "ⓒ-2 그 이름을 지우면 누수 검사 PASS(rc0)" || bad "ⓒ-2 rc=$rc_c2 $out_c2"
_ti_sock="$_orig_ti_sock"

# ── ⓣ1 DA⑥ r2 반례 — TMPDIR=없는 폴더 → 준비 실패는 본문 진입 0 ──
T1LOG="$WORK/t1.log"; : > "$T1LOG"
t1_out="$(env R957_REC_LOG="$T1LOG" R957_TRUE_TMUX="$TRUE_TMUX" R957_REAL_TMUX_OVERRIDE="$WORK/rec-tmux" \
  TMPDIR="$WORK/no-such-dir" TMUX="$_r957_orig_tmux" TMUX_PANE="$_r957_orig_pane" \
  bash -c ". '$HERE/lib/tmux_isolate.sh'; echo 본문진입" 2>&1)"
t1_rc=$?
{ [ "$t1_rc" = 2 ] && [[ "$t1_out" == *"ERROR r957-tmux-isolate"* ]] && [[ "$t1_out" != *"본문진입"* ]]; } \
  && ok "ⓣ1 TMPDIR=없는 폴더 → ERROR + rc2 · 본문 진입 0" || bad "ⓣ1 rc=$t1_rc out=${t1_out:0:200}"
{ [ -s "$T1LOG" ] && awk -F'\t' -v s="$_ti_sock" '$1==s && $2!="ls"' "$T1LOG" | grep -q .; } \
  && bad "ⓣ1 준비 실패인데 실 서버에 쓴 동사가 있다" || ok "ⓣ1 실 서버 쓰기 0(준비 실패 경로 포함)"

# ── ⓣ2 환경 묶음 ──
iso_probe() { # <자식 코드> [env…]
  local code="$1"; shift
  env R957_REC_LOG="$WORK/t2.log" R957_TRUE_TMUX="$TRUE_TMUX" R957_REAL_TMUX_OVERRIDE="$WORK/rec-tmux" \
      TMUX="$_r957_orig_tmux" TMUX_PANE="$_r957_orig_pane" "$@" \
      bash -c ". '$HERE/lib/tmux_isolate.sh' && $code" 2>&1
}
t2_writes() { awk -F'\t' -v s="$_ti_sock" '$1==s && $2!="ls"' "$WORK/t2.log" | sort -u | tr '\n' ' '; }
NEWSEAT='tmux new-session -d -s byz-alpha-r957t2#0 -x 80 -y 24 "sleep 5" >/dev/null 2>&1; tmux ls 2>/dev/null | sed "s/:.*//"'
: > "$WORK/t2.log"
o="$(iso_probe "$NEWSEAT" TMUX_TMPDIR=)"
[ -z "$(t2_writes)" ] && [[ "$o" == *"byz-alpha-r957t2#0"* ]] \
  && ok "ⓣ2 TMUX_TMPDIR='' → 세션은 격리 소켓에만 · 실 서버 쓰기 0" || bad "ⓣ2 TMUX_TMPDIR='' o=${o:0:160} writes=[$(t2_writes)]"
: > "$WORK/t2.log"
o="$(iso_probe 'echo 본문진입' TMPDIR="$WORK/rec-tmux")"
[ -z "$(t2_writes)" ] && [[ "$o" == *"ERROR r957-tmux-isolate"* ]] && [[ "$o" != *"본문진입"* ]] \
  && ok "ⓣ2 TMPDIR=파일 경로 → 격리 실패 rc2 · 본문 0 · 실 서버 쓰기 0" || bad "ⓣ2 TMPDIR=파일 o=${o:0:160}"
: > "$WORK/t2.log"
o="$(iso_probe 'tmux -L default new-session -d -s byz-alpha-r957t3#0 "sleep 5"; echo rc=$?')"
{ [ -z "$(t2_writes)" ] && [[ "$o" == *"REJECT r957-tmux-shim"* ]] && [[ "$o" == *"rc=91"* ]]; } \
  && ok "ⓣ2 tmux -L default → shim REJECT rc91(실 서버 쓰기 0)" || bad "ⓣ2 -L o=${o:0:200} writes=[$(t2_writes)]"
: > "$WORK/t2.log"
o="$(iso_probe "tmux -S '$_ti_sock' new-session -d -s byz-alpha-r957t4#0 'sleep 5'; echo rc=\$?")"
{ [ -z "$(t2_writes)" ] && [[ "$o" == *"REJECT r957-tmux-shim"* ]] && [[ "$o" == *"rc=91"* ]]; } \
  && ok "ⓣ2 tmux -S <실 소켓> → shim REJECT rc91(실 서버 쓰기 0)" || bad "ⓣ2 -S o=${o:0:200} writes=[$(t2_writes)]"
: > "$WORK/t2.log"
o="$(env -i PATH="$PATH" HOME="$HOME" R957_REC_LOG="$WORK/t2.log" R957_TRUE_TMUX="$TRUE_TMUX" \
  bash -c ". '$HERE/lib/tmux_isolate.sh' && tmux new-session -d -s byz-alpha-r957t5#0 -x 80 -y 24 'sleep 5' >/dev/null 2>&1 && tmux ls 2>/dev/null | sed 's/:.*//'" 2>&1)"
{ [ -z "$(t2_writes)" ] && [[ "$o" == *"byz-alpha-r957t5#0"* ]]; } \
  && ok "ⓣ2 env -i 자식(PATH 만 · spawn 꼴) → 세션은 격리 소켓에만 · 실 서버 쓰기 0" \
  || bad "ⓣ2 env -i o=${o:0:160} writes=[$(t2_writes)]"

# ── ⓥ 전역 옵션 꼴(DA⑥ r3 반례 1·2 + 묶음) — 전부 거절되거나 격리 소켓뿐 · 실 서버 쓰기 0 ──
iso_child() { # <쉘 코드> — 도우미를 source 한 자식에서 tmux 호출 꼴을 그대로 준다
  env R957_REC_LOG="$WORK/v.log" R957_TRUE_TMUX="$TRUE_TMUX" R957_REAL_TMUX_OVERRIDE="$WORK/rec-tmux" \
      R957_REAL_SOCK="$_ti_sock" TMUX="$_r957_orig_tmux" TMUX_PANE="$_r957_orig_pane" \
      bash -c ". '$HERE/lib/tmux_isolate.sh' && $1" 2>&1
}
v_blocked() { awk -F'\t' '$3=="WRITE-BLOCK" || $3=="WRITE-PASS"' "$WORK/v.log" | grep -c . ; }
v_pass()    { awk -F'\t' '$3=="WRITE-PASS"' "$WORK/v.log" | grep -c . ; }
REALSOCK="$_ti_sock"
[ -n "$REALSOCK" ] || REALSOCK="/tmp/r957-nosock"
SYMDIR="$TMUX_ISOLATE_DIR/sym"; mkdir -p "$SYMDIR"; ln -sf "$REALSOCK" "$SYMDIR/link" 2>/dev/null
_v_cases=0
v_case() { # <설명> <명령 꼴>
  local name="$1" code="$2" out rc
  _v_cases=$((_v_cases+1)); : > "$WORK/v.log"
  out="$(iso_child "$code"; echo "rc=$?")"
  local crc; crc="$(printf '%s' "$out" | grep -o 'rc=[0-9]*' | head -1)"
  if [ "$(v_pass)" = 0 ] && [ "$(v_blocked)" = 0 ]; then
    ok "ⓥ $name → 실 서버 쓰기 0 · ${crc:-rc=?}"
  else
    bad "ⓥ $name — 실서버 쓰기 통과 $(v_pass) · 막힘 $(v_blocked) · ${out:0:120}"
  fi
}
v_case "묶음 -uS<실 소켓>"           "tmux -uS'$REALSOCK' new-session -d -s byz-alpha-r957v1#0 'sleep 3'; echo rc=\$?"
v_case "따로 -u -S <실 소켓>"        "tmux -u -S '$REALSOCK' new-session -d -s byz-alpha-r957v2#0 'sleep 3'; echo rc=\$?"
v_case "붙임 -S<실 소켓>"            "tmux -S'$REALSOCK' new-session -d -s byz-alpha-r957v3#0 'sleep 3'; echo rc=\$?"
v_case "-S .. 상위 경로"             "tmux -S '$TMUX_ISOLATE_DIR/../../../../../../../../private/tmp/tmux-501/default' new-session -d -s byz-alpha-r957v4#0 'sleep 3'; echo rc=\$?"
v_case "격리 폴더 안 심볼릭 링크→실 소켓" "tmux -S '$SYMDIR/link' new-session -d -s byz-alpha-r957v5#0 'sleep 3'; echo rc=\$?"
v_case "-L default"                  "tmux -L default new-session -d -s byz-alpha-r957v6#0 'sleep 3'; echo rc=\$?"
v_case "모르는 전역 옵션 -x"          "tmux -x new-session -d -s byz-alpha-r957v7#0 'sleep 3'; echo rc=\$?"
{ [ "$_v_cases" = 7 ]; } && ok "ⓥ 꼴 7종 전부 확인(묶음·따로·붙임·..·심볼릭·-L·모르는 옵션)" || bad "ⓥ 확인한 꼴 $_v_cases"

# ── ⓦ 변이 묶음 — «-S 를 그대로 넘기는 shim» 을 기록 대역 아래에서 돌려도 실 서버 쓰기 0 ──
MUT="$WORK/mutshim"; mkdir -p "$MUT"
printf '#!/usr/bin/env bash\n# 변이 shim: 호출자 -S 를 그대로 넘긴다(r3 판 · 기록 대역을 지나게 한다)\nexec "${R957_REAL_TMUX_OVERRIDE:-%s}" "$@"\n' "$TRUE_TMUX" > "$MUT/tmux"; chmod 755 "$MUT/tmux"
: > "$WORK/mut.log"
o="$(env R957_REC_LOG="$WORK/mut.log" R957_TRUE_TMUX="$TRUE_TMUX" R957_REAL_TMUX_OVERRIDE="$WORK/rec-tmux" \
  R957_REAL_SOCK="$_ti_sock" PATH="$MUT:$PATH" bash -c "tmux -S '$REALSOCK' new-session -d -s byz-alpha-r957w1#0 'sleep 3'; echo rc=\$?" 2>&1)"
_passn="$(awk -F'\t' '$3=="WRITE-PASS"' "$WORK/mut.log" | grep -c .)"
_blockn="$(awk -F'\t' '$3=="WRITE-BLOCK"' "$WORK/mut.log" | grep -c .)"
{ [ "$_passn" = 0 ] && [ "$_blockn" -ge 1 ]; } \
  && ok "ⓦ 변이 shim 이 실 소켓을 지정해도 기록 대역이 막는다(넘긴 쓰기 0 · 막힘 ${_blockn})" \
  || bad "ⓦ 변이 넘긴 쓰기=${_passn} 막힘=${_blockn} o=${o:0:120}"
# 변이 «기록 대역이 쓰기를 넘김» 재현(R957_REC_PASSTHRU=1 · «실 서버» 를 대역 소켓으로 돌려 실 서버는 안 건드린다)
if [ "${R957_MUT_PASSTHRU:-0}" = 1 ]; then
  : > "$WORK/mut2.log"; STAND="$(mktemp -d "${TMPDIR:-/tmp}/r957-stand.XXXXXX")"
  env R957_REC_LOG="$WORK/mut2.log" R957_TRUE_TMUX="$TRUE_TMUX" R957_REAL_TMUX_OVERRIDE="$WORK/rec-tmux" \
    R957_REAL_SOCK="$STAND/sock" R957_REC_PASSTHRU=1 PATH="$MUT:$PATH" \
    bash -c "tmux -S '$STAND/sock' new-session -d -s byz-alpha-r957w2#0 -x 80 -y 24 'sleep 3' >/dev/null 2>&1" 2>&1
  _pass2="$(awk -F'\t' '$3=="WRITE-PASS"' "$WORK/mut2.log" | grep -c .)"
  { [ "$_pass2" = 0 ]; } && ok "ⓦ 변이 «기록 대역이 쓰기를 넘김» → 넘긴 쓰기 0" \
    || bad "ⓦ 변이 «기록 대역이 쓰기를 넘김» — WRITE-PASS ${_pass2}건(검출)"
  for s in "$TRUE_TMUX" -S "$STAND/sock"; do :; done
  "$TRUE_TMUX" -S "$STAND/sock" kill-session -t "=byz-alpha-r957w2#0" 2>/dev/null
  rm -rf "$STAND"
fi

# ── ⓦ' DA⑥ r4 반례 — tmux «밖» 실행(실 소켓 값이 빈 경우)에도 격리 폴더 밖 쓰기는 막힌다 ──
#    입력 그대로: env -u TMUX -u TMUX_PANE <셸> … (/tmp 기존 서버가 있는 경우 포함)
#    기대 = 기록 대역에 new-session 0(넘긴 쓰기 0) · 막힘 ≥1 · 대역 소켓 세션 목록 불변
STAND2="$WORK/outside-stand"; mkdir -p "$STAND2"
"$TRUE_TMUX" -S "$STAND2/sock" new-session -d -s byz-alpha-r957wpkeep#0 -x 80 -y 24 'sleep 5' </dev/null >/dev/null 2>&1
wp_stand_ls() { "$TRUE_TMUX" -S "$STAND2/sock" ls 2>/dev/null | sed 's/:.*//' | sort | tr '\n' ' '; }
wp_before="$(wp_stand_ls)"
wp_run() { # tmux 밖 자식(실 소켓 값 = 빈 값)이 «격리 폴더 밖» 소켓에 new-session 하려는 꼴
  : > "$WORK/wp.log"
  env -u TMUX -u TMUX_PANE R957_REC_LOG="$WORK/wp.log" R957_TRUE_TMUX="$TRUE_TMUX" \
      R957_REAL_TMUX_OVERRIDE="$WORK/rec-tmux" R957_REAL_SOCK= \
      bash -c "MUT='$MUT'; . '$HERE/lib/tmux_isolate.sh'; \"\$MUT/tmux\" -S '$STAND2/sock' new-session -d -s byz-alpha-r957wp#0 'sleep 3'; echo rc=\$?" 2>&1
}
wp_pass()  { awk -F'\t' '$3=="WRITE-PASS"' "$WORK/wp.log" | grep -c . ; }
wp_block() { awk -F'\t' '$3=="WRITE-BLOCK"' "$WORK/wp.log" | grep -c . ; }
_wp_out="$(wp_run)"
{ [ "$(wp_pass)" = 0 ] && [ "$(wp_block)" -ge 1 ]; } \
  && ok "ⓦ' tmux 밖(실 소켓 값 빈) → 격리 폴더 밖 쓰기 막힘 $(wp_block) · 넘긴 쓰기 0" \
  || bad "ⓦ' 넘긴 쓰기=$(wp_pass) 막힘=$(wp_block) o=${_wp_out:0:160}"
[ "$(wp_stand_ls)" = "$wp_before" ] \
  && ok "ⓦ' 대역 소켓 세션 목록 불변(${wp_before})" || bad "ⓦ' 대역 소켓이 변했다: $(wp_stand_ls)"
"$TRUE_TMUX" -S "$STAND2/sock" kill-session -t "=byz-alpha-r957wpkeep#0" 2>/dev/null

# ── ⓒ3 기록 대역 결과 — 이 시험 전체에서 실 서버 소켓에 쓴 동사 0 ──
if [ -n "$_r957_orig_tmux" ]; then
  w="$(awk -F'\t' -v s="$_ti_sock" '$1==s && $3!="READ" {print $2"/"$3}' "$REC_LOG" | sort -u | tr '\n' ' ')"
  { [ -z "$w" ]; } && ok "ⓒ3 실 서버 소켓(${_ti_sock##*/}) 대상 = 읽기(ls)뿐 · 쓰기 통과 0" \
    || bad "ⓒ3 실 서버 소켓에 쓴 동사: [$w]"
  { awk -F'\t' -v s="$_ti_sock" '$1==s && $3=="READ"' "$REC_LOG" | grep -q .; } \
    && ok "ⓒ3 실 서버는 ls 로만 읽었다(기록 대역 확인)" || bad "ⓒ3 실 서버 ls 기록 없음 — 기록 대역 미작동"
else
  ok "ⓒ3 건너뜀 — TMUX 없이 돌려 실 서버 소켓 자체가 없다"
fi

# ── ⓓ 정리는 격리 소켓만 ──
real_pre_end="$(tmux_isolate_real_ls | sed 's/:.*//' | sort)"
tmux_isolate_clean_sessions
iso_after="$("$TRUE_TMUX" -S "$_ti_iso_sock" ls 2>/dev/null | sed 's/:.*//' | sort)"
{ [ -z "$iso_after" ]; } && ok "ⓓ 세션 정리 → 격리 소켓 세션 0" || bad "ⓓ 격리 잔여=[$(echo $iso_after)]"
_iso_dir_keep="$TMUX_ISOLATE_DIR"
tmux_isolate_end
{ [ ! -e "$_iso_dir_keep" ]; } && ok "ⓓ-2 end → 격리 폴더·shim 삭제(흔적 0)" || bad "ⓓ-2 폴더가 남았다: $_iso_dir_keep"
real_post_end="$(tmux_isolate_real_ls | sed 's/:.*//' | sort)"
{ [ "$real_post_end" = "$real_pre_end" ]; } && ok "ⓓ 실 서버 불변(정리 범위 = 격리 소켓만 · kill-server 0)" \
  || bad "ⓓ 정리가 실 서버를 건드렸다"
rm -rf "$WORK"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
