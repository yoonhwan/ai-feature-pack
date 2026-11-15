#!/usr/bin/env bash
# test_tmp_sweep_r2073.sh — ft-tmp-sweep.sh (r2073): /private/tmp 바로 아래 손 사본 하루 1회 정리.
#   반례 ①~⑦ + 변이 M1~M4(사본에서만 · 원본 대조) + bin·kit cmp + 실 /private/tmp 바로 아래 항목 수 앞뒤.
#   입력 = 임시 폴더(FT_TMP_SWEEP_BASE) · 임시 git 리포·worktree·clone · touch -t · lsof 스텁(FT_LSOF_BIN) · git 스텁(FT_GIT_BIN · fifo) · 가짜 mbox. 실 /private/tmp 쓰기 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HB="$(cd -- "$HERE/.." && pwd)"
ORIG="$HB/bin/ft-tmp-sweep.sh"; KIT="$HB/kit/fable-team/bin/ft-tmp-sweep.sh"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMP0=$(ls -A /private/tmp | wc -l | tr -d ' ')
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$GIT_CONFIG_GLOBAL"
REALGIT="$(command -v git)"
O="$T/o.git"; M="$T/main"
git init -q --bare "$O"; git clone -q "$O" "$M" 2>/dev/null; echo a > "$M/a"; git -C "$M" add a; git -C "$M" commit -qm a; git -C "$M" push -q origin main 2>/dev/null
MLOG="$T/mbox.log"; printf '#!/bin/sh\necho "$2|$4" >> "%s"\n' "$MLOG" > "$T/mbox.sh"
CWDP="$T/cwdpath"; printf '#!/bin/sh\necho p1\nprintf "n%%s\\n" "$(cat %s)"\n' "$CWDP" > "$T/lsof"; chmod 755 "$T/lsof"
printf '#!/bin/sh\nexit 1\n' > "$T/lsof-fail"; chmod 755 "$T/lsof-fail"
mkfifo "$T/fifo"
printf '#!/bin/bash\necho "$*" >> "%s"\nfor a in "$@"; do case "$a" in *%s*) exit 1;; *%s*|*%s*) read -r _ < "%s";; esac; done\nexec "%s" "$@"\n' "$T/git.calls" "\${FAIL_PAT:-/nofail/}" "\${HANG_PAT:-/nohang/}" "\${HANG_PAT2:-/nohang/}" "$T/fifo" "$REALGIT" > "$T/git"
mkdir "$T/fbin"; printf '#!/bin/sh\necho "$*" >> "%s"\nexec /usr/bin/find "$@"\n' "$T/find.calls" > "$T/fbin/find"; chmod 755 "$T/fbin/find"   # A6 ⑨a: find 호출 기록
chmod 755 "$T/git"
printf '#!/bin/bash\nread -r _ < "%s"\n' "$T/fifo" > "$T/mbox-hang.sh"   # r2073 R1: 멈춘 우편함(fifo 읽기)

