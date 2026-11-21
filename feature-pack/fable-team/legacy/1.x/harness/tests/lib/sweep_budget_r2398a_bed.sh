#!/usr/bin/env bash
# sweep_budget_r2398a_bed.sh — source 전용 · r2398a 예산 시험 두 파일(사례 / 변이)이 같이 쓰는 대역.
#   임시 git 저장소·가짜 tmux·가짜 lsof(전체 지도 1회 / 출구 게이트 재확인 / 사본별)·가짜 du(«2초»)·가짜 date(가상 시계)만 쓴다.
#   쓰는 법: `. "$HERE/lib/sweep_budget_r2398a_bed.sh"` → `bed_begin "$SUT"` → `reset` → 사본 만들기(`mtmp`·`many_tmp`·`mkreg`) → `sc --sweep`
#   가상 시계 = 틱 10 = 1초 · STEP_TICKS = date 호출마다 미는 틱(판정 예산) · GATE_TICKS = 출구 게이트 재확인마다 미는 틱(«사본 1개 N초») · DU_TICKS = du 호출마다
bed_begin() { # <SUT> — 임시 리포·사본 자리·가짜 도구·변이 자리·가상 시계를 만든다(실 상태 0)
  SUT="$1"
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"
  mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$BIN"
  git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
  SHA="$(git -C "$G" rev-parse HEAD)"
  STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; ARMED="$STATE/scratch-sweep.armed"; CURSOR="$STATE/scratch-sweep.cursor"
  REAL_DATE="$(command -v date)"

# ── 가짜 도구 ────────────────────────────────────────────────────────────────────────────────
#   tmux = $T/sessions · date +%s = 가상 시계($T/clock · 틱 10 = 1초 · 호출마다 STEP 틱) · du = 호출 기록 + 시계를 DU_TICKS 틱 민다(«du 2초»)
#   lsof = 경로 인자 있음 = 사본별 조회(rc1 «아무도 안 씀» · $T/hold.<이름> 있으면 그 줄) · -p = 대조 조회 · -a = 회차 전체 지도($T/map.fail 있으면 rc1) · 그 밖 = 출구 게이트 재확인
cat > "$BIN/tmux" <<EOF
#!/bin/sh
[ "\${1:-}" = list-sessions ] && cat "$T/sessions" 2>/dev/null
exit 0
EOF
cat > "$BIN/date" <<EOF
#!/bin/sh
case "\${1:-}" in
  +%s) n=\$(cat "$T/clock" 2>/dev/null || echo 1000000); echo \$((n / 10)); echo \$((n + \${STEP_TICKS:-0})) > "$T/clock";;
  *) exec "$REAL_DATE" "\$@";;
esac
EOF
cat > "$BIN/du" <<EOF
#!/bin/sh
n=\$(cat "$T/du.calls" 2>/dev/null || echo 0); echo \$((n+1)) > "$T/du.calls"
c=\$(cat "$T/clock" 2>/dev/null || echo 1000000); echo \$((c + \${DU_TICKS:-20})) > "$T/clock"
printf '1024\t%s\n' "\${2:-}"
EOF
cat > "$BIN/lsof" <<EOF
#!/bin/sh
path=""
for a in "\$@"; do case "\$a" in /*) path="\$a";; esac; done
if [ -n "\$path" ]; then
  b=\${path##*/}
  [ -f "$T/hold.\$b" ] && cat "$T/hold.\$b"
  exit 1
