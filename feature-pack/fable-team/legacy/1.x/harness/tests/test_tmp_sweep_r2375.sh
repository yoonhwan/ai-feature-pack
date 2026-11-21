#!/usr/bin/env bash
# test_tmp_sweep_r2375.sh — ft-tmp-sweep.sh r2375: K1 목록 = «내 소유 · 48시간 지난 폴더» 만 · K2 cursor 이어가기(항목이 사라져도 «다음 이름»부터).
#   반례 ①~⑨ + 변이 M1~M6(사본에서만 · 원본 대조) + bin·kit cmp.
#   기준판(고치기 전) 대조 = `R2375_SUT=<기준판 경로> bash 이 파일` → ①·⑤·⑦·⑧ 만 FAIL 이어야 한다.
#   입력 = 임시 폴더(FT_TMP_SWEEP_BASE) · 임시 git 리포·worktree·clone · touch -t · lsof 스텁(FT_LSOF_BIN) · git 스텁(FT_GIT_BIN · fifo) · 가짜 mbox.
#   실 /private/tmp 쓰기 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HB="$(cd -- "$HERE/.." && pwd)"
ORIG="$HB/bin/ft-tmp-sweep.sh"; KIT="$HB/kit/fable-team/bin/ft-tmp-sweep.sh"
SUT="${R2375_SUT:-$ORIG}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
LANG0="${LANG:-}"; LC0="${LC_ALL:-}"   # ⑦ 이 로캘을 바꿔 돌리므로 뒤에서 되돌린다

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$GIT_CONFIG_GLOBAL"
REALGIT="$(command -v git)"
O="$T/o.git"; M="$T/main"
git init -q --bare "$O"; git clone -q "$O" "$M" 2>/dev/null; echo a > "$M/a"; git -C "$M" add a; git -C "$M" commit -qm a; git -C "$M" push -q origin main 2>/dev/null
MLOG="$T/mbox.log"; printf '#!/bin/sh\necho "$2|$4" >> "%s"\n' "$MLOG" > "$T/mbox.sh"
CWDP="$T/cwdpath"; printf '#!/bin/sh\necho p1\nprintf "n%%s\\n" "$(cat %s)"\n' "$CWDP" > "$T/lsof"; chmod 755 "$T/lsof"
mkfifo "$T/fifo"
printf '#!/bin/bash\necho "$*" >> "%s"\nfor a in "$@"; do case "$a" in *%s*) read -r _ < "%s";; esac; done\nexec "%s" "$@"\n' "$T/git.calls" "\${HANG_PAT:-/nohang/}" "$T/fifo" "$REALGIT" > "$T/git"
chmod 755 "$T/git"

