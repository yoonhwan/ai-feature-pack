#!/usr/bin/env bash
# test_disk_reclaim_r2107.sh — r2107 ft-disk-reclaim.sh plan · apply 반례 ①~⑧.
# 모든 입력은 mktemp 안: 가짜 뿌리(tmp · cache) · 임시 리포 2개(가짜 origin) · 가짜 lsof · tmux · df · du 를 PATH 앞에. 실 /private/tmp · 캐시 · 리포 · tmux 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="${FT_DISK_RECLAIM_BIN:-$HERE/../bin/ft-disk-reclaim.sh}"
W="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }   # <파일> <글자>
ex() { [ -e "$1" ] || [ -L "$1" ] && echo yes || echo no; }
OLD="$(date -v-8d +%Y%m%d%H%M)"; D6="$(date -v-6d +%Y%m%d%H%M)"; D1="$(date -v-1d +%Y%m%d%H%M)"
age() { local t="$1"; shift; for p in "$@"; do find "$p" -depth -exec touch -h -t "$t" {} +; done; }
[ -f "$TOOL" ] || { echo "FAIL 도구 없음: $TOOL"; exit 1; }
bash -n "$TOOL" && echo "PASS bash -n" || { echo "FAIL bash -n"; fail=$((fail+1)); }

# 가짜 명령(호출 수 · rc · 출력 = $FK 파일)
FK="$W/fake"; mkdir -p "$FK/bin"
cat > "$FK/bin/lsof" <<EOF
#!/bin/bash
[ -f "$FK/lsof.rc" ] && exit "\$(cat "$FK/lsof.rc")"; echo p1; cat "$FK/lsof.out" 2>/dev/null; exit 0
EOF
cat > "$FK/bin/tmux" <<EOF
#!/bin/bash
n=\$(( \$(cat "$FK/tmux.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$FK/tmux.n"
[ -f "$FK/tmux.failat" ] && [ "\$n" -ge "\$(cat "$FK/tmux.failat")" ] && exit 1; cat "$FK/panes" 2>/dev/null; exit 0
EOF
cat > "$FK/bin/df" <<EOF
#!/bin/bash
n=\$(( \$(cat "$FK/df.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$FK/df.n"
v=\$(sed -n "\${n}p" "$FK/df.vals"); [ -n "\$v" ] || v=\$(tail -1 "$FK/df.vals")
echo "Filesystem 1024-blocks Used Available Capacity Mounted"; echo "/dev/x 9 9 \$v 99% /"
EOF
cat > "$FK/bin/du" <<'EOF'
#!/bin/bash
case "$*" in *slow-item*) exec sleep 5 ;; esac; exec /usr/bin/du "$@"
EOF
cat > "$FK/bin/rm" <<'EOF'
#!/bin/bash
case "$*" in *slow-rm*) exec sleep 5 ;; esac; exec /bin/rm "$@"
EOF
chmod +x "$FK/bin/"*; printf '1048576\n3145728\n' > "$FK/df.vals"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = t\n\temail = t@t\n[protocol "file"]\n\tallow = always\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
T0=$SECONDS

# 가짜 뿌리 — ② tmp · ③ cache
TR="$W/tmp"; CR="$W/cache"; mkdir -p "$TR" "$CR" "$W/outside" "$W/out1"; echo keep > "$W/outside/k"
( cd "$TR" && echo x > f8 && echo x > f6 && mkdir d8new dopen a 'a b' c 'c d' symdir t5open rm1 rm2 && echo x > d8new/new && echo x > dopen/inner \
  && echo x > a/i && echo x > 'a b/i' && echo x > c/i && echo x > 'c d/i' && ln -s "$W/outside" lnk && ln -s "$W/outside" symdir/out && echo x > $'t\tab' )
age "$OLD" "$TR"/*; age "$D6" "$TR/f6"; touch -t "$D1" "$TR/d8new/new"
( cd "$CR" && mkdir c1 copen && echo x > c1/z && echo x > copen/z && ln -s "$W/outside" clink ); age "$D1" "$CR"/*
printf 'n%s\n' "$TR/dopen/inner" "$TR/a" "$TR/c d/i" "$CR/copen/z" > "$FK/lsof.out"

# 임시 리포 2개 — ④ worktree
mkrepo() { git init -q --bare "$W/o$1" && git clone -q "$W/o$1" "$W/r$1" 2>/dev/null && echo f > "$W/r$1/f" && git -C "$W/r$1" add f && git -C "$W/r$1" commit -qm c1 && git -C "$W/r$1" push -q origin main; }
mkrepo A; mkrepo B; RA="$W/rA"; RB="$W/rB"; WT="$W/wts"
wt() { git -C "$1" worktree add -q --detach "$WT/$2" "${3:-main}" 2>/dev/null; }
for n in good1 'x@a1' 'x@a10' locked notanc dirty untracked unpushed pane idxnew wbad w5p w5f; do wt "$RA" "$n"; done; wt "$RB" rbw1
git -C "$RA" worktree lock "$WT/locked"
git -C "$WT/notanc" commit -q --allow-empty -m side && git -C "$WT/notanc" push -q origin HEAD:refs/heads/side
echo y >> "$WT/dirty/f"; echo u > "$WT/untracked/u"; git -C "$WT/unpushed" commit -q --allow-empty -m local
( cd "$RA" && git submodule add -q "$W/oB" sm 2>/dev/null && git commit -qm sm && git push -q origin main ); wt "$RA" sm; git -C "$WT/sm" submodule update -q --init 2>/dev/null
for i in "$RA"/.git/worktrees/* "$RB"/.git/worktrees/*; do touch -t "$OLD" "$i/index"; done; touch "$RA/.git/worktrees/idxnew/index"
echo junk > "$RA/.git/worktrees/wbad/index"
printf '%s\n' "$WT/pane/sub" "$WT/x@a1" > "$FK/panes"
export PATH="$FK/bin:$PATH" FT_RECLAIM_TMP_ROOT="$TR" FT_RECLAIM_CACHE_ROOT="$CR" FT_RECLAIM_REPOS="$RA:$RB" FT_RECLAIM_INFO="$W/outside" FT_RECLAIM_DF_PATH=/
snap() { (cd "$W" && find tmp cache rA rB wts outside | LC_ALL=C sort; for r in "$RA" "$RB"; do git -C "$r" worktree list --porcelain; git -C "$r" for-each-ref; done); }
BR0="$(git -C "$RA" for-each-ref refs/heads | wc -l)/$(git -C "$RB" for-each-ref refs/heads | wc -l)"
T1=$SECONDS

# ① 목록(읽기만)
snap > "$W/s0"; out="$(bash "$TOOL" plan "$W/out1" 2>/dev/null)"; rc=$?; snap > "$W/s1"; C="$W/out1/candidates.tsv"
chk "①plan rc 0" "$rc" 0
chk "①산출 = candidates.tsv 1파일" "$(ls "$W/out1" | xargs)" candidates.tsv
chk "①뿌리 · 리포 · worktree · 가지 목록 앞뒤 같음" "$(cmp -s "$W/s0" "$W/s1" && echo same || echo diff)" same
chk "①줄 꼴 4칸" "$(awk -F'\t' 'NF!=4' "$C" | wc -l | tr -d ' ')" 0
chk "①PLAN 줄" "${out%% *}" PLAN
sizes_ok() { awk -F'\t' -v k="$1" '$1==k{print $2}' "$C" | sort -c -n -r 2>/dev/null && echo yes || echo no; }
chk "①종류 안 크기 큰 순(tmp · worktree)" "$(sizes_ok tmp)$(sizes_ok worktree)" yesyes
line() { awk -F'\t' -v k="$1" -v p="$2" '$1==k && $3==p{print $4}' "$C"; }
for c in "locked:locked" "notanc:조상 아님" "dirty:수정 파일" "untracked:수정 파일" "unpushed:조상 아님" "pane:tmux pane" "idxnew:index 최근" "x@a1:tmux pane"; do
  chk "①hold ${c%%:*} = ${c#*:}" "$(line hold "$WT/${c%%:*}")" "${c#*:}"; done
chk "①hold 주 worktree" "$(line hold "$RA")" "주 worktree"
chk "①info 줄" "$(awk -F'\t' '$1=="info"' "$C" | cut -f3)" "$W/outside"

# ② tmp
for c in "f8:y" "f6:n" "d8new:n" "dopen:n" "a:n" "a b:y" "c:y" "c d:n" "lnk:n" "symdir:y" $'t\tab:n'; do
  chk "②tmp ${c%%:*} 줄 $( [ "${c#*:}" = y ] && echo 있음 || echo 없음)" "$(awk -F'\t' -v p="$TR/${c%%:*}" '$1=="tmp" && $3==p' "$C" | wc -l | tr -d ' ')" "$( [ "${c#*:}" = y ] && echo 1 || echo 0)"; done
# ③ cache
for c in "c1:1" "copen:0" "clink:0"; do chk "③cache ${c%%:*}" "$(awk -F'\t' -v p="$CR/${c%%:*}" '$1=="cache" && $3==p' "$C" | wc -l | tr -d ' ')" "${c#*:}"; done
# ④ worktree
for c in "good1:1" "x@a10:1" "w5p:1" "w5f:1" "sm:1" "locked:0" "notanc:0" "dirty:0" "untracked:0" "unpushed:0" "pane:0" "idxnew:0" "x@a1:0" "wbad:0"; do
  chk "④worktree ${c%%:*}" "$(awk -F'\t' -v p="$WT/${c%%:*}" '$1=="worktree" && $3==p' "$C" | wc -l | tr -d ' ')" "${c#*:}"; done
chk "④주 worktree 지울 줄 없음" "$(awk -F'\t' -v p="$RA" '$1=="worktree" && $3==p' "$C" | wc -l | tr -d ' ')" 0
chk "④리포 B 후보" "$(line worktree "$WT/rbw1")" "repo=$RB"
# ⑦ 줄 하나의 git 판정 실패 → 그 줄만 hold 판정 불가
chk "⑦git status 실패 → hold 판정 불가" "$(line hold "$WT/wbad")" "판정 불가"
T2=$SECONDS

# ⑤ 지우기 — 줄 2개(rm1 · rm2)를 뺀 목록 · 목록 뒤 바뀐 것 3개
mkdir -p "$W/out5"; grep -v -e "$TR/rm1" -e "$TR/rm2" "$C" | grep -v "$WT/rbw1" > "$W/out5/candidates.tsv"; L5="$W/out5/deleted.log"
echo "$WT/w5p" >> "$FK/panes"; echo new > "$WT/w5f/new"; echo "n$TR/t5open" >> "$FK/lsof.out"; echo 0 > "$FK/df.n"
bash "$TOOL" apply "$W/out5/candidates.tsv" > /dev/null 2>&1; rc=$?
chk "⑤apply rc 0" "$rc" 0
chk "⑤뺀 줄 2개 그대로" "$(ex "$TR/rm1")$(ex "$TR/rm2")" yesyes
chk "⑤남은 줄 지워짐(f8 · a b · c · symdir · c1 · good1 · x@a10)" "$(for p in "$TR/f8" "$TR/a b" "$TR/c" "$TR/symdir" "$CR/c1" "$WT/good1" "$WT/x@a10"; do ex "$p"; done | xargs)" "no no no no no no no"
chk "⑤공백 경로 지움 · 접두 이웃 a 그대로" "$(ex "$TR/a b")$(ex "$TR/a")" noyes
chk "⑤worktree 지운 뒤 목록에서도 빠짐" "$(git -C "$RA" worktree list | grep -c "$WT/good1 ")" 0
chk "⑤목록 뒤 pane → SKIP · 폴더 그대로" "$(has "$L5" $'SKIP\tworktree\t'"$WT/w5p"$'\ttmux pane')$(ex "$WT/w5p")" yesyes
chk "⑤목록 뒤 파일 생김 → SKIP · 폴더 그대로" "$(has "$L5" $'SKIP\tworktree\t'"$WT/w5f"$'\t수정 파일')$(ex "$WT/w5f")" yesyes
chk "⑤목록 뒤 열림 → SKIP" "$(has "$L5" $'SKIP\ttmp\t'"$TR/t5open"$'\t열린 파일')$(ex "$TR/t5open")" yesyes
chk "⑤하위 모듈 worktree = --force 없이 SKIP · 그대로" "$(has "$L5" $'SKIP\tworktree\t'"$WT/sm"$'\t지우기 실패')$(ex "$WT/sm/f")" yesyes
chk "⑤DELETED 줄 꼴" "$(grep -c "^DELETED"$'\t'"tmp"$'\t'"[0-9]*"$'\t'"$TR/f8\$" "$L5")" 1
chk "⑤SUMMARY 줄" "$(tail -1 "$L5")" "SUMMARY freed_gib=2.0 before_kib=1048576 after_kib=3145728 deleted=7 skipped=4"
T3=$SECONDS

# ⑥ 지우지 않는 것
chk "⑥심링크가 가리키던 밖 폴더 · 파일 그대로" "$(ex "$W/outside/k")" yes
mkdir -p "$W/ext" "$TR/two/deep" "$W/out6"; echo x > "$W/ext/e"; age "$OLD" "$W/ext" "$TR/two"
printf 'tmp\t1\t%s\tx\ntmp\t1\t%s\tx\ntmp\t1\t%s\tx\nworktree\t1\t%s\tx\n' "$W/ext" "$TR/../ext" "$TR/two/deep" "$WT/rbw1" > "$W/out6/candidates.tsv"
echo 0 > "$FK/df.n"; FT_RECLAIM_REPOS="$RA" bash "$TOOL" apply "$W/out6/candidates.tsv" > /dev/null 2>&1; rc=$?; L6="$W/out6/deleted.log"
chk "⑥손으로 더한 줄 3개 SKIP 범위 밖" "$(grep -c $'^SKIP\ttmp\t.*\t범위 밖$' "$L6")" 3
chk "⑥대상 그대로" "$(ex "$W/ext/e")$(ex "$TR/two/deep")" yesyes
chk "⑥리포 목록 밖 worktree → SKIP" "$(has "$L6" $'SKIP\tworktree\t'"$WT/rbw1"$'\t범위 밖 리포')$(ex "$WT/rbw1")" yesyes
chk "⑥가지 수 앞뒤 같음" "$(git -C "$RA" for-each-ref refs/heads | wc -l)/$(git -C "$RB" for-each-ref refs/heads | wc -l)" "$BR0"
mkdir -p "$W/out6r"; FT_RECLAIM_TMP_ROOT=/ bash "$TOOL" plan "$W/out6r" > /dev/null 2>&1; rc1=$?
FT_RECLAIM_CACHE_ROOT="$HOME" bash "$TOOL" apply "$W/out6/candidates.tsv" > /dev/null 2>&1; rc2=$?
chk "⑥뿌리 / · 홈 → rc≠0 · 쓰기 0" "$([ $rc1 -ne 0 ] && [ $rc2 -ne 0 ] && echo yes)$(ls "$W/out6r" | wc -l | tr -d ' ')$(wc -l < "$L6" | tr -d ' ')" "yes0$(wc -l < "$L6" | tr -d ' ')"
T4=$SECONDS

# ⑦ 판정 불가
echo 1 > "$FK/lsof.rc"; err="$(bash "$TOOL" plan "$W/out7a" 2>&1 >/dev/null)"; rc=$?; rm -f "$FK/lsof.rc"
chk "⑦lsof rc 1 → rc≠0 · 판정 불가 lsof · 목록 0" "$([ $rc -ne 0 ] && echo y)|$err|$(ex "$W/out7a/candidates.tsv")" "y|판정 불가 lsof|no"
echo 0 > "$FK/tmux.n"; echo 1 > "$FK/tmux.failat"; err="$(bash "$TOOL" plan "$W/out7b" 2>&1 >/dev/null)"; rc=$?
chk "⑦tmux rc 1 → 같은 꼴" "$([ $rc -ne 0 ] && echo y)|$err|$(ex "$W/out7b/candidates.tsv")" "y|판정 불가 tmux|no"
wt "$RA" wq1; wt "$RA" wq2; touch -t "$OLD" "$RA/.git/worktrees/wq1/index" "$RA/.git/worktrees/wq2/index"; mkdir -p "$W/out7c"
printf 'worktree\t1\t%s\tx\nworktree\t1\t%s\tx\ntmp\t1\t%s\tx\n' "$WT/wq1" "$WT/wq2" "$TR/rm1" > "$W/out7c/candidates.tsv"
echo 0 > "$FK/tmux.n"; echo 2 > "$FK/tmux.failat"; echo 0 > "$FK/df.n"; err="$(bash "$TOOL" apply "$W/out7c/candidates.tsv" 2>&1 >/dev/null)"; rc=$?; rm -f "$FK/tmux.failat"
chk "⑦apply 도중 tmux rc 1 → 첫 줄 DELETED · 뒤 0 · ABORT · rc≠0" "$(cut -f1 "$W/out7c/deleted.log" | cut -d' ' -f1-4 | xargs)|$(ex "$WT/wq1")$(ex "$WT/wq2")$(ex "$TR/rm1")|$([ $rc -ne 0 ] && echo y)|$err" "DELETED ABORT 판정 불가 tmux|noyesyes|y|판정 불가 tmux"
T5=$SECONDS

# ⑧ 시간 — du 가 timeout 을 넘기는 항목은 후보 아님
T8="$W/tmp8"; mkdir -p "$T8/slow-item" "$T8/fast-item"; age "$OLD" "$T8"/*
out="$(FT_RECLAIM_TIMEOUT=1 FT_RECLAIM_TMP_ROOT="$T8" FT_RECLAIM_REPOS="$RB" bash "$TOOL" plan "$W/out8" 2>/dev/null)"; rc=$?
chk "⑧rc 0 · slow 줄 없음 · fast 줄 있음" "$rc|$(grep -c slow-item "$W/out8/candidates.tsv")|$(grep -c fast-item "$W/out8/candidates.tsv")" "0|0|1"
# ⑧b 지우기도 공통 상한(DA #317143) — rm 이 상한을 넘기면 그 줄 SKIP · 보존 · 다음 줄은 계속
mkdir -p "$T8/slow-rm" "$W/out8b"; age "$OLD" "$T8/slow-rm"; echo 0 > "$FK/df.n"
printf 'tmp\t1\t%s\tx\ntmp\t1\t%s\tx\n' "$T8/slow-rm" "$T8/fast-item" > "$W/out8b/candidates.tsv"
FT_RECLAIM_TIMEOUT=1 FT_RECLAIM_TMP_ROOT="$T8" FT_RECLAIM_REPOS="$RB" bash "$TOOL" apply "$W/out8b/candidates.tsv" > /dev/null 2>&1; rc=$?
chk "⑧b 지우기 상한 초과 → SKIP 시간 초과 · 보존 · 다음 줄 DELETED · rc 0" "$rc|$(has "$W/out8b/deleted.log" $'SKIP\ttmp\t'"$T8/slow-rm"$'\t시간 초과')$(ex "$T8/slow-rm")|$(ex "$T8/fast-item")" "0|yesyes|no"
T6=$SECONDS
echo "TIME 준비=$((T1-T0))s ①~④=$((T2-T1))s ⑤=$((T3-T2))s ⑥=$((T4-T3))s ⑦=$((T5-T4))s ⑧=$((T6-T5))s"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL count=$fail"
exit $(( fail > 0 ))
