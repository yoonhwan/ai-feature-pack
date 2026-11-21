#!/usr/bin/env bash
# test_base_run_r2377.sh — r2377 · «기준판에서도 같은 시험이 FAILED 인가» 비교 = 한 명령(ft-base-run.sh) · 사본은 $TMPDIR/tmp.ftbase.* 에 살고 끝나면 지운다 + 손 스크립트의 /tmp 고정 export 는 린트가 거절
#   반례 ①~⑫ + 변이 M1~M6(사본에서만 · 변이마다 원본으로 같은 사례 1회 더) · 임시 git 리포(커밋 2 · 폴더 2) · 실 BYZ 리포·실 /tmp 사본 0 · 가짜 git(archive 멈춤) · 가짜 시험 명령(pwd·rc·git) · sleep 은 신호 대기 polling 만
#   R2377_BIN = 기준판 대조용 bin 폴더. 지정하면 변이 생략 · 그 판에는 ft-base-run.sh 가 없으므로 ②~⑦·⑨·⑩ 은 SKIP(판정 불가) · 기준판 Red = ①·⑧·⑪
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2377_BIN:-$HERE/../bin}"; BASE_MODE=0; [ -n "${R2377_BIN:-}" ] && BASE_MODE=1
fail=0; res=0; msg=""; T0=$SECONDS
ck() { if [ "$2" = 1 ]; then echo "PASS $1"; else echo "FAIL $1 :: ${3:0:400}"; fail=$((fail+1)); fi; }
sk() { echo "SKIP $1 :: $2"; }

TT="${TMPDIR:-/tmp}"; T="$(mktemp -d "${TT%/}/r2377.XXXXXX")"; T="${T%/}"; TD=""; trap 'rm -rf "$T" ${TD:+"$TD"}' EXIT
SUT="$BIN/ft-base-run.sh"; LINT_RUN="$BIN/ft-tmp-trap-lint.sh"; RUN="$SUT"

# ── 임시 리포(커밋 2 · 폴더 2) ────────────────────────────────────────────────
SRC="$T/src"; git init -q "$SRC" || { echo "FAIL 임시 리포 못 만듦"; exit 1; }
git -C "$SRC" config user.email t@t.local; git -C "$SRC" config user.name t
mkdir -p "$SRC/d1" "$SRC/d2"; printf 'A\n' > "$SRC/d1/a.txt"; printf 'B\n' > "$SRC/d2/b.txt"
git -C "$SRC" add -A; git -C "$SRC" commit -q -m A; A="$(git -C "$SRC" rev-parse HEAD)"
printf 'A2\n' > "$SRC/d1/a.txt"; git -C "$SRC" add -A; git -C "$SRC" commit -q -m B; B="$(git -C "$SRC" rev-parse HEAD)"
git -C "$SRC" show "$A:d1/a.txt" > "$T/expect-a.txt"
GIT_REAL="$(command -v git)"

# ── 시험 명령(사본 안에서 확인 — 사본은 끝나면 지워지므로 결과를 파일로 남긴다) ──
cat > "$T/probe" <<'PROBE'
#!/usr/bin/env bash
# probe <PROBE_OUT> — 사본 안에서 pwd·파일 목록·cmp·git 상태를 남긴다
set -uo pipefail
O="${PROBE_OUT:?}"; {
  echo "pwd=$PWD"
  echo "files=$(find . -type f -not -path './.git/*' | sed 's|^\./||' | sort | tr '\n' '|')"
  if [ -n "${EXPECT:-}" ]; then cmp -s d1/a.txt "$EXPECT"; echo "cmp=$?"; fi
  if [ -n "${CHECK_D2:-}" ]; then [ -e d2 ] && echo "d2=yes" || echo "d2=no"; fi
  if [ -n "${CHECK_GIT:-}" ]; then
    h="$(git rev-parse HEAD 2>/dev/null)"; echo "head_rc=$?"; echo "head=$h"
    echo "status=$(git status --porcelain 2>/dev/null | grep -c .)"
    echo "log1=$(git log --oneline -1 2>/dev/null)"
    echo "alt=$(cat .git/objects/info/alternates 2>/dev/null)"
  fi
} > "$O" 2>&1
exit "${PROBE_RC:-0}"
PROBE
cat > "$T/hold" <<'HOLD'
#!/usr/bin/env bash
# hold <표식 파일> — 신호 시험용: 표식을 남기고 계속 산다(TERM·KILL 을 받을 창)
: > "$1"; while :; do sleep 0.2; done
HOLD

