#!/usr/bin/env bash
# test_tmp_sweep_r2375.sh — ft-tmp-sweep.sh r2375: K1 목록 = «내 소유 · 48시간 지난 폴더» 만(cap 7초 · rc≠0 = 판정 불가 목록) · K2 cursor = «이상» C 순서 이어 가기.
#   반례 ①~⑨(원고 동결) + ⑩~⑬(목록 꼴·.git 없음·지움·점 폴더/심링크) + 변이 M1~M6(사본에서만 · 원본 대조) + bin·kit cmp.
#   기준판(고치기 전) 대조 = `R2375_SUT=<기준판 경로> bash 이 파일` → ①·⑤·⑦·⑧ 만 FAIL 이어야 한다.
#   입력 = 임시 폴더(FT_TMP_SWEEP_BASE) · 임시 git 리포·worktree · touch -t · lsof 스텁 · git 스텁(fifo) · find 스텁(rc1 · 멈춤) · sort 스텁(로캘) · 가짜 mbox.
#   실 /private/tmp 쓰기 0 · sleep 0(멈춤은 스텁 안에서만 · cap 7초가 끊는다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HB="$(cd -- "$HERE/.." && pwd)"
ORIG="$HB/bin/ft-tmp-sweep.sh"; KIT="$HB/kit/fable-team/bin/ft-tmp-sweep.sh"
SUT="${R2375_SUT:-$ORIG}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$GIT_CONFIG_GLOBAL"
REALGIT="$(command -v git)"; REALSORT="$(command -v sort)"
O="$T/o.git"; M="$T/main"
git init -q --bare "$O"; git clone -q "$O" "$M" 2>/dev/null; echo a > "$M/a"; git -C "$M" add a; git -C "$M" commit -qm a; git -C "$M" push -q origin main 2>/dev/null
MLOG="$T/mbox.log"; printf '#!/bin/sh\necho "$2|$4" >> "%s"\n' "$MLOG" > "$T/mbox.sh"
CWDP="$T/cwdpath"; printf '#!/bin/sh\necho p1\nprintf "n%%s\\n" "$(cat %s)"\n' "$CWDP" > "$T/lsof"; chmod 755 "$T/lsof"
mkfifo "$T/fifo"
printf '#!/bin/bash\necho "$*" >> "%s"\nfor a in "$@"; do case "$a" in *%s*) read -r _ < "%s";; esac; done\nexec "%s" "$@"\n' "$T/git.calls" "\${HANG_PAT:-/nohang/}" "$T/fifo" "$REALGIT" > "$T/git"; chmod 755 "$T/git"
mkdir "$T/fbfail" "$T/fbhang" "$T/fblog" "$T/sbin"
printf '#!/bin/sh\nexit 1\n' > "$T/fbfail/find"
printf '#!/bin/sh\nexec perl -e "sleep 8"\n' > "$T/fbhang/find"
printf '#!/bin/sh\necho "$*" >> "%s"\nexec /usr/bin/find "$@"\n' "$T/find.calls" > "$T/fblog/find"
# ⑦ 사전 DA#51 H1: 로캘이 C 가 아니면 -f(대소문자 무시)로 정렬해 glibc 꼴을 흉내 = M6(LC_ALL=C 뺌)가 죽는다
cat > "$T/sbin/sort" <<EOS
#!/bin/sh
l="\${LC_ALL:-\${LC_COLLATE:-\${LANG:-C}}}"
case "\$l" in C|POSIX|C.*|POSIX.*) exec "$REALSORT" "\$@";; esac
exec "$REALSORT" -f "\$@"
EOS
chmod 755 "$T"/fbfail/find "$T"/fbhang/find "$T"/fblog/find "$T/sbin/sort"

