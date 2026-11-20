#!/usr/bin/env bash
# report_budget_r2363_bed.sh — source 전용 · r2363 시험 두 파일(사례 / 변이)이 같이 쓰는 대역.
# 임시 git 저장소·가짜 tmux·가짜 lsof·가짜 du·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 TMPDIR·실 상태 0 · 삭제는 임시 폴더 안에서만.
# 쓰는 법: `. "$HERE/lib/report_budget_r2363_bed.sh"` → `bed_begin "$SUT"` → `bed <사본 수>` → `sc --report`
#   변이는 `mut <이름> <sed 식…>` → `$MUT` (원본 옆 동료 lib 을 심링크로 붙인 자리라 lib 못 찾고 일찍 죽는 길 0)
RELIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
done_line() { [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"; exit "$fail"; }   # 두 파일 꼴 같게

bed_begin() { # <SUT>
  SUT="$1"
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"
  mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$BIN"
  git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
  SHA="$(git -C "$G" rev-parse HEAD)"
  STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; ARMED="$STATE/scratch-sweep.armed"
  printf 'live-owner\n' > "$T/sessions"
  printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" > "$BIN/tmux"
  printf '#!/bin/sh\ncat "%s/lsof.all" 2>/dev/null\nexit 0\n' "$T" > "$BIN/lsof"
  # 가짜 du — 호출마다 0.5초(고정 sleep 은 이 파일 안에서만) · 호출 수를 센다 · 크기 = 1 GiB(1048576 kb)
  printf '#!/bin/sh\nn=$(cat "%s/du.calls" 2>/dev/null || echo 0); echo $((n+1)) > "%s/du.calls"\nsleep 0.5\nprintf "1048576\\t%%s\\n" "$2"\n' "$T" "$T" > "$BIN/du"
  chmod 755 "$BIN/tmux" "$BIN/lsof" "$BIN/du"
  : > "$T/lsof.all"; printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"
  # 변이 판 자리 — 원본 옆 동료 lib(ft-heavy-slot-lib.sh 등)를 심링크로 붙인다
  MUTDIR="$T/mutbin"; mkdir -p "$MUTDIR"
  local f
  for f in "$(dirname -- "$SUT")"/*; do [ "$(basename -- "$f")" = "$(basename -- "$SUT")" ] || ln -s "$f" "$MUTDIR/"; done
}

calls() { local n; n="$(cat "$T/du.calls" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) echo 0;; *) echo "$n";; esac; }   # 한 번도 안 불렸으면 «빈 파일» = 0
bed() { # <사본 수> — 등록부·사본·호출 계수·armed 초기화(모두 임시 폴더 안)
  rm -rf "$STATE" "$SCR" "$TMPD"; mkdir -p "$STATE" "$SCR" "$TMPD"
  : > "$T/du.calls"; : > "$TSV"; : > "$T/lsof.all"; printf 'p1\ncinit\nfcwd\nn/\n' > "$T/lsof.all"
  local i d
  for i in $(seq 1 "$1"); do
    d="$SCR/repo-$(printf '%08d' "$i")-111-222"
    mkdir -p "$d"
    printf '%s\tgone-%s\t%s\n' "$d" "$i" "$(( $(date +%s) - 90000 ))" >> "$TSV"
  done
}
sc() { # <인자…> — FT_SUT·BUDGET 은 호출 앞에 env 로
  OUT="$(env PATH="$BIN:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER=live-owner \
    FT_SCRATCH_JUDGE_BUDGET="${BUDGET:-20}" bash "${FT_SUT:-$SUT}" "$@" 2>&1)"; RC=$?; }
rows() { printf '%s\n' "$OUT" | awk -F'\t' 'NF>=3 && $2 ~ /\/repo-/' | wc -l | tr -d ' '; }   # 표 줄 수(크기·경로·사유 3열)
raws() { printf '%s\n' "$OUT" | awk -F'\t' '$1=="?"' | wc -l | tr -d ' '; }                     # 크기 «?» 줄 수 = 못 잰 사본
zero_rows() { printf '%s\n' "$OUT" | awk -F'\t' '$1=="0.00"' | wc -l | tr -d ' '; }
sumline() { printf '%s\n' "$OUT" | grep -m1 '^주인 없는 임시 사본'; }
mut() { # <이름> <sed 식…> → $MUTDIR/ft-scratch-repo.sh (원본과 다르고 문법이 살아야 한다)
  local n="$1" x s=(); shift
  for x in "$@"; do [ "$x" = -e ] || s+=(-e "$x"); done   # BSD sed 는 스크립트 뒤의 -e 를 옵션으로 안 본다
  sed "${s[@]}" "$SUT" > "$MUTDIR/$(basename -- "$SUT")"
  MUT="$MUTDIR/$(basename -- "$SUT")"
  cmp -s "$SUT" "$MUT" && { bad "변이 $n 주입 실패(바뀐 줄 없음)"; return 1; }
  bash -n "$MUT" 2>/dev/null || { bad "변이 $n 문법 깨짐(가짜 변이)"; return 1; }
  return 0
}
want() { [ -z "${FT_TEST_ONLY:-}" ] && return 0; printf '%s\n' "$FT_TEST_ONLY" | tr ',' '\n' | grep -qx "$1"; }