# ── 가짜 git(archive 만 멈춤 · 나머지는 실 git) ───────────────────────────────
FGIT="$T/fgit"; mkdir -p "$FGIT"
cat > "$FGIT/git" <<FAKE
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = archive ] && exec sleep 30; done
exec "$GIT_REAL" "\$@"
FAKE
chmod +x "$FGIT/git" "$T/probe" "$T/hold"

# ── ft-base-run 이 부르는 러너 사본(부작용 도구는 스텁 — 실 reap·tmux 0) ──────
EBIN="$T/ebin"; mkdir -p "$EBIN"
for f in ft-test-run.sh ft-test-reentry-lint.sh; do [ -f "$BIN/$f" ] && cp -p "$BIN/$f" "$EBIN/"; done
cp -p "$HERE/stubs/kit-side-effect.sh" "$EBIN/ft-seat-quiesce.sh"
[ -f "$SUT" ] && cp -p "$SUT" "$EBIN/"

newtmp() { TD="$(mktemp -d "$T/tmpd.XXXXXX")"; }
leftovers() { find "$TD" -maxdepth 1 -mindepth 1 -name 'tmp.ftbase.*' 2>/dev/null | wc -l | tr -d ' '; }
first() { printf '%s\n' "$OUT" | head -1; }
field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1; }
# split_base <첫 줄> → BASE_OK=1 이면 BPATH·BSHA
split_base() { BPATH=""; BSHA=""; BASE_OK=0; local w p s; read -r w p s <<< "$1"; [ "$w" = BASE ] || return 0
  [ -n "${p:-}" ] && [ -n "${s:-}" ] || return 0; BPATH="$p"; BSHA="$s"; BASE_OK=1; }

# ══ ① 커밋 A · --path 없음 → 첫 줄 BASE <TMPDIR>/tmp.ftbase.* <A 10> · 시험 pwd = 그 경로 · 내용 = A 트리 ══
c1() { local o="$T/o1"; rm -f "$o"; newtmp
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" EXPECT="$T/expect-a.txt" "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e1")"; RC=$?
  RES=1; MSG="rc=$RC out=$(first) pwd=$(field pwd "$o") files=$(field files "$o") cmp=$(field cmp "$o") err=$(head -1 "$T/e1")"
  split_base "$(first)"; [ "$BASE_OK" = 1 ] || { RES=0; return; }
  [ "${BPATH%/*}" = "$TD" ] || { RES=0; return; }
  case "${BPATH##*/}" in tmp.ftbase.*) ;; *) RES=0; return;; esac
  [ "$BSHA" = "${A:0:10}" ] || { RES=0; return; }
  [ "$RC" = 0 ] || { RES=0; return; }
  [ "$(field pwd "$o")" = "$BPATH" ] || { RES=0; return; }
  [ "$(field files "$o")" = "d1/a.txt|d2/b.txt|" ] || { RES=0; return; }
  [ "$(field cmp "$o")" = 0 ] || { RES=0; return; }
  OUT="$OUT"; }

# ══ ② --path d1 → 사본에 d1 만 · d2 0 ══
c2() { local o="$T/o2"; rm -f "$o"; newtmp
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" CHECK_D2=1 "$RUN" "$A" --repo "$SRC" --path d1 -- bash "$T/probe" 2>"$T/e2")"; RC=$?
  RES=1; MSG="rc=$RC files=$(field files "$o") d2=$(field d2 "$o") err=$(head -1 "$T/e2")"
  [ "$RC" = 0 ] || { RES=0; return; }
  [ "$(field files "$o")" = "d1/a.txt|" ] || { RES=0; return; }
  [ "$(field d2 "$o")" = no ] || { RES=0; return; }; }

# ══ ③ 없는 ref → «판정 불가 — ref» 1줄 · rc 20 · 시험 0 · 바깥 TMPDIR 에 tmp.ftbase.* 0 ══
c3() { local o="$T/o3"; rm -f "$o"; newtmp
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" "$RUN" 0123456789abcdef0123456789abcdef01234567 --repo "$SRC" -- bash "$T/probe" 2>"$T/e3")"; RC=$?
  RES=1; MSG="rc=$RC out=$(printf '%s' "$OUT" | tail -1) left=$(leftovers)"
  [ "$RC" = 20 ] || { RES=0; return; }
  case "$(printf '%s' "$OUT" | tail -n 1)" in "BASE-RUN 판정 불가 — ref"*) ;; *) RES=0; return;; esac
  [ ! -e "$o" ] || { RES=0; return; }
  [ "$(leftovers)" = 0 ] || { RES=0; return; }; }

