#!/usr/bin/env bash
# r2377_cells.sh — r2377 반례 ①~⑫ 판정 칸. source 해서 쓴다(r2377_fixture.sh 가 내주는 세계를 읽는다).
#   각 칸은 RES(1 = 통과 · 0 = 실패) · MSG 를 채운다. 칸 안에서 사본을 지우고 임시 TMPDIR 을 새로 만든다(칸 사이 상태 0).
# shellcheck shell=bash

# ══ ① 커밋 A · --path 없음 → 첫 줄 BASE <TMPDIR>/tmp.ftbase.*/tree <A 10> · 시험 pwd = 그 경로 · 내용 = A 트리 ══
c1() { local o="$T/o1"; rm -f "$o"; newtmp
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" EXPECT="$T/expect-a.txt" "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e1")"; RC=$?
  RES=1; MSG="rc=$RC out=$(first) pwd=$(field pwd "$o") files=$(field files "$o") cmp=$(field cmp "$o") err=$(head -1 "$T/e1")"
  split_base "$(first)"; [ "$BASE_OK" = 1 ] || { RES=0; return; }
  case "$BPATH" in "$TD"/tmp.ftbase.*/tree) ;; *) RES=0; return;; esac
  [ "$BSHA" = "${A:0:10}" ] || { RES=0; return; }
  [ "$RC" = 0 ] || { RES=0; return; }
  [ "$(field pwd "$o")" = "$BPATH" ] || { RES=0; return; }
  [ "$(field files "$o")" = "d1/a.txt|d2/b.txt|" ] || { RES=0; return; }
  [ "$(field cmp "$o")" = 0 ] || { RES=0; return; }; }

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
  RES=1; MSG="rc=$RC out=$(printf '%s' "$OUT" | tail -1) left=$(leftovers) 시험=$([ -e "$o" ] && echo 있음 || echo 0) ${T4}초"
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
c6() { local o="$T/o6"; rm -f "$o"; newtmp; local r0 r3
  OUT="$(TMPDIR="$TD" PROBE_OUT="$o" PROBE_RC=0 "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e6a")"; r0=$?
  newtmp; OUT="$(TMPDIR="$TD" PROBE_OUT="$o" PROBE_RC=3 "$RUN" "$A" --repo "$SRC" -- bash "$T/probe" 2>"$T/e6b")"; r3=$?
  RES=1; MSG="rc(0)=$r0 rc(3)=$r3"
  [ "$r0" = 0 ] || { RES=0; return; }
  [ "$r3" = 3 ] || { RES=0; return; }; }

