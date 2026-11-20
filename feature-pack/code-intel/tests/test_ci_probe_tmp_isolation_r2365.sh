#!/usr/bin/env bash
# r2365 — ci 가 probe(와 probe 가 띄우는 LSP 데몬)에게 전용 임시 폴더를 주고, 부를 때마다 그 폴더의
#   오래된 tursodb-ephemeral 파일을 상한 안에서 지운다. 사용자 TMPDIR 에 새로 쌓이는 파일이 0 이 된다.
#   대역 = 가짜 probe(받은 TMPDIR 기록 · lsp init/start 때 그 폴더에 tursodb-ephemeral 1개 = 데몬 대역)
#          + 가짜 tilth · 가짜 timeout · 가짜 mktemp(경로 기록) · tmp HOME·TMPDIR.
#   실 probe·실 데몬·실 캐시·외부 호출 0 · 실제 기다림 0.
#   실행: bash feature-pack/code-intel/tests/test_ci_probe_tmp_isolation_r2365.sh
#         CI_UNDER_TEST=<ci 사본> (다른 판) · CI_BASE_REV=<기준판 git 개정>(기본 origin/main)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
cntl() { grep -c . <<<"$1" 2>/dev/null | tr -d ' '; }   # 글자 덩이의 줄 수(빈 값 = 0)

# ── 변이·기준판 자리(mk 가 지우지 않는 곳) ─────────────────────────────
WORKROOT="$(mktemp -d "${TMPDIR:-/tmp}/ci-r2365-mut.XXXXXX")"
trap 'rm -rf "$WORKROOT" "${SB:-}"' EXIT
BASE_CI="$WORKROOT/ci.base"
root="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -n "$root" ]; then
  reldir="$(cd "$HERE/../skill/scripts" && pwd)"; reldir="${reldir#"$root"/}"
  rev="${CI_BASE_REV:-origin/main}"
  git -C "$root" show "$rev:$reldir/ci" > "$BASE_CI" 2>/dev/null || : > "$BASE_CI"
else
  : > "$BASE_CI"
fi
[ -s "$BASE_CI" ] || { echo "기준판 ci 사본을 만들지 못했다(git 부재?). CI_BASE_REV 를 확인하세요." >&2; exit 3; }

SB=""; run_rc=0
mk() { # 새 샌드박스: home/tmp · 가짜 probe·tilth·timeout·mktemp(bin) · 기록 파일
  [ -n "$SB" ] && rm -rf "$SB"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-r2365.XXXXXX")"
  mkdir -p "$SB/home" "$SB/tmp" "$SB/bin" "$SB/ws"
  : > "$SB/probe.log"; : > "$SB/mktemp.log"; : > "$SB/timeout.log"; : > "$SB/tilth.log"
  cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
echo "TMPDIR=${TMPDIR-unset} ARGS: $*" >> "$FAKE_DIR/probe.log"
made=0
case "$1" in
  --version) echo "probe 0.6.0-fake" ;;
  search)    echo "FAKE-SEARCH $2" ;;
  query)     echo "FAKE-AST" ;;
  lsp)
    shift
    case "${1:-status}" in
      status) printf 'LSP Daemon Status\n  Status: Connected\n  Uptime: %s\n' "${FAKE_UPTIME:-120s}" ;;
      call)   echo "FAKE_REFERENCES 1" ;;
      init|start|up) made=1 ;;
    esac ;;
esac
# 데몬 대역 — probe 가 띄운 데몬이 만드는 turso VDBE 임시 btree 파일(이 부름이 받은 TMPDIR 에)
[ "$made" = 1 ] && : > "${TMPDIR:-/tmp}/tursodb-ephemeral-fake.$$" 2>/dev/null
exit 0
FAKE
  printf '#!/usr/bin/env bash\necho "TILTH $*" >> "$FAKE_DIR/tilth.log"\necho "FAKE-TILTH $*"\nexit 0\n' > "$SB/tilth"
  cat > "$SB/bin/timeout" <<'FAKE'