# ══ ④ 가짜 git archive 멈춤(상한 주입 2초) → «판정 불가 — archive» · rc 20 · 폴더 0 · 시험 0 ══
c4() { local o="$T/o4"; rm -f "$o"; newtmp; local t4=$SECONDS
  OUT="$(TMPDIR="$TD" PATH="$FGIT:$PATH" FT_BASE_ARCHIVE_SEC=2 PROBE_OUT="$o" "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e4")"; RC=$?
  T4=$((SECONDS - t4))
  RES=1; MSG="rc=$RC out=$(printf '%s' "$OUT" | tail -1) left=$(leftovers) 시험=$( [ -e "$o" ] && echo 있음 || echo 0) ${T4}초"
  [ "$RC" = 20 ] || { RES=0; return; }
  case "$(printf '%s' "$OUT" | tail -n 1)" in "BASE-RUN 판정 불가 — archive"*) ;; *) RES=0; return;; esac
  [ ! -e "$o" ] || { RES=0; return; }
  [ "$(leftovers)" = 0 ] || { RES=0; return; }; }

# ══ ⑤ `--` 없음 · 시험 명령 없음 → rc 2 · 쓰기 0 ══
c5() { newtmp; local a b
  OUT="$(TMPDIR="$TD" "$RUN" "$A" --repo "$SRC" bash "$T/probe" 2>&1)"; a=$?
  OUT2="$(TMPDIR="$TD" "$RUN" "$A" --repo "$SRC" -- 2>&1)"; b=$?
  RES=1; MSG="rc(--없음)=$a rc(명령없음)=$b left=$(leftovers)"
  [ "$a" = 2 ] || { RES=0; return; }
  [ "$b" = 2 ] || { RES=0; return; }
  [ "$(leftovers)" = 0 ] || { RES=0; return; }; }

# ══ ⑥ 시험 rc 0 · 3 → 명령 rc 0 · 3 ══
c6() { local o="$T/o6"; rm -f "$o"; newtmp
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" PROBE_RC=0 "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e6a")"; local r0=$?
  newtmp; OUT="$(TMPDIR="$TD" PROBE_OUT="$o" PROBE_RC=3 "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e6b")"; local r3=$?
  RES=1; MSG="rc(0)=$r0 rc(3)=$r3"
  [ "$r0" = 0 ] || { RES=0; return; }
  [ "$r3" = 3 ] || { RES=0; return; }; }

# ══ ⑦ --git → 사본에서 git rev-parse HEAD rc0 · status 0줄 · 원 리포 쓰기 0 ══
c7() { local o="$T/o7"; rm -f "$o"; newtmp; local before after bst; local SRC_P; SRC_P="$(cd -- "$SRC" && pwd -P)"
  before="$(git -C "$SRC" rev-parse HEAD)"; bst="$(git -C "$SRC" status --porcelain | grep -c .)"
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" CHECK_GIT=1 "$RUN" "$A" --repo "$SRC" --git -- bash "$T/probe" 2>"$T/e7")"; RC=$?
  after="$(git -C "$SRC" rev-parse HEAD)"
  RES=1; MSG="rc=$RC head_rc=$(field head_rc "$o") status=$(field status "$o") log1=$(field log1 "$o") alt=$(field alt "$o") SRC=$before/$after dirt=$bst"
  [ "$RC" = 0 ] || { RES=0; return; }
  [ "$(field head_rc "$o")" = 0 ] || { RES=0; return; }
  [ "$(field status "$o")" = 0 ] || { RES=0; return; }
  case "$(field log1 "$o")" in *"base ${A:0:10}"*) ;; *) RES=0; return;; esac
  [ "$(field alt "$o")" = "$SRC_P/.git/objects" ] || { RES=0; return; }
  [ "$after" = "$before" ] || { RES=0; return; }
  [ "$(git -C "$SRC" status --porcelain | grep -c .)" = 0 ] || { RES=0; return; }; }