# ══ ⑦ --git → 사본에서 git rev-parse HEAD rc0 · status 0줄 · 원 리포 쓰기 0 ══
c7() { local o="$T/o7"; rm -f "$o"; newtmp; local before after bst SRC_P; SRC_P="$(cd -- "$SRC" && pwd -P)"
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

# ══ ⑨ 시험 = sleep 30 · 1초째 명령에 TERM → 3초 안에 폴더 0 · 명령 rc 143 ══
c9() { newtmp; local pid r9 i left=9 pol=0
  TMPDIR="$TD" "$RUN" "$A" --repo "$SRC" -- bash "$T/sleep30" >"$T/o9" 2>&1 & pid=$!
  for i in $(seq 10); do sleep 0.1; done            # 1초째
  kill -TERM "$pid" 2>/dev/null                     # 원본은 trap 이 사본을 지우고 143 · 앞쪽 실행 변이는 신호를 미루므로 아래에서 상한을 둔다
  for i in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -KILL "$pid" 2>/dev/null; wait "$pid"; r9=$?
  for i in $(seq 30); do left="$(leftovers)"; [ "$left" = 0 ] && break; pol=$((pol+1)); sleep 0.1; done   # 지움이 끝난 초 = pol × 0.1
  pkill -f "$T/sleep30" 2>/dev/null
  RES=1; MSG="rc=$r9 남은 사본=$left 지움 $((pol))×0.1초 out=$(tail -1 "$T/o9")"
  [ "$left" = 0 ] || { RES=0; return; }
  [ "$pol" -le 30 ] || { RES=0; return; }
  [ "$r9" = 143 ] || { RES=0; return; }; }

# ══ ⑩ SIGKILL(--git 없음 · 있음) → 폴더 1개 남음 · 이름 tmp.ftbase.* · 맨 위 .git 0 · --gate G1·G2·G5 통과 ══
c10() { local mode p l g st=1 i pid; MSG=""
  for mode in none git; do
    newtmp
    if [ "$mode" = git ]; then
      TMPDIR="$TD" "$RUN" "$A" --repo "$SRC" --git -- bash "$T/sleep30" >"$T/o10.$mode" 2>&1 & pid=$!
    else
      TMPDIR="$TD" "$RUN" "$A" --repo "$SRC" -- bash "$T/sleep30" >"$T/o10.$mode" 2>&1 & pid=$!
    fi
    for i in $(seq 50); do p="$(find "$TD" -maxdepth 1 -mindepth 1 -name 'tmp.ftbase.*' 2>/dev/null | head -1)"; [ -n "$p" ] && [ -d "$p/tree" ] && break; sleep 0.1; done
    kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    p="$(find "$TD" -maxdepth 1 -mindepth 1 -name 'tmp.ftbase.*' | head -1)"; l="$(leftovers)"
    for i in $(seq 10); do sleep 0.1; done   # KILL 뒤 고아(ft-test-run)가 시험을 띄우는 창 — 그 전 pkill 은 맞출 것이 없다
    for i in $(seq 30); do pkill -f "$T/sleep30" 2>/dev/null; pgrep -f "$T/sleep30" >/dev/null 2>&1 || break; sleep 0.1; done   # 고아가 cwd 를 놓을 때까지 — G4(점유) 로 G5 를 못 보는 일 0
    g=""
    for i in $(seq 5); do   # 문은 읽기 전용(GATE_DRY) — 고아가 cwd 를 놓는 순간까지 몇 번 다시 본다
      [ -n "$p" ] && g="$(TMPDIR="$TD" FT_RES_ROOT="$T/res" FT_SCRATCH_DIR="$TD" bash "$BIN/ft-scratch-repo.sh" --gate "$p" --kind tmp 2>&1)"
      case "$g" in *"G4 HELD"*) sleep 0.2;; *) break;; esac
    done
    MSG="$MSG[$mode l=$l p=${p:-없음} topgit=$([ -n "$p" ] && { [ -e "$p/.git" ] && echo 있음 || echo 0; }) gate=$(printf '%s' "$g" | tr '\n' ' ' | cut -c1-120)]"
    { [ "$l" = 1 ] && [ -n "$p" ] && [ ! -e "$p/.git" ]; } || st=0
    case "$p" in */tmp.ftbase.*) ;; *) st=0;; esac
    case "$g" in *"G1 ok"*) ;; *) st=0;; esac
    case "$g" in *"G2 ok"*) ;; *) st=0;; esac
    case "$g" in *"G5 ok"*) ;; *) st=0;; esac
    [ -n "$p" ] && rm -rf -- "$p"
  done
  RES="$st"; }