B=""; R=""
fresh() { # fresh [armed] — 새 BASE·데이터 루트
  B="$T/b$RANDOM$RANDOM"; R="$T/r$RANDOM$RANDOM"; mkdir -p "$B" "$R/.fable-team/state"; : > "$MLOG"; : > "$T/git.calls"; echo /nonexistent > "$CWDP"
  [ "${1:-}" != armed ] || : > "$R/.fable-team/state/tmp-sweep.armed"
}
old() { touch -t 202001010000 "$@"; }
wt() { git -C "$M" worktree add -q --detach "$1" origin/main 2>/dev/null; }
run() { # run [env…] — 출력 OUT · rc RC
  OUT="$(perl -e 'alarm 20; exec @ARGV' env FT_RES_ROOT="$R" FT_TMP_SWEEP_BASE="$B" FT_LSOF_BIN="${LSOF:-$T/lsof}" FT_MBOX_SH="$T/mbox.sh" FT_TMP_SWEEP_TO=planner#1 "$@" bash "$SUT" 2>&1)"; RC=$?
}
endl() { grep '^tmp-sweep ' <<<"$OUT" | tail -1; }
CUR() { echo "$R/.fable-team/state/tmp-sweep.cursor"; }
ARM() { echo "$R/.fable-team/state/tmp-sweep.armed"; }
SLOG() { cat "$R/.fable-team/state/tmp-sweep.log" 2>/dev/null; }
dels() { SLOG | awk -F'\t' '$2 ~ /^삭제 \// {sub(/.*\//, "", $2); printf "%s ", $2}'; }

# ① 작은 파일 20,000개 + 48h+ 깨끗한 worktree 폴더 2개 · BUDGET=10 → 한 실행에 목록 끝(CUT 0 · deferred=0) · 2개 판정
c1() { fresh armed; wt "$B/w1"; wt "$B/w2"; old "$B/w1" "$B/w2"
  python3 -c 'import os,sys
b=sys.argv[1]
for i in range(20000): open(os.path.join(b,"f%05d"%i),"w").close()' "$B"
  run FT_TMP_SWEEP_BUDGET=10
  [ ! -e "$B/w1" ] && [ ! -e "$B/w2" ] && [ ! -e "$(CUR)" ] && endl | grep -qE 'removed=2 .*deferred=0' || { echo "  $(endl) · 삭제=[$(dels)]"; return 1; }; }

# ② 젊은 폴더(mtime 1시간 전) · 심링크 폴더 · 일반 파일 → 목록 0 · 손 0 · 판정 줄 0
c2() { fresh armed; wt "$B/young"; touch -t "$(date -v-1H +%Y%m%d%H%M)" "$B/young"
  local e="$T/ext2"; wt "$e"; old "$e"; ln -s "$e" "$B/lnk"; old -h "$B/lnk"; echo x > "$B/plain"; old "$B/plain"
  run
  [ -d "$B/young" ] && [ -d "$e" ] && [ -L "$B/lnk" ] && [ -e "$B/plain" ] && endl | grep -qE 'deferred=0' \
    && ! SLOG | grep -qE '목록 지움 대상|남김' && [ "$(grep -c . "$MLOG")" = 0 ] || { echo "  $(endl) · 로그=[$(SLOG | tail -2)]"; return 1; }; }

# ③ 가짜 find rc 1 → «판정 불가 목록» 1줄 · rc 3 · 삭제 0 · cursor 그대로 · armed 0
c3() { fresh; wt "$B/x-wt"; old "$B/x-wt"; printf 'x-old\n' > "$(CUR)"
  PATH="$T/fbfail:$PATH" run
  [ "$RC" = 3 ] && [ "$(grep -c '판정 불가 목록' <<<"$OUT")" = 1 ] && grep -q '판정 불가 목록 rc=1' <<<"$OUT" \
    && [ -d "$B/x-wt" ] && [ "$(cat "$(CUR)" 2>/dev/null)" = x-old ] && [ ! -f "$(ARM)" ] || { echo "  rc=$RC · $(endl)"; return 1; }; }

# ④ 가짜 find 8초 멈춤 → cap 7초에 끊김 · ③ 과 같은 결과 · 총 걸린 초 ≤ 12
c4() { fresh; wt "$B/x-wt"; old "$B/x-wt"; printf 'x-old\n' > "$(CUR)"; local s=$SECONDS
  PATH="$T/fbhang:$PATH" run; local e=$((SECONDS-s)); echo "  ④ find 멈춤 초 $e"
  [ "$e" -le 12 ] && [ "$RC" = 3 ] && grep -q '판정 불가 목록 rc=142' <<<"$OUT" && [ -d "$B/x-wt" ] && [ ! -f "$(ARM)" ] || { echo "  rc=$RC · $(endl)"; return 1; }; }