# ══ ⑧ 시험 끝(rc 0 · 3 둘 다) → 폴더 0 (+ 기준판 대조: 같은 비교를 손 스크립트로 하면 사본이 그대로 남는다) ══
c8() { local o="$T/o8"; rm -f "$o"; newtmp; local l0 l3 r0 r3
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" PROBE_RC=0 "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e8a")"; r0=$?; l0="$(leftovers)"
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" PROBE_RC=3 "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e8b")"; r3=$?; l3="$(leftovers)"
  local HB="$TD/hand-base" hl=0
  mkdir -p "$HB" && { git -C "$SRC" archive "$A"; } | tar -x -C "$HB" 2>/dev/null && [ -d "$HB" ] && hl=1
  RES=1; MSG="rc=$r0/$r3 남은 사본=$l0/$l3 손 스크립트 꼴 남음=$hl err=$(head -1 "$T/e8a")"
  [ "$r0" = 0 ] || { RES=0; return; }
  [ "$r3" = 3 ] || { RES=0; return; }
  [ "$l0" = 0 ] || { RES=0; return; }
  [ "$l3" = 0 ] || { RES=0; return; }
  [ "$hl" = 1 ] || { RES=0; return; }
  rm -rf -- "$HB"; }

# ══ ⑨ 명령에 TERM → trap 지움 · 폴더 0 ══
c9() { newtmp; local m="$T/mark9" pid r
  rm -f "$m"; TMPDIR="$TD" "$RUN" "$A" --repo "$SRC" -- bash "$T/hold" "$m" >"$T/o9" 2>&1 & pid=$!
  for i in $(seq 50); do [ -e "$m" ] && break; sleep 0.1; done
  kill -TERM "$pid" 2>/dev/null; wait "$pid"; r=$?
  local l l2; l="$(leftovers)"; pkill -f "$T/hold " 2>/dev/null
  for i in $(seq 20); do l2="$(leftovers)"; [ "$l2" = 0 ] && break; sleep 0.1; done
  RES=1; MSG="rc=$r 남은 사본=$l/$l2 표식=$([ -e "$m" ] && echo 있음 || echo 없음)"
  [ -e "$m" ] || { RES=0; return; }
  [ "$r" != 0 ] || { RES=0; return; }
  [ "$(leftovers)" = 0 ] || { RES=0; return; }; }

# ══ ⑩ SIGKILL → 폴더 1개 남음 · 이름 tmp.ftbase.* · --gate --kind tmp 의 G1·G2 통과 ══
c10() { newtmp; local m="$T/mark10" pid p l g
  rm -f "$m"; TMPDIR="$TD" "$RUN" "$A" --repo "$SRC" -- bash "$T/hold" "$m" >"$T/o10" 2>&1 & pid=$!
  for i in $(seq 50); do [ -e "$m" ] && break; sleep 0.1; done
  kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  p="$(find "$TD" -maxdepth 1 -mindepth 1 -name 'tmp.ftbase.*' | head -1)"; l="$(leftovers)"
  pkill -f "$T/hold " 2>/dev/null
  g=""
  [ -n "$p" ] && g="$(TMPDIR="$TD" FT_RES_ROOT="$T/res" FT_SCRATCH_DIR="$TD" bash "$BIN/ft-scratch-repo.sh" --gate "$p" --kind tmp 2>&1)"
  RES=1; MSG="남은 사본=$l 경로=${p:-없음} gate=$(printf '%s' "$g" | tr '\n' ' ' | cut -c1-160)"
  [ "$l" = 1 ] || { RES=0; return; }
  case "${p##*/}" in tmp.ftbase.*) ;; *) RES=0; return;; esac
  [ -f "$m" ] || { RES=0; return; }
  case "$g" in *"G1 ok"*) ;; *) RES=0; return;; esac
  case "$g" in *"G2 ok"*) ;; *) RES=0; return;; esac
  [ -n "$p" ] && rm -rf -- "$p"; }

# ══ ⑪ 손 스크립트 `git archive … | tar -x -C /private/tmp/x-base`(trap 0) → 린트 REJECT 1줄 ══
c11() { local d="$T/lint"; mkdir -p "$d"; local G='git archive $S d' X='tar -x -C' P1='/private/tmp/x-base' P2='/tmp/y-base'
  printf '%s\n' '#!/bin/bash' 'S=HEAD' "$G | $X $P1" > "$d/bad1"
  printf '%s\n' '#!/bin/bash' 'S=HEAD' "$G | tar x -C $P2" > "$d/bad2"
  printf '%s\n' '#!/bin/bash' 'S=HEAD' "$G | $X \"\$W\"" > "$d/ok_var"
  OUT="$("$LINT_RUN" "$d/bad1" 2>&1)"; local r1=$?
  OUT2="$("$LINT_RUN" "$d/bad2" 2>&1)"; local r2=$?
  local r3; OUT3="$("$LINT_RUN" "$d/ok_var" 2>&1)"; r3=$?
  RES=1; MSG="rc1=$r1 «$(printf '%s' "$OUT" | head -1)» rc2=$r2 rc3=$r3"
  [ "$r1" = 1 ] || { RES=0; return; }
  case "$OUT" in *"REJECT "*"bad1:3: 기준판 사본 — ft-base-run.sh 를 쓴다"*) ;; *) RES=0; return;; esac
  [ "$r2" = 1 ] || { RES=0; return; }
  case "$OUT2" in *"bad2:3: 기준판 사본"*) ;; *) RES=0; return;; esac
  [ "$r3" = 0 ] || { RES=0; return; }; }