B=""; R=""
fresh() { # fresh [armed] — 새 BASE·데이터 루트
  B="$T/b$RANDOM$RANDOM"; R="$T/r$RANDOM$RANDOM"; mkdir -p "$B" "$R/.fable-team/state"; : > "$MLOG"; echo /nonexistent > "$CWDP"
  [ "${1:-}" != armed ] || : > "$R/.fable-team/state/tmp-sweep.armed"
}
old() { touch -t 202001010000 "$@"; }
wt() { git -C "$M" worktree add -q --detach "$1" origin/main 2>/dev/null; }
cl() { git clone -q "$O" "$1" 2>/dev/null; }
commit() { echo "$2" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2"; }
run() { # run [env…] — 출력 OUT · rc RC
  OUT="$(perl -e 'alarm 20; exec @ARGV' env FT_RES_ROOT="$R" FT_TMP_SWEEP_BASE="$B" FT_LSOF_BIN="${LSOF:-$T/lsof}" FT_MBOX_SH="${MBOXS:-$T/mbox.sh}" FT_TMP_SWEEP_TO=planner#1 "$@" bash "$SUT" 2>&1)"; RC=$?
}
endl() { grep '^tmp-sweep ' <<<"$OUT" | tail -1; }

c1() { # ① 고르기 + ⑤ 첫 1회 목록만
  fresh; mkdir "$B/w2" "$B/files" "$B/sock"; wt "$B/w2/a"; wt "$B/w2/b"; cl "$B/c1"; echo x > "$B/files/x"
  python3 -c 'import socket,sys;s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1])' "$B/sock/s"; echo f > "$B/plain"; ln -s "$B/w2" "$B/link"
  wt "$B/reg"; printf '%s\towner\t0\n' "$B/reg" > "$R/.fable-team/state/scratch-repos.tsv"
  old "$B"/*; old -h "$B/link"; run
  L="$(grep '^목록 ' <<<"$OUT" | sed 's/.* //' | sort | tr '\n' ' ')"
  [ "$L" = "$B/c1 $B/w2 " ] || { echo "  목록=[$L]"; return 1; }
  ! grep -q -e files -e sock -e plain -e link -e reg "$R/.fable-team/state/tmp-sweep.log" || return 1
  for p in w2 c1 files sock plain link reg; do [ -e "$B/$p" ] || [ -L "$B/$p" ] || return 1; done; return 0
}
c5() { # ⑤ 첫 1회 = 목록만 · 표식 · 다시 실행 = 삭제
  fresh; wt "$B/w"; old "$B/w"; run
  [ -d "$B/w" ] && [ -f "$R/.fable-team/state/tmp-sweep.armed" ] && grep -q "^목록 지움 대상 $B/w" <<<"$OUT" || return 1
  run; [ ! -e "$B/w" ]
}
c2a() { fresh armed; mkdir "$B/p"; wt "$B/p/a"; wt "$B/p/b"; old "$B/p"; run
  [ ! -e "$B/p" ] && ! git -C "$M" worktree list | grep -q "$B/p" && endl | grep -q '^tmp-sweep removed=1 '; }
c2b() { fresh armed; mkdir "$B/p"; cl "$B/p/c"; old "$B/p"; run; [ ! -e "$B/p" ] && endl | grep -q 'removed=1 '; }
c2c() { fresh armed; mkdir "$B/p"; cl "$B/p/c"; wt "$B/p/w"; old "$B/p"; run; [ ! -e "$B/p" ] && endl | grep -q 'removed=1 '; }
c3() { # ③ 열 폴더 그대로 · kept 칸
  fresh armed; local i; for i in 1 2 3 4 5 6 7 8 9 10; do mkdir "$B/k$i"; done
  wt "$B/k1/w"; wt "$B/k2/w"; echo "$B/k2/w/sub" > "$CWDP"
  wt "$B/k3/w"; echo u > "$B/k3/w/u"; wt "$B/k4/w"; commit "$B/k4/w" n4
  cl "$B/k5/c"; echo u > "$B/k5/c/u"; cl "$B/k6/c"; commit "$B/k6/c" n6
  cl "$B/k7/c"; echo s >> "$B/k7/c/a"; git -C "$B/k7/c" stash -q
  cl "$B/k8/c"; git -C "$B/k8/c" checkout -q --detach; commit "$B/k8/c" n8
  git init -q "$B/k9/c"; commit "$B/k9/c" n9
  wt "$B/k10/w"; cl "$B/k10/x"; commit "$B/k10/x" n10
  old "$B"/k2 "$B"/k3 "$B"/k4 "$B"/k5 "$B"/k6 "$B"/k7 "$B"/k8 "$B"/k9 "$B"/k10; run
  for i in 1 2 3 4 5 6 7 8 9 10; do [ -d "$B/k$i" ] || { echo "  k$i 지워짐"; return 1; }; done
  endl | grep -q 'removed=0 .*kept=10(young 1 · cwd 1 · dirty 2 · unpushed 6 · 판정 불가 0)' || { echo "  $(endl)"; return 1; }
}
c4a() { fresh armed; wt "$B/w"; old "$B/w"; LSOF="$T/lsof-fail" run
  [ "$RC" = 3 ] && [ -d "$B/w" ] && grep -q '판정 불가 lsof' <<<"$OUT"; }
c4b() { fresh armed; wt "$B/hang"; wt "$B/ok"; old "$B"/*; local s=$SECONDS
  run FT_GIT_BIN="$T/git" HANG_PAT="/hang"; local e=$((SECONDS-s))
  echo "  ④ 걸린 초 $e"; [ "$e" -le 10 ] && [ -d "$B/hang" ] && [ ! -e "$B/ok" ] && endl | grep -q '판정 불가 1)'; }
c6a() { fresh armed; local i; for i in 1 2 3 4 5; do wt "$B/s$i"; done; old "$B"/*; local s=$SECONDS
  run FT_GIT_BIN="$T/git" HANG_PAT="$B" FT_TMP_SWEEP_BUDGET=3; local e=$((SECONDS-s))
  echo "  ⑥ 걸린 초 $e"; [ "$e" -le 12 ] && [ "$(grep -c '^tmp-sweep ' <<<"$OUT")" = 1 ] && endl | grep -Eq 'deferred=[1-9]'; }
c6b() { fresh armed; wt "$B/y"; run; [ "$(grep -c . "$MLOG")" = 0 ] || return 1
  fresh armed; wt "$B/z"; old "$B/z"; run; [ "$(grep -c . "$MLOG")" = 1 ] && grep -q 'removed=1' "$MLOG"; }
c7() { fresh armed; mkdir "$B/v"; wt "$B/v/w"; head -c 2048 /dev/urandom > "$B/v/verdict.md"; head -c 2097152 /dev/urandom > "$B/v/big.bin"
  cp "$B/v/verdict.md" "$T/verdict.orig"; old "$B/v"; run; local K="$R/.fable-team/state/tmp-sweep-keep/v"
  [ ! -e "$B/v" ] && cmp -s "$K/verdict.md" "$T/verdict.orig" && [ ! -e "$K/big.bin" ] && [ "$(ls -A "$K" | wc -l | tr -d ' ')" = 1 ]; }
SLOG() { cat "$R/.fable-team/state/tmp-sweep.log" 2>/dev/null; }
c8a() { # R1 쪽지: 우편함이 멈춰도 총 예산 안에서 끝 · 미전달 로그 1줄
  fresh armed; wt "$B/a"; old "$B/a"; local s=$SECONDS; MBOXS="$T/mbox-hang.sh" run FT_TMP_SWEEP_BUDGET=3; local e=$((SECONDS-s))
  echo "  R1 쪽지 걸린 초 $e"; [ "$e" -le 5 ] && [ "$RC" = 0 ] && [ ! -e "$B/a" ] && SLOG | grep -q '쪽지 미전달'; }
c8b() { # R1 prune: 예산을 다 쓴 뒤 prune 호출 0 · 로그 1줄
  fresh armed; wt "$B/a"; wt "$B/z"; old "$B"/*; local s=$SECONDS
  run FT_GIT_BIN="$T/git" HANG_PAT="$B/z" HANG_PAT2=prune FT_TMP_SWEEP_BUDGET=3; local e=$((SECONDS-s))
  echo "  R1 prune 걸린 초 $e"; [ "$e" -le 5 ] && [ ! -e "$B/a" ] && [ -d "$B/z" ] && SLOG | grep -q 'prune 생략'; }
c8c() { # R1 삭제: 판정 끝에 예산 0 이면 rm 0 · deferred
  fresh armed; wt "$B/a"; old "$B/a"; local s=$SECONDS
  run FT_GIT_BIN="$T/git" HANG_PAT=--git-common-dir FT_TMP_SWEEP_BUDGET=3; local e=$((SECONDS-s))
  echo "  R1 삭제 걸린 초 $e"; [ "$e" -le 5 ] && [ -d "$B/a" ] && endl | grep -q 'removed=0 .*deferred=1'; }
# ⑨ A6 끊김 · 이어 보기 · 쪽지 몫 — 바로 아래 7개 = 지움 꼴 a1~a5 + 리포 없는 z1 · z2
CUR() { echo "$R/.fable-team/state/tmp-sweep.cursor"; }
mk9() { fresh "${1:-armed}"; local i; for i in 1 2 3 4 5; do wt "$B/a$i"; done; mkdir "$B/z1" "$B/z2"; old "$B"/*; }
gone5() { local i; for i in 1 2 3 4 5; do [ ! -e "$B/a$i" ] || return 1; done; }
dels() { SLOG | awk -F'\t' '$2 ~ /^삭제 \// {sub(/.*\//, "", $2); printf "%s ", $2}'; }
c9a() { mk9; : > "$T/git.calls"; : > "$T/find.calls"; run FT_GIT_BIN="$T/git" PATH="$T/fbin:$PATH" FT_TMP_SWEEP_BUDGET=0
  local i; for i in 1 2 3 4 5; do [ -d "$B/a$i" ] || return 1; done
  [ ! -s "$T/git.calls" ] && [ ! -s "$T/find.calls" ] && endl | grep -q 'removed=0 .*deferred=7$' && [ "$(cat "$(CUR)" 2>/dev/null)" = a1 ] \
    && [ "$(SLOG | grep -c '예산 끝 — a1 부터 다음 실행')" = 1 ]; }
c9b() { mk9; echo a3 > "$(CUR)"; run; [ "$(dels)" = "a3 a4 a5 " ] && [ -d "$B/a1" ] && [ -d "$B/a2" ] && [ ! -e "$(CUR)" ] || { echo "  삭제=[$(dels)]"; return 1; }
  run; gone5; }
c9c() { fresh armed; local i; for i in 1 2 3 4 5; do wt "$B/s$i"; done; old "$B"/*
  run FT_GIT_BIN="$T/git" HANG_PAT="$B" FT_TMP_SWEEP_BUDGET=3; local c; c="$(cat "$(CUR)" 2>/dev/null)"
  case "$c" in s1|s2|s3|s4|s5) ;; *) echo "  cursor=[$c]"; return 1;; esac
  run; for i in 1 2 3 4 5; do [ ! -e "$B/s$i" ] || return 1; done; [ ! -e "$(CUR)" ]; }
c9d() { fresh armed; local i; for i in 1 2 3 4 5; do wt "$B/s$i"; done; old "$B"/*
  run FT_GIT_BIN="$T/git" FAIL_PAT="$B/s1" HANG_PAT="$B/s" FT_TMP_SWEEP_BUDGET=6
  [ "$(grep -c . "$MLOG")" = 1 ] && ! SLOG | grep -q '쪽지 미전달' && [ -s "$(CUR)" ]; }
c9e() { local c; for c in '' 'a/b' 'zz'; do mk9; printf '%s\n' "$c" > "$(CUR)"; run; gone5 && [ ! -e "$(CUR)" ] || { echo "  cursor [$c] 안 지움"; return 1; }
    if [ "$c" != zz ]; then [ "$(SLOG | grep -c 'cursor 읽기 실패 — 처음부터')" = 1 ] || { echo "  cursor [$c] 로그 없음"; return 1; }; fi; done; }
c9f() { mk9 plain; run FT_TMP_SWEEP_BUDGET=0; local A="$R/.fable-team/state/tmp-sweep.armed"
  [ -d "$B/a1" ] && [ ! -e "$A" ] && [ "$(cat "$(CUR)" 2>/dev/null)" = a1 ] || return 1
  run; [ -d "$B/a1" ] && [ "$(grep -c '^목록 지움 대상' <<<"$OUT")" = 5 ] && [ -f "$A" ] && [ ! -e "$(CUR)" ] || return 1
  run; gone5; }

SUT="$ORIG"; [ -f "$SUT" ] || bad "ft-tmp-sweep.sh 없음 (기준판)"
for c in "c1 ① 고르기 = worktree 2 폴더 · clone 폴더만 목록" "c2a ② 깨끗한 worktree 2 폴더 지움 · worktree list 빠짐 · removed=1" \
  "c2b ② 깨끗한 clone 폴더 지움" "c2c ② clone + worktree 같이 든 폴더 지움(R1)" "c3 ③ 열 폴더 남김 · young 1 cwd 1 dirty 2 unpushed 6" \
  "c4a ④ lsof rc1 = 전체 삭제 0 · rc 3" "c4b ④ git fifo 멈춤 = 그 폴더만 판정 불가 · 다른 폴더 지움" "c5 ⑤ 첫 1회 목록만 · 표식 · 다시 = 삭제" \
  "c6a ⑥ 총 상한 3초 · deferred · 끝 줄 1" "c6b ⑥ 쪽지 0통 / removed 1 = 1통" "c7 ⑦ 판정문 보관 verdict.md 만" \
  "c8a R1 우편함 멈춤 = 총 예산 안 · 미전달 로그" "c8b R1 예산 소진 뒤 prune 0" "c8c R1 예산 소진 뒤 삭제 0 · deferred" \
  "c9a ⑨a 총 상한 0 = 삭제 0 · git·find 0 · deferred=7 · cursor a1" "c9b ⑨b cursor a3 = a3·a4·a5 만 · 다음 = a1·a2" \
  "c9c ⑨c 실제 끊김 → cursor · 이어서 5개 지움" "c9d ⑨d 끊겨도 쪽지 1통(쪽지 몫)" "c9e ⑨e cursor 깨짐 세 꼴 = 처음부터" \
  "c9f ⑨f 끊긴 목록만 = 표식 0 · 끝까지 간 목록만 = 표식"; do
  f="${c%% *}"; if "$f"; then ok "${c#* }"; else bad "${c#* }"; fi
done

# 변이 M1~M4 — 사본에서만 · 원본은 위에서 PASS(같은 사례)
mut() { # mut <이름> <지울 줄 고정 문자열> <사례> <설명>
  local MS="$T/mut-$1.sh"; grep -vF -- "$2" "$ORIG" > "$MS"
  if cmp -s "$MS" "$ORIG"; then bad "$1 변이 적용 안 됨"; return; fi
  SUT="$MS"; if "$3" >/dev/null 2>&1; then bad "$1 $4 — 변이인데 PASS"; else ok "$1 $4 → FAIL(원본 PASS)"; fi; SUT="$ORIG"
}
muts() { # muts <이름> <찾을 고정 문자열> <바꿀 문자열> <사례> <설명> — 줄 안 치환 변이
  local MS="$T/mut-$1.sh"; python3 -c 'import sys;s=open(sys.argv[1]).read();open(sys.argv[2],"w").write(s.replace(sys.argv[3],sys.argv[4]))' "$ORIG" "$MS" "$2" "$3"
  if cmp -s "$MS" "$ORIG"; then bad "$1 변이 적용 안 됨"; return; fi
  SUT="$MS"; if "$4" >/dev/null 2>&1; then bad "$1 $5 — 변이인데 PASS"; else ok "$1 $5 → FAIL(원본 PASS)"; fi; SUT="$ORIG"
}
if [ -f "$ORIG" ]; then
  mut M1 '[ -n "$(repos_of "$d")" ] || continue' c1 "git 리포 품은 폴더만 고르기 지움 → ①"
  mut M2 'WHY="dirty $r"; return 1;' c3 "dirty 검사 지움 → ③"
  mut M3 'WHY="unpushed $r"; return 1;' c3 "unpushed 검사(worktree·clone) 지움 → ③"
  mut M4 'if [ "$ARM" = 0 ]; then listed=' c5 "첫 1회 목록만 지움 → ⑤"
  mut M5 'break   # A6 끊긴 자리' c9a "끊긴 자리에서 반복 끝내기 지움 → ⑨a"
  mut M6 '> "$CURSOR"   # A6 cursor 쓰기' c9a "cursor 쓰기 지움 → ⑨a"
  mut M7 'START=$k   # A6 cursor 부터' c9b "cursor 항목부터 시작 지움 → ⑨b"
  muts M8 'SCAN=$((BUDGET - NOTE))' 'SCAN=$BUDGET' c9d "쪽지 몫 지움(훑기 예산 = 총 상한) → ⑨d"
  muts M9 '[ -n "$CUT" ] || : > "$ARMED"' ': > "$ARMED"' c9f "끊긴 목록만에도 표식 → ⑨f"
fi
cmp -s "$ORIG" "$KIT" && ok "bin·kit cmp 0" || bad "bin·kit 다름"
TMP1=$(ls -A /private/tmp | wc -l | tr -d ' ')
[ "$TMP1" -ge "$TMP0" ] && ok "실 /private/tmp 바로 아래 항목 수 $TMP0 → $TMP1 (줄지 않음)" || bad "실 /private/tmp 항목 수 줄어듦 $TMP0 → $TMP1"
[ "$fail" = 0 ] && { echo "(all passed)"; exit 0; } || { echo "($fail failed)"; exit 1; }