fi
case " \$* " in *" -p "*) cat "$T/lsof.all" 2>/dev/null; exit 0;; esac
case " \$* " in *" -a "*) [ -f "$T/map.fail" ] && exit 1;; esac
if [ "\${GATE_TICKS:-0}" != 0 ]; then c=\$(cat "$T/clock" 2>/dev/null || echo 1000000); echo \$((c + GATE_TICKS)) > "$T/clock"; fi
cat "$T/lsof.all" 2>/dev/null
exit 0
EOF
chmod 755 "$BIN/tmux" "$BIN/date" "$BIN/du" "$BIN/lsof"
  MUTB="$T/mutbin"   # 변이 판 자리 — 원본 옆 동료 lib symlink(밖에 두면 ft-heavy-slot-lib.sh 를 못 찾아 조용히 삭제 0)
  mkdir -p "$MUTB"; for f in "$(dirname -- "$SUT")"/*; do [ "$(basename -- "$f")" = "$(basename -- "$SUT")" ] || ln -sfn "$f" "$MUTB/"; done
}

mut() { # <이름> <sed 식…> → $MUTB/ft-scratch-repo.sh · 원본과 다르고 문법이 살아야 한다
  local n="$1" x s=(); shift
  for x in "$@"; do [ "$x" = -e ] || s+=(-e "$x"); done
  sed "${s[@]}" "$SUT" > "$MUTB/$(basename -- "$SUT")"
  cmp -s "$SUT" "$MUTB/$(basename -- "$SUT")" && { bad "$n 변이 주입 실패(바뀐 줄 없음)"; return 1; }
  bash -n "$MUTB/$(basename -- "$SUT")" 2>/dev/null || { bad "$n 변이 문법 깨짐(가짜 변이)"; return 1; }
  return 0
}
reset() {
  rm -rf "$STATE" "$SCR" "$TMPD"; mkdir -p "$STATE" "$SCR" "$TMPD"
  : > "$TSV"; : > "$ARMED"; : > "$T/du.calls"; : > "$T/calls"; : > "$T/lsof.all"; rm -f "$T/map.fail" "$T"/hold.* "$CURSOR"
  printf 'live-owner\n' > "$T/sessions"
  printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"
  printf '%s\n' "$(( ($(date +%s) + 1000) * 10 ))" > "$T/clock"   # 가상 시계(틱 10 = 1초)
  git -C "$G" worktree prune >/dev/null 2>&1
}
oldmtime() { touch -t 202001010000 "$1"; }
mtmp() { # <이름> → $TMPDIR/tmp.<이름> (240분 지난 꼴)
  local d="$TMPD/tmp.$1"; mkdir -p "$d" && oldmtime "$d"; printf '%s\n' "$d"
}
many_tmp() { # <수> [git] → $TMPDIR 에 tmp.bN·tmp.cN 폴더 <수>개(240분 지난 꼴) — 2762개도 몇 초 안(파이썬 1회 · 하위 셸 수천 번 0)
  python3 - "$TMPD" "$1" "${2:-}" <<'PYEOF'
import os, sys, time
root, n, git = sys.argv[1], int(sys.argv[2]), (len(sys.argv) > 3 and sys.argv[3] == "git")
old = time.time() - 6 * 3600
tag = "c" if git else "b"
for i in range(1, n + 1):
    d = os.path.join(root, "tmp.%s%d" % (tag, i))
    os.makedirs(d, exist_ok=True)
    if git:
        os.makedirs(os.path.join(d, ".git"), exist_ok=True)   # 출구 게이트 G5′ «git 폴더(모르는 물건)» = 싼 거절
    os.utime(d, (old, old))
PYEOF
}
mkreg() { # <번호> → 진짜 git worktree(detached · 깨끗 · 25시간 전 등록 · 주인 없음)
  local d="$SCR/repo-0123abcd-$1-1"
  git -C "$G" worktree add --detach -q "$d" "$SHA" >/dev/null 2>&1
  printf '%s\t%s\t%s\t%s\n' "$d" "gone-$1" "$(( $(date +%s) - 90000 ))" "$SCR" >> "$TSV"
  printf '%s\n' "$d"
}
sc() { OUT="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER=live-owner FT_HEAVY_SLOTS=0 \
  ${BUDGET:+FT_SCRATCH_JUDGE_BUDGET=$BUDGET} STEP_TICKS="${STEP_TICKS:-0}" GATE_TICKS="${GATE_TICKS:-0}" DU_TICKS="${DU_TICKS:-20}" \
  bash "${CASE_SUT:-$SUT}" "$@" 2>&1)"; RC=$?; }
duC() { local n; n="$(cat "$T/du.calls" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) echo 0;; *) echo "$n";; esac; }
endf() { printf '%s\n' "$OUT" | grep -m1 '^swept=' ; }                                        # 끝 줄
field() { endf | sed -n "s/.*$1=\([0-9][0-9]*\).*/\1/p" | tail -1; }                        # 끝 줄의 수 하나
roundof() { endf | sed -n 's/.*round=//p' | tail -1; }
puts() { printf '%s' "$1" | grep -qF -- "$2"; }


fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
done_line() { [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"; exit "$fail"; }
want() { [ -z "${FT_TEST_ONLY:-}" ] && return 0; printf '%s\n' "$FT_TEST_ONLY" | tr ',' '\n' | grep -qx "$1"; }