# ══ ⑫ 같은 줄 + trap · ft-base-run.sh 자신 · 기존 mktemp 규칙 시험 그대로 ══
c12() { local d="$T/lint"; mkdir -p "$d"; local G='git archive $S d' X='tar -x -C' P1='/private/tmp/x-base'
  printf '%s\n' '#!/bin/bash' 'S=HEAD' "$G | $X $P1" > "$d/good1"
  printf '%s\n' "trap 'rm -rf $P1' EXIT" >> "$d/good1"
  printf '%s\n' '#!/bin/bash' 'exec /opt/bin/ft-base-run.sh HEAD -- bash t.sh' > "$d/good2"
  local r1 r2 r3; OUT="$("$LINT_RUN" "$d/good1" 2>&1)"; r1=$?
  OUT2="$("$LINT_RUN" "$d/good2" 2>&1)"; r2=$?
  OUT3="$("$LINT_RUN" "$SUT" 2>&1)"; r3=$?   # K4: 새 규칙이 우리 도구 자신을 잡으면 안 된다(mktemp 규칙은 기존 도구들과 같은 사정)
  OUT4="$(bash "$HERE/test_tmp_trap_lint.sh" 2>&1)"; local r4=$?
  RES=1; MSG="rc=$r1/$r2/$r3 기존시험rc=$r4 «$(printf '%s' "$OUT" | head -1)» SUT=«$(printf '%s' "$OUT3" | head -1)»"
  [ "$r1" = 0 ] || { RES=0; return; }
  [ "$r2" = 0 ] || { RES=0; return; }
  case "$OUT3" in *"기준판 사본"*) RES=0; return;; esac
  [ "$r4" = 0 ] || { RES=0; return; }
  case "$OUT4" in *"ALL PASS"*) ;; *) RES=0; return;; esac; }

# ── 본 시험 ──────────────────────────────────────────────────────────────────
c1;  ck "① 커밋 A · --path 없음 → BASE 첫 줄 · pwd = 사본 · 내용 = A 트리" "$RES" "$MSG"
if [ "$BASE_MODE" = 1 ]; then
  sk "②~⑦·⑨·⑩" "기준판 모드(R2377_BIN) — 그 판에 ft-base-run.sh 가 없어 «명령 없음» 판정 불가"
else
  c2;  ck "② --path d1 → d1 만 · d2 0" "$RES" "$MSG"
  c3;  ck "③ 없는 ref → 판정 불가 — ref · rc 20 · 사본 0 · 시험 0" "$RES" "$MSG"
  c4;  ck "④ archive 멈춤(2초 상한) → 판정 불가 — archive · rc 20 · 사본 0 · 시험 0 (${T4:-?}초)" "$RES" "$MSG"
  c5;  ck "⑤ -- 없음 · 시험 명령 없음 → rc 2 · 쓰기 0" "$RES" "$MSG"
  c6;  ck "⑥ 시험 rc 0·3 → 명령 rc 0·3" "$RES" "$MSG"
  c7;  ck "⑦ --git → 사본 git HEAD rc0 · status 0줄 · 원 리포 쓰기 0" "$RES" "$MSG"
  c9;  ck "⑨ TERM → trap 이 지움 · 남은 사본 0" "$RES" "$MSG"
  c10; ck "⑩ SIGKILL → 사본 1개(tmp.ftbase.*) · --gate G1·G2 통과" "$RES" "$MSG"
fi
c8;  ck "⑧ 시험 끝(rc 0·3) → 남은 사본 0 · 손 스크립트 꼴은 남음(기준판 대조)" "$RES" "$MSG"
c11; ck "⑪ 손 스크립트 /tmp 고정 export → 린트 REJECT (기준판 PASS)" "$RES" "$MSG"
c12; ck "⑫ trap 있음 · ft-base-run.sh 부름 → 린트 PASS · 기존 mktemp 시험 그대로" "$RES" "$MSG"
T_CELLS=$((SECONDS - T0))