#!/usr/bin/env bash
echo "TO $*" >> "$FAKE_DIR/timeout.log"
while [ $# -gt 0 ]; do case "$1" in -s|-k) shift 2 ;; -*) shift ;; [0-9]*) shift ;; *) break ;; esac; done
[ $# -gt 0 ] || exit 0
exec "$@"
FAKE
  cat > "$SB/bin/mktemp" <<'FAKE'
#!/usr/bin/env bash
echo "REAL mktemp $*" >> "$FAKE_DIR/mktemp.log"
FAKE
  cat >> "$SB/bin/mktemp" <<'FAKE'
exec /usr/bin/mktemp "$@"
FAKE
  : > "$SB/ws/a.py"; echo "def foo(): pass" > "$SB/ws/a.py"
  chmod +x "$SB/probe" "$SB/tilth" "$SB/bin/timeout" "$SB/bin/mktemp"
}
run_ci() { # stdout→$SB/last.out · stderr→$SB/last.err · rc→$run_rc
  ( unset CI_PROBE_TMPDIR
    export HOME="$SB/home" TMPDIR="$SB/tmp" FAKE_DIR="$SB" CI_TIMEOUT=10
    export PROBE_BIN="$SB/probe" TILTH_BIN="$SB/tilth"
    export PATH="$SB/bin:$PATH"
    [ -n "${PT_OVERRIDE+x}" ] && export CI_PROBE_TMPDIR="$PT_OVERRIDE"
    [ -n "${FAKE_UP+x}" ] && export FAKE_UPTIME="$FAKE_UP"
    ( cd "$SB/ws" && bash "${CI_RUN:-$CI}" "$@" ) ) >"$SB/last.out" 2>"$SB/last.err"
  run_rc=$?
}
ded() { echo "$SB/home/Library/Caches/probe/tmp"; }   # 기본 전용 폴더(K1)
old() { touch -t 202001010000 "$@" 2>/dev/null || :; } # 10분 훨씬 지난 mtime
bones() { find "$1" -maxdepth 1 -type f -name 'tursodb-ephemeral-*' 2>/dev/null | wc -l | tr -d ' '; }
olds()  { find "$1" -maxdepth 1 -type f -name 'tursodb-ephemeral-*' -mmin +10 2>/dev/null | wc -l | tr -d ' '; }
got_pt() { sed -n '1s/^TMPDIR=//; 1s/ ARGS:.*//p' "$SB/probe.log"; }

# ── ① 데몬 대역이 받은 TMPDIR = 전용 폴더 · 사용자 TMPDIR 에 0 ─────────
c1() {
  mk; run_ci lsp up --scope .
  chk "① 데몬 띄우는 부름이 받은 TMPDIR" "$(got_pt)" "$(ded)"
  chk "① 전용 폴더의 tursodb-ephemeral" "$(bones "$(ded)")" "1"
  chk "① 사용자 TMPDIR 의 tursodb-ephemeral" "$(bones "$SB/tmp")" "0"
}
# ── ② CI_PROBE_TMPDIR 주입 → 그 폴더 ──────────────────────────────────
c2() {
  mk; PT_OVERRIDE="$SB/tmp2" run_ci lsp up --scope .
  chk "② 주입 폴더가 받은 TMPDIR" "$(got_pt)" "$SB/tmp2"
  chk "② 주입 폴더의 tursodb-ephemeral" "$(bones "$SB/tmp2")" "1"
  chk "② 사용자 TMPDIR 의 tursodb-ephemeral" "$(bones "$SB/tmp")" "0"
}
# ── ③ mkdir 실패 → 부른 쪽 TMPDIR 그대로 · WARN 1줄 · rc 그대로 ────────
c3() {
  mk; : > "$SB/blocker"
  PT_OVERRIDE="$SB/blocker/tmp" run_ci lsp up --scope .; new_rc=$run_rc
  local warn new_tmp
  warn="$(grep -c 'WARN ci — probe 임시 폴더 못 만듦' "$SB/last.err" | tr -d ' ')"
  new_tmp="$(bones "$SB/tmp")"
  CI_RUN="$BASE_CI" PT_OVERRIDE="$SB/blocker/tmp" run_ci lsp up --scope .; base_rc=$run_rc
  chk "③ 파일이 부른 쪽 TMPDIR 에" "$new_tmp" "1"
  chk "③ stderr WARN 줄 수" "$warn" "1"
  chk "③ rc = 기준판" "$new_rc" "$base_rc"
}
# ── ④ 나이·이름·종류 구분(11분 3 / 5분 2 / 다른 이름 1 / 같은 이름 폴더 1) ─
c4() {
  mk; local d; d="$(ded)"; mkdir -p "$d"
  : > "$d/tursodb-ephemeral-old1"; : > "$d/tursodb-ephemeral-old2"; : > "$d/tursodb-ephemeral-old3"
  old "$d"/tursodb-ephemeral-old1 "$d"/tursodb-ephemeral-old2 "$d"/tursodb-ephemeral-old3
  : > "$d/tursodb-ephemeral-fresh1"; : > "$d/tursodb-ephemeral-fresh2"
  : > "$d/other-name"; old "$d/other-name"
  mkdir -p "$d/tursodb-ephemeral-adir"; old "$d/tursodb-ephemeral-adir"
  run_ci lsp up --scope .
  chk "④ 10분 지난 tursodb-ephemeral 남은 수" "$(olds "$d")" "0"
  chk "④ 5분 2 + 이번 부름 1" "$(bones "$d")" "3"
  chk "④ 다른 이름 일반 파일 그대로" "$([ -f "$d/other-name" ] && echo yes || echo no)" "yes"
  chk "④ 같은 이름 폴더 그대로" "$([ -d "$d/tursodb-ephemeral-adir" ] && echo yes || echo no)" "yes"
}
# ── ⑤ 1회 상한 500 (600 → 1회 뒤 100 · 2회 뒤 0) ─────────────────────
c5() {
  mk; local d i; d="$(ded)"; mkdir -p "$d"
  for i in $(seq 1 600); do : > "$d/tursodb-ephemeral-$i"; done
  old "$d"/tursodb-ephemeral-*
  run_ci lsp up --scope .
  chk "⑤ 1회 뒤 10분 지난 것" "$(olds "$d")" "100"
  chk "⑤ 1회 뒤 전체(이번 부름 1 포함)" "$(bones "$d")" "101"
  run_ci lsp up --scope .
  chk "⑤ 2회 뒤 10분 지난 것" "$(olds "$d")" "0"
  chk "⑤ 2회 뒤 전체(부름마다 만든 2)" "$(bones "$d")" "2"
}
# ── ⑥ 부른 쪽 TMPDIR 은 손대지 않는다 ────────────────────────────────
c6() {
  mk; local i
  for i in 1 2 3; do : > "$SB/tmp/tursodb-ephemeral-call$i"; done
  old "$SB/tmp"/tursodb-ephemeral-call*
  run_ci lsp up --scope .
  chk "⑥ 부른 쪽 TMPDIR 그대로" "$(bones "$SB/tmp")" "3"
}
# ── ⑦ ci search · ci sym 의 stdout·rc = 기준판 ───────────────────────
c7() {
  mk; local o1 r1 o2 r2
  CI_RUN="$CI" run_ci search foo .;      o1="$(cat "$SB/last.out")"; r1=$run_rc
  CI_RUN="$BASE_CI" run_ci search foo .; o2="$(cat "$SB/last.out")"; r2=$run_rc
  chk "⑦ ci search stdout" "$([ "$o1" = "$o2" ] && echo same || echo diff)" "same"
  chk "⑦ ci search rc" "$r1" "$r2"
  CI_RUN="$CI" run_ci sym foo --scope .;      o1="$(cat "$SB/last.out")"; r1=$run_rc
  CI_RUN="$BASE_CI" run_ci sym foo --scope .; o2="$(cat "$SB/last.out")"; r2=$run_rc
  chk "⑦ ci sym stdout" "$([ "$o1" = "$o2" ] && echo same || echo diff)" "same"
  chk "⑦ ci sym rc" "$r1" "$r2"
}
# ── ⑧ ci 자기 임시 파일(mktemp·uptime0 stamp)은 부른 쪽 TMPDIR ───────
c8() {
  mk; local d stamp mstray
  d="$(ded)"
  FAKE_UP=0s run_ci doctor
  stamp="$SB/tmp/ci-lsp-uptime0.$(id -u)"
  chk "⑧ uptime0 stamp 자리 = 부른 쪽 TMPDIR" "$([ -f "$stamp" ] && echo yes || echo no)" "yes"
  mstray="$(grep 'REAL mktemp' "$SB/mktemp.log" | grep -vc "$SB/tmp" | tr -d ' ')"
  chk "⑧ mktemp 경로가 부른 쪽 TMPDIR 밖" "$mstray" "0"
  chk "⑧ 부른 쪽이 아닌 ci 파일이 전용 폴더에" "$(find "$d" -maxdepth 1 -mindepth 1 -not -name 'tursodb-ephemeral-*' 2>/dev/null | wc -l | tr -d ' ')" "0"
}
# ── I1 구조 검사 — env TMPDIR 접두 없는 probe 부름 줄 0 ────────────────
structure() { # $1=ci 파일 → TMPDIR 앞 대입이 없는 «명령어가 "$PROBE" 인» 줄
  grep -nF '"$PROBE"' "$1" | grep -vF 'TMPDIR="$CI_PT"' | grep -vF -- '-n "$PROBE"'
}
c_i1() {
  chk "I1 — TMPDIR 대입 없는 probe 부름 줄" "$(cntl "$(structure "$CI")")" "0"
  chk "I1 — TMPDIR 대입 붙은 probe 부름 자리 수" "$(grep -cF 'TMPDIR="$CI_PT"' "$CI" | tr -d ' ')" "15"
}

echo "== 계약 시험 (ci = $CI) =="
echo "== ① ~ ⑧ =="
c1; c2; c3; c4; c5; c6; c7; c8; c_i1

echo "== 기준판 Red — ① 은 고치기 전 판에서 FAIL 이어야 한다 =="
solo() { # $1=사례 함수 → stdout "ok fail" (전역 n·fail 격리)
  ( n=0; fail=0; "$1" >"$WORKROOT/solo.$$.out" 2>&1; printf '%s %s' "$n" "$fail" )
}
res="$(CI_RUN="$BASE_CI" solo c1)"; rb="${res##* }"
chk "기준판 Red ① — FAIL 수 > 0" "$([ "${rb:-0}" -gt 0 ] && echo yes || echo no)" "yes"

echo "== 변이 M1~M7 (사본에서만) + 변이마다 원본으로 같은 사례 1회 더 =="
mk_mut() { # $1=이름 $2=sed 식 → $WORKROOT/$1
  sed "$2" "$CI" > "$WORKROOT/$1" 2>/dev/null && bash -n "$WORKROOT/$1" 2>/dev/null \
    && echo "$WORKROOT/$1" || { bad "변이 생성 $1"; return 1; }
}

mk_mut m1 's/TMPDIR="\$CI_PT" //g'                 >/dev/null   # M1 접두 지움
mk_mut m2 's|local d="${CI_PROBE_TMPDIR:-$HOME/Library/Caches/probe/tmp}"|local d="$HOME/Library/Caches/probe/tmp"|' >/dev/null
mk_mut m3 's/if \[ ! -d "\$d" \] && ! mkdir -p "\$d" 2>\/dev\/null; then/if false; then/' >/dev/null
mk_mut m4 's/ -mmin +10//'                              >/dev/null   # M4 나이 검사 지움
mk_mut m5 's/\[ "\$n" -ge 500 \] && break/:/'           >/dev/null   # M5 상한 지움
mk_mut m6 's|_probe_tmp_sweep "\$d"|_probe_tmp_sweep "${TMPDIR:-/tmp}"|' >/dev/null
mk_mut m7 's/^_probe_tmp_init$/_probe_tmp_init\nexport TMPDIR="$CI_PT"/' >/dev/null   # M7 머리 export
# 위 mk_mut 는 생성만 한다(변이 이름 → 파일). 아래가 실제 판정이다.
mut() { local f; f="$WORKROOT/$1"; [ -s "$f" ] || { bad "변이 파일 없음 $1"; return; }
  local mf of
  mf="$( CI_RUN="$f" solo "$2" | awk '{print $2}')"
  of="$( CI_RUN="$CI" solo "$2" | awk '{print $2}')"
  chk "$1 → $2 변이 FAIL(검출)" "$([ "${mf:-0}" -gt 0 ] && echo yes || echo no)" "yes"
  chk "$1 → $2 원본 PASS(대조)" "$of" "0"; }
mut m1 c1; mut m2 c2; mut m3 c3; mut m4 c4; mut m5 c5; mut m6 c6; mut m7 c8

echo
echo "합계: $((n - fail))/$n 통과 · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