# ⑤ cursor 이름 사라짐: 목록 a·b·d·e · cursor = c → 첫 판정 = d
mk5() { fresh armed; local n; for n in a b d e; do wt "$B/$n"; done; old "$B"/*; }
c5() { mk5; echo c > "$(CUR)"; run
  [ "$(dels | cut -d' ' -f1)" = d ] && [ -d "$B/a" ] && [ -d "$B/b" ] && [ ! -e "$B/d" ] || { echo "  삭제=[$(dels)]"; return 1; }; }

# ⑥ cursor 이름 있음: cursor = b → 첫 판정 = b («이상» 이라 같은 이름 포함)
c6() { mk5; echo b > "$(CUR)"; run
  [ "$(dels | cut -d' ' -f1)" = b ] && [ -d "$B/a" ] && [ ! -e "$B/b" ] || { echo "  삭제=[$(dels)]"; return 1; }; }

# ⑦ C 정렬: 이름 B1 · a-1 · a.1 · a_1 + 사라진 cursor a-0 · ko_KR.UTF-8 → 판정 순서 = a-1 · a.1 · a_1 · B1 은 0
c7() { fresh armed; local n; for n in a-1 a.1 a_1 B1; do wt "$B/$n"; done; old "$B"/*; echo a-0 > "$(CUR)"
  PATH="$T/sbin:$PATH" run LC_ALL=ko_KR.UTF-8 LANG=ko_KR.UTF-8 FT_TMP_SWEEP_BUDGET=10
  [ "$(dels)" = "a-1 a.1 a_1 " ] && [ -d "$B/B1" ] || { echo "  삭제=[$(dels)] (기대 a-1 a.1 a_1 · B1 0)"; return 1; }; }

# ⑧ 무장 전 두 실행: 1차 BUDGET 작게 → cursor = x · x 폴더를 지운 뒤 2차 → x 다음부터 끝까지 · armed 생김 · 삭제 0
c8() { fresh; local n; for n in x y z; do wt "$B/$n"; done; old "$B"/*
  run FT_TMP_SWEEP_BUDGET=0   # 1차 = 예산 0 → 목록 첫 이름이 cursor 다
  local x; x="$(cat "$(CUR)" 2>/dev/null)"; [ "$x" = x ] || { echo "  1차 cursor=[$x] (기대 x)"; return 1; }
  rm -rf "${B:?}/x"                            # 이어 가기 표식 항목이 사라졌다
  for n in p1 p2 p3; do wt "$B/$n"; done; old "$B"/*   # 그보다 앞 이름 = git 이 멈춰 예산을 다 먹는다
  run FT_GIT_BIN="$T/git" HANG_PAT="$B/p" FT_TMP_SWEEP_BUDGET=4
  [ -f "$(ARM)" ] && [ ! -e "$(CUR)" ] && [ -d "$B/p1" ] && [ -d "$B/y" ] && [ -d "$B/z" ] \
    && [ "$(grep -c '^목록 지움 대상' <<<"$OUT")" = 2 ] && endl | grep -qE 'removed=0 .*deferred=0'     || { echo "  2차 $(endl) · 대상=$(grep -c '^목록 지움 대상' <<<"$OUT")"; return 1; }; }

# ⑨ 무장 뒤 48h+ 깨끗한 worktree 1개 → 판정문 보관 · 삭제 · prune 1 · removed=1 (r2073 그대로)
c9() { fresh armed; mkdir "$B/a-wt"; wt "$B/a-wt/w"; head -c 2048 /dev/urandom > "$B/a-wt/verdict.md"; old "$B/a-wt"
  cp "$B/a-wt/verdict.md" "$T/verdict.orig"; run FT_GIT_BIN="$T/git"
  [ ! -e "$B/a-wt" ] && cmp -s "$R/.fable-team/state/tmp-sweep-keep/a-wt/verdict.md" "$T/verdict.orig" \
    && [ "$(grep -c 'worktree prune' "$T/git.calls")" = 1 ] && endl | grep -qE 'removed=1 ' || { echo "  $(endl) · prune=$(grep -c 'worktree prune' "$T/git.calls")"; return 1; }; }

# ⑩ 목록 꼴 = 48h 지난 내 소유 폴더만(일반 파일·심링크·젊은 폴더 목록 밖) — 예산 0 이면 cursor·deferred 가 목록을 드러낸다
c10() { fresh; local e="$T/ext10"; wt "$e"; old "$e"
  wt "$B/a-wt"; mkdir "$B/m-nogit"; wt "$B/y-wt"; echo f > "$B/f-file"; ln -s "$e" "$B/l-link"; wt "$B/.hid"
  old "$B/a-wt" "$B/m-nogit" "$B/f-file" "$B/.hid"; old -h "$B/l-link"
  run FT_TMP_SWEEP_BUDGET=0
  [ "$(cat "$(CUR)" 2>/dev/null)" = .hid ] && endl | grep -qE 'deferred=3( |$)' || { echo "  첫 이름 [$(cat "$(CUR)" 2>/dev/null)] · $(endl)"; return 1; }; }

# ⑪ 지난 폴더라도 안쪽에 .git 이 없으면 목록엔 들고 지움 0 · 남김 수 0
c11() { fresh armed; mkdir "$B/m-nogit"; old "$B/m-nogit"
  run FT_TMP_SWEEP_BUDGET=0; [ "$(cat "$(CUR)" 2>/dev/null)" = m-nogit ] && endl | grep -qE 'deferred=1( |$)' || { echo "  목록에 안 듦"; return 1; }
  run; [ -d "$B/m-nogit" ] && endl | grep -q 'removed=0 .*kept=0(' && ! SLOG | grep -q '목록 지움 대상' || { echo "  $(endl)"; return 1; }; }

# ⑫ 지난 폴더 + 깨끗한 worktree = 무장 뒤 지운다(지움 범위 그대로)
c12() { fresh armed; wt "$B/a-wt"; old "$B/a-wt"; run
  [ ! -e "$B/a-wt" ] && endl | grep -q 'removed=1 ' && [ "$(grep -c . "$MLOG")" = 1 ]; }

# ⑬ '.' 로 시작하는 폴더는 목록에 든다 · 심링크는 목록에서 빠진다(가리키는 실제 폴더 손 0)
c13() { fresh armed; local e="$T/ext13"; wt "$e"; old "$e"; wt "$B/.hid-wt"; old "$B/.hid-wt"; ln -s "$e" "$B/l-link"; old -h "$B/l-link"
  run; [ ! -e "$B/.hid-wt" ] && [ -d "$e" ] && [ -L "$B/l-link" ] && endl | grep -q 'removed=1 ' || { echo "  $(endl)"; return 1; }; }

echo "# 시험 대상 = $([ "$SUT" = "$ORIG" ] && echo '고친 판' || echo "대조 $SUT")"
for c in "c1 ① 파일 2만개 + 지난 worktree 2개 · BUDGET=10 → 목록 끝(deferred=0)" "c2 ② 젊은 폴더·심링크·일반 파일 = 목록 0 · 손 0" \
  "c3 ③ 가짜 find rc 1 = 판정 불가 목록 · rc 3 · cursor 그대로 · armed 0" "c4 ④ 가짜 find 8초 = 7초 끊김 · 총 ≤12초" \
  "c5 ⑤ cursor 사라짐 = C 순서 «이상» 첫 항목(d)" "c6 ⑥ cursor 있음 = 그 항목(b)" "c7 ⑦ ko_KR.UTF-8 에서도 C 순서 · B1 0" \
  "c8 ⑧ 무장 전 두 실행 = 사라진 표식 다음부터 끝까지 · 무장" "c9 ⑨ 무장 뒤 = 보관 · 삭제 · prune 1 · removed=1" \
  "c10 ⑩ 목록 = 48h 지난 내 소유 폴더만(목록 꼴)" "c11 ⑪ 안쪽 .git 없으면 목록엔 들고 지움 0" "c12 ⑫ 깨끗한 worktree 지움" "c13 ⑬ '.' 폴더는 목록 · 심링크는 목록 밖"; do
  f="${c%% *}"; if "$f"; then ok "${c#* }"; else bad "${c#* }"; fi
done

# 변이 M1~M6 — 사본에서만 · 원본(고친 판)은 위에서 PASS · 표준입력 = python(sys.argv[1]=원본 · [2]=사본)
mutp() { # mutp <이름> <사례> <설명>
  local MS="$T/mut-$1.sh"
  python3 -c "$(cat)" "$ORIG" "$MS" || { bad "$1 변이 적용 안 됨"; return; }
  cmp -s "$MS" "$ORIG" && { bad "$1 변이 적용 안 됨"; return; }
  SUT="$MS"; if "$2" >/dev/null 2>&1; then bad "$1 $3 — 변이인데 PASS"; else ok "$1 $3 → FAIL(원본 PASS)"; fi; SUT="${R2375_SUT:-$ORIG}"
}
if [ -n "${R2375_SUT:-}" ]; then ok "변이 M1~M6 = 건너뜀(기준판 대조 실행)"; elif [ -f "$ORIG" ]; then
  mutp M1 c1 "목록을 옛 glob 으로 되돌림 → ①" <<'PY'
import io,sys
s=io.open(sys.argv[1],encoding='utf-8').read()
old='LIST=(); while IFS= read -r e; do [ -n "$e" ] && LIST+=("$e"); done <<<"$(LC_ALL=C sort <<<"$LISTOUT")"'
new='LIST=(); for e in "$BASE"/* "$BASE"/.[!.]*; do [ -e "$e" ] || [ -L "$e" ] || continue; LIST+=("$e"); done'
assert old in s; io.open(sys.argv[2],'w',encoding='utf-8').write(s.replace(old,new,1))
PY
  mutp M2 c3 "find 실패를 빈 목록으로 읽음 → ③" <<'PY'
import io,sys
s=io.open(sys.argv[1],encoding='utf-8').read()
old='if [ "$lsrc" != 0 ]; then'; new='if false; then'
assert old in s; io.open(sys.argv[2],'w',encoding='utf-8').write(s.replace(old,new,1))
PY
  mutp M3 c2 "find 의 ! -mmin 뺌 + 항목마다 young 검사도 뺌 → ②" <<'PY'
import io,sys
s=io.open(sys.argv[1],encoding='utf-8').read()
a=' -user "$(id -u)" ! -mmin -"$AGE" -print'; b=' -user "$(id -u)" -print'
y='  if [ -n "$(find "$d" -maxdepth 0 -mmin -"$AGE" 2>/dev/null)" ]; then young=$((young+1)); logline "남김 young $d"; continue; fi'
assert a in s and y in s
s=s.replace(a,b,1).replace(y,'  :',1)
io.open(sys.argv[2],'w',encoding='utf-8').write(s)
PY
  mutp M4 c5 "cursor 를 «이름 같음» 만으로 → ⑤" <<'PY'
import io,sys
s=io.open(sys.argv[1],encoding='utf-8').read()
old='         pos="$( { printf \'%s\\n\' "$cn"; printf \'%s\\n\' "${LIST[@]##*/}"; } | LC_ALL=C sort | grep -n -x -F -e "$cn" | head -n 1 | cut -d: -f1 )"\n         case "$pos" in \'\'|*[!0-9]*) logline "cursor 위치 못 찾음 — 처음부터";; *) START=$((pos - 1));; esac'
new='         for k in "${!LIST[@]}"; do [ "${LIST[$k]##*/}" = "$cn" ] && { START=$k; break; }; done'
assert old in s, "pos 줄 못 찾음"; io.open(sys.argv[2],'w',encoding='utf-8').write(s.replace(old,new,1))
PY
  mutp M5 c6 "«이상» 을 «초과» 로 → ⑥" <<'PY'
import io,sys
s=io.open(sys.argv[1],encoding='utf-8').read()
old='START=$((pos - 1))'; new='START=$((pos))'
assert old in s; io.open(sys.argv[2],'w',encoding='utf-8').write(s.replace(old,new,1))
PY
  mutp M6 c7 "sort 의 LC_ALL=C 뺌 → ⑦" <<'PY'
import io,sys
s=io.open(sys.argv[1],encoding='utf-8').read()
n=s.replace('LC_ALL=C sort','sort')
assert n!=s; io.open(sys.argv[2],'w',encoding='utf-8').write(n)
PY
fi
[ -f "$KIT" ] && cmp -s "$ORIG" "$KIT" && ok "bin·kit cmp 0" || bad "bin·kit 다름"
[ "$fail" = 0 ] && { echo "(all passed)"; exit 0; } || { echo "($fail failed)"; exit 1; }