# ── 변이 M1~M6 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더) ─────────────────
if [ "$BASE_MODE" = 1 ]; then
  echo "SKIP 변이 M1~M6 :: 기준판 모드(R2377_BIN) — ft-base-run.sh 없음"
else
  MUTD="$T/mut"; mkdir -p "$MUTD"; cp -p "$EBIN"/* "$MUTD/" 2>/dev/null; cp -p "$SUT" "$MUTD/ft-base-run.sh"; cp -p "$BIN/ft-tmp-trap-lint.sh" "$MUTD/"
  mut() { # mut <이름> <옛 줄=>새 줄> — 사본만 고친다(원본 무변경)
    local ok=1; cp -p "$SUT" "$MUTD/ft-base-run.sh"
    python3 - "$MUTD/ft-base-run.sh" "$2" <<'PY' || ok=0
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
old, new = (x.strip() for x in expr.split("=>", 1))
if old not in s:
    sys.exit(f"변이 대상 없음: {old!r}")
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
    [ "$ok" = 1 ] || { echo "FAIL $1 변이 적용 실패"; fail=$((fail+1)); }
  }
  mutlint() { # M6: 새 규칙(r2377) 블록만 지운다
    cp -p "$BIN/ft-tmp-trap-lint.sh" "$MUTD/ft-tmp-trap-lint.sh"
    python3 - "$MUTD/ft-tmp-trap-lint.sh" <<'PY'
import sys
p = sys.argv[1]; L = open(p, encoding="utf-8").read().splitlines(True)
out = []; inside = False
for l in L:
    if "# r2377-rule" in l: inside = True
    if not inside: out.append(l)
    if "# /r2377-rule" in l: inside = False
open(p, "w", encoding="utf-8").write("".join(out))
PY
  }
  ex() { # ex <변이 이름> <사례 함수> <설명>
    local name="$1" fn="$2" desc="$3"
    RUN="$MUTD/ft-base-run.sh"; LINT_RUN="$MUTD/ft-tmp-trap-lint.sh"
    "$fn"; if [ "$RES" = 0 ]; then echo "PASS $name 변이 → $desc FAIL"; else echo "FAIL $name 변이인데 $desc 가 통과 :: $MSG"; fail=$((fail+1)); fi
    RUN="$SUT"; LINT_RUN="$BIN/ft-tmp-trap-lint.sh"
    "$fn"; if [ "$RES" = 1 ]; then echo "PASS $name 원본 대조 → $desc 통과"; else echo "FAIL $name 원본 대조인데 $desc 실패 :: $MSG"; fail=$((fail+1)); fi
  }
  mut M1 'if [ "$ARCH_RC" != 0 ]; then => if false; then'   # archive 실패를 무시하고 시험으로 간다
  ex M1 c4 "④"

  mut M2 'exit "$rc" => exit 0'                              # rc 를 늘 0 으로
  ex M2 c6 "⑥"

  mut M3 'reap_dir end => :'                                 # 끝 rm 지움(trap 만 남김)
  ex M3 c8 "⑧"

  mut M4 "trap 'on_signal 15' TERM => :"                     # trap 에서 TERM 뺌
  ex M4 c9 "⑨"

  mut M5 'tmp.ftbase.XXXXXX => ftbase.XXXXXX'                # 이름 머리에서 tmp. 뺌
  ex M5 c10 "⑩"

  mutlint                                                    # M6: 린트 규칙(r2377) 지움
  RUN="$SUT"
  LINT_RUN="$MUTD/ft-tmp-trap-lint.sh"; c11
  if [ "$RES" = 0 ]; then echo "PASS M6 변이(린트 규칙 지움) → ⑪ FAIL"; else echo "FAIL M6 변이인데 ⑪ 이 통과 :: $MSG"; fail=$((fail+1)); fi
  LINT_RUN="$BIN/ft-tmp-trap-lint.sh"; c11
  if [ "$RES" = 1 ]; then echo "PASS M6 원본 대조 → ⑪ 통과"; else echo "FAIL M6 원본 대조인데 ⑪ 실패 :: $MSG"; fail=$((fail+1)); fi
fi
T_ALL=$((SECONDS - T0))

echo "[시간] 사례①②~⑦⑨⑩⑫ ${T_CELLS}초 · 변이 포함 전체 ${T_ALL}초"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit "$fail"