B=""; R=""
fresh() { # fresh [armed] — 새 BASE·데이터 루트
  B="$T/b$RANDOM$RANDOM"; R="$T/r$RANDOM$RANDOM"; mkdir -p "$B" "$R/.fable-team/state"; : > "$MLOG"; echo /nonexistent > "$CWDP"
  [ "${1:-}" != armed ] || : > "$R/.fable-team/state/tmp-sweep.armed"
}
old() { touch -t 202001010000 "$@"; }
wt() { git -C "$M" worktree add -q --detach "$1" origin/main 2>/dev/null; }
commit() { echo "$2" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2"; }
run() { # run [env…] — 출력 OUT · rc RC
  OUT="$(perl -e 'alarm 20; exec @ARGV' env FT_RES_ROOT="$R" FT_TMP_SWEEP_BASE="$B" FT_LSOF_BIN="${LSOF:-$T/lsof}" FT_MBOX_SH="$T/mbox.sh" FT_TMP_SWEEP_TO=planner#1 "$@" bash "$SUT" 2>&1)"; RC=$?
}
endl() { grep '^tmp-sweep ' <<<"$OUT" | tail -1; }
CUR() { echo "$R/.fable-team/state/tmp-sweep.cursor"; }
ARM() { echo "$R/.fable-team/state/tmp-sweep.armed"; }
SLOG() { cat "$R/.fable-team/state/tmp-sweep.log" 2>/dev/null; }
dels() { SLOG | awk -F'\t' '$2 ~ /^삭제 \// {sub(/.*\//, "", $2); printf "%s ", $2}'; }

# ① 목록 = 48시간 지난 · 내 소유 · 폴더만 — 일반 파일·심링크·젊은 폴더는 목록에 들지 않는다(K1)
c1() { fresh; local e="$T/ext1"; wt "$e"; old "$e"
  wt "$B/a-wt"; mkdir "$B/m-nogit"; wt "$B/y-wt"; echo f > "$B/f-file"; ln -s "$e" "$B/l-link"; wt "$B/.hid"
  old "$B/a-wt" "$B/m-nogit" "$B/f-file" "$B/.hid"; old -h "$B/l-link"
  run FT_TMP_SWEEP_BUDGET=0   # 예산 0 = 목록 첫 항목에서 끊김 → cursor·deferred 가 목록 꼴을 그대로 드러낸다
  local got; got="$(cat "$(CUR)" 2>/dev/null)"
  [ "$got" = .hid ] || { echo "  목록 첫 이름 [$got] (기대 .hid)"; return 1; }
  endl | grep -qE 'deferred=3( |$)' || { echo "  $(endl) (기대 deferred=3 = .hid·a-wt·m-nogit)"; return 1; }
  [ -d "$B/y-wt" ] && [ -e "$B/f-file" ] && [ -L "$B/l-link" ]; }

# ② 지난 폴더라도 안쪽에 .git 이 없으면 목록엔 들고 지움 0 · 남김 수 0
c2() { fresh armed; mkdir "$B/m-nogit"; old "$B/m-nogit"
  run FT_TMP_SWEEP_BUDGET=0; [ "$(cat "$(CUR)" 2>/dev/null)" = m-nogit ] && endl | grep -qE 'deferred=1( |$)' || { echo "  목록에 안 듦 [$(cat "$(CUR)" 2>/dev/null)]"; return 1; }
  run; [ -d "$B/m-nogit" ] && endl | grep -q 'removed=0 .*kept=0(' || { echo "  $(endl)"; return 1; }
  ! SLOG | grep -q '목록 지움 대상'; }

# ③ 지난 폴더 + 깨끗한 worktree = 무장 뒤 지운다(지움 범위 그대로)
c3() { fresh armed; wt "$B/a-wt"; old "$B/a-wt"; run
  [ ! -e "$B/a-wt" ] && endl | grep -q 'removed=1 ' && [ "$(grep -c . "$MLOG")" = 1 ]; }

# ④ '.' 로 시작하는 폴더는 목록에 든다 · 심링크는 목록에서 빠진다(가리키는 실제 폴더 손 0)
c4() { fresh armed; local e="$T/ext4"; wt "$e"; old "$e"; wt "$B/.hid-wt"; old "$B/.hid-wt"; ln -s "$e" "$B/l-link"; old -h "$B/l-link"
  run; [ ! -e "$B/.hid-wt" ] && [ -d "$e" ] && [ -L "$B/l-link" ] && endl | grep -q 'removed=1 ' || { echo "  $(endl)"; return 1; }; }

# ⑤ cursor 항목이 사라졌으면 «처음부터» 가 아니라 C 순서 «다음 이름» 부터 (K2)
mk5() { fresh armed; wt "$B/zz"; wt "$B/aA-old"; wt "$B/a-mid2"; wt "$B/a!old"; old "$B"/*; }   # 만든 순서 = C 순서의 거꾸로(M3 변이 감지용)
c5() { mk5; echo a-mid > "$(CUR)"; run FT_TMP_SWEEP_BUDGET=0
  [ "$(cat "$(CUR)" 2>/dev/null)" = a-mid2 ] && endl | grep -qE 'deferred=3( |$)' || { echo "  다음 이름 [$(cat "$(CUR)" 2>/dev/null)] $(endl)"; return 1; }; }

# ⑥ cursor 항목이 목록에 있으면 «그 항목» 부터(같은 이름 다음 이름 아님)
c6() { mk5; echo a-mid2 > "$(CUR)"; run FT_TMP_SWEEP_BUDGET=0
  [ "$(cat "$(CUR)" 2>/dev/null)" = a-mid2 ] && endl | grep -qE 'deferred=3( |$)' || { echo "  cursor 항목 [$(cat "$(CUR)" 2>/dev/null)] $(endl)"; return 1; }; }

# ⑦ «다음 이름» 은 로캘 순서가 아니라 바이트(C) 순서 — 로캘을 en_US.UTF-8 로 돌려도 같다
c7() { fresh armed; wt "$B/a-wt"; wt "$B/Ä-wt"; wt "$B/!z"; old "$B"/*; echo b > "$(CUR)"   # C 순서 = !z(0x21) · a-wt · Ä-wt(0xC3) — en_US 는 Ä-wt 를 a 계열 앞에 둔다
  run LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 FT_TMP_SWEEP_BUDGET=0
  [ "$(cat "$(CUR)" 2>/dev/null)" = "Ä-wt" ] && endl | grep -qE 'deferred=1( |$)' || { echo "  C 순서 다음 이름 [$(cat "$(CUR)" 2>/dev/null)] $(endl)"; return 1; }; }

# ⑧ 목록 끝에 닿은 실행만 무장 — cursor 가 사라진 자리에서 이어 가 끝에 닿으면 무장 · 남은 앞 항목은 다음 회차
c8() { fresh; wt "$B/a1-wt"; wt "$B/a2-wt"; mkdir "$B/z-nogit"; old "$B"/*
  echo a2 > "$(CUR)"   # 사라진 이름 → C 순서 다음 = a2-wt (앞 항목 a1-wt 는 이번 회차에 안 본다 · 멈춰 있으면 보지 않았다는 뜻)
  run FT_GIT_BIN="$T/git" HANG_PAT="$B/a1-wt" FT_TMP_SWEEP_BUDGET=10
  [ -d "$B/a2-wt" ] && [ -d "$B/a1-wt" ] && [ -f "$(ARM)" ] && [ ! -e "$(CUR)" ] \
    && grep -q "^목록 지움 대상 $B/a2-wt" <<<"$OUT" && endl | grep -qE 'deferred=0' || { echo "  $(endl) / armed=$([ -f "$(ARM)" ] && echo 1 || echo 0)"; return 1; }
  run   # 무장 뒤 다음 회차 = 앞 항목부터 지운다(멈춤 없이)
  [ ! -e "$B/a1-wt" ] && [ ! -e "$B/a2-wt" ] || { echo "  다음 회차가 앞 항목을 안 지움"; return 1; }; }

# ⑨ 다른 길 그대로 — 남김 판정(dirty)·판정문 보관·쪽지 1통·kept 칸
c9() { fresh armed; mkdir "$B/a-dirty"; wt "$B/a-dirty/w"; echo u > "$B/a-dirty/w/u"
  mkdir "$B/b-clean"; wt "$B/b-clean/w"; head -c 2048 /dev/urandom > "$B/b-clean/verdict.md"
  cp "$B/b-clean/verdict.md" "$T/verdict.orig"; old "$B"/*
  run; [ -d "$B/a-dirty" ] && [ ! -e "$B/b-clean" ] && cmp -s "$R/.fable-team/state/tmp-sweep-keep/b-clean/verdict.md" "$T/verdict.orig" \
    && endl | grep -q 'removed=1 .*kept=1(young 0 · cwd 0 · dirty 1 ' && [ "$(grep -c . "$MLOG")" = 1 ] || { echo "  $(endl)"; return 1; }; }

SUTNAME="$([ "$SUT" = "$ORIG" ] && echo '고친 판' || echo "대조 $SUT")"
echo "# 시험 대상 = $SUTNAME"
for c in "c1 ① 목록 = 48h 지난 내 소유 폴더만(파일·심링크·젊은 폴더 목록 밖) · deferred 3" \
  "c2 ② 안쪽 .git 없으면 목록엔 들고 지움 0 · 남김 0" "c3 ③ 깨끗한 worktree 지움 = removed 1 · 쪽지 1통" \
  "c4 ④ '.' 폴더는 목록 · 심링크는 목록 밖(가리키는 실제 폴더 손 0)" "c5 ⑤ cursor 사라짐 = C 순서 «다음 이름» 부터" \
  "c6 ⑥ cursor 있음 = 그 항목부터" "c7 ⑦ en_US.UTF-8 에서도 «다음 이름» = 바이트 순서" "c8 ⑧ 목록 끝에 닿은 실행만 무장 · 앞 항목은 다음 회차" \
  "c9 ⑨ dirty 남김 · 판정문 보관 · kept 칸 그대로"; do
  f="${c%% *}"; if "$f"; then ok "${c#* }"; else bad "${c#* }"; fi
done

# 변이 M1~M6 — 사본에서만 · 원본(고친 판)은 위에서 PASS
mut() { # mut <이름> <찾을 문자열> <바꿀 문자열> <사례> <설명>
  local MS="$T/mut-$1.sh"
  python3 -c 'import sys;s=open(sys.argv[1]).read();n=s.replace(sys.argv[3],sys.argv[4]);open(sys.argv[2],"w").write(n);sys.exit(0 if n!=s else 3)' "$ORIG" "$MS" "$2" "$3" || { bad "$1 변이 적용 안 됨"; return; }
  cmp -s "$MS" "$ORIG" && { bad "$1 변이 적용 안 됨"; return; }
  SUT="$MS"; if "$4" >/dev/null 2>&1; then bad "$1 $5 — 변이인데 PASS"; else ok "$1 $5 → FAIL(원본 PASS)"; fi; SUT="${R2375_SUT:-$ORIG}"
}
if [ -n "${R2375_SUT:-}" ]; then ok "변이 M1~M6 = 건너뜀(기준판 대조 실행)"; elif [ -f "$ORIG" ]; then
  mut M1 '-maxdepth 1 -type d -mmin' '-maxdepth 1 -mmin' c1 "목록의 -type d 뺌(일반 파일이 목록에) → ①"
  mut M2 '-mmin +"$AGE" -uid' '-uid' c1 "목록의 48시간 필터 뺌(젊은 폴더가 목록에) → ①"
  mut M3 '-print 2>/dev/null | LC_ALL=C sort' '-print 2>/dev/null' c5 "목록의 LC_ALL=C sort 뺌(목록이 이름 순서 아님) → ⑤"
  mut M4 'START=$((pos - 1))' 'START=0' c5 "cursor 이어가기 뺌(사라지면 처음부터) → ⑤"
  mut M5 'START=$((pos - 1))' 'START=$((pos))' c6 "cursor 위치를 한 칸 뒤로 → ⑥"
  mut M6 'LC_ALL=C sort' 'sort' c7 "sort 의 LC_ALL=C 뺌(로캘 순서) → ⑦"
fi
[ -f "$KIT" ] && cmp -s "$ORIG" "$KIT" && ok "bin·kit cmp 0" || bad "bin·kit 다름"
[ "$fail" = 0 ] && { echo "(all passed)"; exit 0; } || { echo "($fail failed)"; exit 1; }