# ══ ⑪ 손 스크립트 두 꼴(trap 0) → reentry-lint BASECOPY 1줄 · rc 3 ══
c11() { local d="$T/lint"; mkdir -p "$d"; local G='git archive $S d' X='tar -x -C' P1='/private/tmp/x-base' W1='/tmp/a505/$K'
  printf '%s\n' '#!/bin/bash' 'S=HEAD' "$G | $X $P1" > "$d/lit.sh"
  printf '%s\n' '#!/bin/bash' "W=$W1" "$G \"\$2\" | $X \"\$W/\$1\"" > "$d/var.sh"
  local r1 r2; OUT="$("$LINT_RUN" "$d/lit.sh" 2>&1)"; r1=$?
  OUT2="$("$LINT_RUN" "$d/var.sh" 2>&1)"; r2=$?
  RES=1; MSG="rc=$r1/$r2 lit=«$(printf '%s' "$OUT" | grep '^BASECOPY ' | head -1)» var=«$(printf '%s' "$OUT2" | grep '^BASECOPY ' | head -1)»"
  [ "$r1" = 3 ] || { RES=0; return; }
  [ "$r2" = 3 ] || { RES=0; return; }
  case "$OUT" in *"BASECOPY $d/lit.sh:3: 기준판 사본 — ft-base-run.sh 를 쓴다"*) ;; *) RES=0; return;; esac
  case "$OUT2" in *"BASECOPY $d/var.sh:3: 기준판 사본 — ft-base-run.sh 를 쓴다"*) ;; *) RES=0; return;; esac
  [ "$(printf '%s\n' "$OUT" | grep -c "^BASECOPY $d/lit.sh:")" = 1 ] || { RES=0; return; }; }

# ══ ⑫ trap 있음 · ft-base-run.sh 부름 → BASECOPY 0 · 러너로 돌리면 «WARN BASECOPY» 뒤 시험 실행 · 기존 린트 시험 그대로 ══
c12() { local d="$T/lint"; mkdir -p "$d"; local G='git archive $S d' X='tar -x -C' P1='/private/tmp/x-base'
  printf '%s\n' '#!/bin/bash' 'S=HEAD' "$G | $X $P1" "trap 'rm -rf $P1' EXIT" > "$d/litok.sh"
  printf '%s\n' '#!/bin/bash' 'W=/tmp/a505/$K' "$G \"\$2\" | $X \"\$W/\$1\"" "trap 'rm -rf \"\$W\"' EXIT" > "$d/varok.sh"
  printf '%s\n' '#!/bin/bash' 'exec /opt/bin/ft-base-run.sh HEAD -- bash t.sh' > "$d/call.sh"
  printf '%s\n' '#!/bin/bash' 'S=HEAD' 'mk() {' "$G | $X $P1" '}' 'echo hi' > "$d/runme.sh"   # 러너 경로: 줄은 있지만 실행은 안 한다
  chmod +x "$d"/*.sh
  local r1 r2 r3 r4 r5 r6 o4
  OUT="$("$LINT_RUN" "$d/litok.sh" 2>&1)"; r1=$?
  OUT2="$("$LINT_RUN" "$d/varok.sh" 2>&1)"; r2=$?
  OUT3="$("$LINT_RUN" "$d/call.sh" 2>&1)"; r3=$?
  o4="$(TMPDIR="$TD" bash "$EBIN/ft-test-run.sh" "$d/runme.sh" 2>"$T/e12")"; r4=$?
  OUT5="$(bash "$HERE/test_test_reentry_lint.sh" 2>&1)"; r5=$?
  OUT6="$(bash "$HERE/test_test_run_reap_bg_r1234.sh" 2>&1)"; r6=$?
  RES=1; MSG="rc=$r1/$r2/$r3/$r4 기존=$r5/$r6 o4=«$(printf '%s' "$o4" | tail -1)» err=«$(grep -m1 BASECOPY "$T/e12" | cut -c1-60)»"
  [ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$r3" = 0 ] || { RES=0; return; }
  case "$OUT$OUT2$OUT3" in *BASECOPY*) RES=0; return;; esac
  [ "$r4" = 0 ] || { RES=0; return; }
  case "$o4" in *hi*) ;; *) RES=0; return;; esac
  case "$(cat "$T/e12")" in *"WARN BASECOPY "*) ;; *) RES=0; return;; esac
  case "$OUT5" in *"fail=0"*) ;; *) RES=0; return;; esac
  case "$OUT6" in *"ALL PASS"*) ;; *) RES=0; return;; esac; }
