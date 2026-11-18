#!/usr/bin/env bash
# test_disk_reclaim_squash_r2196.sh — r2196 ft-disk-reclaim.sh squash 착지 worktree 반례 ②~⑩(① = test_disk_reclaim_r2107.sh 재실행).
# 입력은 mktemp 안: 임시 리포 2개(가짜 origin) · 가짜 gh(FT_RECLAIM_GH · stdout = gh pr list JSON · 리포별 rc) · 가짜 lsof · tmux.
# 실 gh 0 · 네트워크 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="${FT_DISK_RECLAIM_BIN:-$HERE/../bin/ft-disk-reclaim.sh}"
W="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$W"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
[ -f "$TOOL" ] || { echo "FAIL 도구 없음: $TOOL"; exit 1; }
T0=$SECONDS

FK="$W/fake"; mkdir -p "$FK/bin" "$W/tmp" "$W/cache"
cat > "$FK/bin/gh" <<EOF
#!/bin/bash
k=\$(basename "\$PWD"); n=\$(( \$(cat "$FK/gh.\$k.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$FK/gh.\$k.n"; echo "\$*" > "$FK/gh.\$k.args"
cat "$FK/gh.\$k.json" 2>/dev/null; exit "\$(cat "$FK/gh.\$k.rc" 2>/dev/null || echo 0)"
EOF
printf '#!/bin/bash\necho p1; exit 0\n' > "$FK/bin/lsof"; printf '#!/bin/bash\nexit 0\n' > "$FK/bin/tmux"
chmod +x "$FK/bin/"*
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
export PATH="$FK/bin:$PATH" FT_RECLAIM_GH="$FK/bin/gh" FT_RECLAIM_TMP_ROOT="$W/tmp" FT_RECLAIM_CACHE_ROOT="$W/cache" FT_RECLAIM_INFO="" FT_RECLAIM_DF_PATH=/

mkrepo() { git init -q --bare "$W/o$1" && git clone -q "$W/o$1" "$W/r$1" 2>/dev/null && echo f > "$W/r$1/f" && echo d > "$W/r$1/gone" \
  && git -C "$W/r$1" add f gone && git -C "$W/r$1" commit -qm c1 && git -C "$W/r$1" push -q origin main; }
mkrepo A; mkrepo B; RA="$W/rA"; RB="$W/rB"; WT="$W/wts"
# br <리포> <이름> : 가지 b<이름> 의 worktree s<이름> · 파일 f<이름> 커밋 · push
br() { git -C "$1" worktree add -q -b "b$2" "$WT/s$2" main && echo "$2" > "$WT/s$2/f$2" && git -C "$WT/s$2" add "f$2" \
  && git -C "$WT/s$2" commit -qm "pr $2" && git -C "$WT/s$2" push -q origin "b$2" 2>/dev/null; }
# sq <리포> <이름> : main 에 squash 착지 · push · 착지 커밋 sha 출력
sq() { git -C "$1" merge -q --squash "b$2" >/dev/null && git -C "$1" commit -qm "squash $2" && git -C "$1" push -q origin main && git -C "$1" rev-parse HEAD; }
pr() { printf '{"number":%s,"headRefName":"%s","headRefOid":"%s","baseRefName":"%s","mergeCommit":{"oid":"%s"}}' "$@"; }
head_() { git -C "$WT/s$1" rev-parse HEAD; }

br "$RA" 2; M2=$(sq "$RA" 2)                                                         # ② 착지 · 같음
git -C "$RA" worktree add -q -b b2d "$WT/s2d" main && git -C "$WT/s2d" rm -q gone && git -C "$WT/s2d" commit -qm del \
  && git -C "$WT/s2d" push -q origin b2d 2>/dev/null; M2d=$(git -C "$RA" merge -q --squash b2d >/dev/null && git -C "$RA" commit -qm "squash 2d" && git -C "$RA" push -q origin main && git -C "$RA" rev-parse HEAD)   # ② PR 이 지운 파일
br "$RA" 3; M3=$(sq "$RA" 3); echo more > "$WT/s3/f3"; git -C "$WT/s3" commit -qam more && git -C "$WT/s3" push -q origin b3 2>/dev/null   # ③
br "$RA" 4; sq "$RA" 4 >/dev/null                                                     # ④ 착지 커밋 로컬 없음
br "$RA" 5; M5=$(sq "$RA" 5)                                                          # ⑤ PR 2건
br "$RA" 6; sq "$RA" 6 >/dev/null                                                     # ⑥ 목록에 없음
br "$RA" 7; M7=$(sq "$RA" 7); H7=$(head_ 7); git -C "$WT/s7" checkout -q --detach     # ⑦ detached
br "$RA" 9; M9=$(sq "$RA" 9); echo dirty >> "$WT/s9/f9"                               # ⑨ 수정 파일
br "$RA" 10; M10=$(sq "$RA" 10); H10=$(head_ 10); echo x > "$WT/s10/X"; git -C "$WT/s10" add X && git -C "$WT/s10" commit -qm X && git -C "$WT/s10" push -q origin b10 2>/dev/null   # ⑩
br "$RA" 12; M12=$(sq "$RA" 12)                                                       # base ≠ main
br "$RB" 8; M8=$(sq "$RB" 8)                                                          # ⑧ 리포 B
{ echo "["; pr 2 b2 "$(head_ 2)" main "$M2"; echo ","; pr 21 b2d "$(head_ 2d)" main "$M2d"; echo ","; pr 3 b3 "$(head_ 3)" main "$M3"; echo ","
  pr 4 b4 "$(head_ 4)" main 0123456789abcdef0123456789abcdef01234567; echo ","; pr 5 b5 "$(head_ 5)" main "$M5"; echo ","; pr 55 b5 "$(head_ 5)" main "$M5"; echo ","
  pr 7 b7 "$H7" main "$M7"; echo ","; pr 9 b9 "$(head_ 9)" main "$M9"; echo ","; pr 10 b10 "$H10" main "$M10"; echo ","; pr 12 b12 "$(head_ 12)" ops/main-base "$M12"; echo "]"; } > "$FK/gh.rA.json"
printf '[%s]' "$(pr 8 b8 "$(head_ 8)" main "$M8")" > "$FK/gh.rB.json"
OLD="$(date -v-8d +%Y%m%d%H%M)"; for i in "$RA"/.git/worktrees/* "$RB"/.git/worktrees/*; do touch -t "$OLD" "$i/index"; done
T1=$SECONDS

C="$W/out/candidates.tsv"; line() { awk -F'\t' -v k="$1" -v p="$2" '$1==k && $3==p{print $4}' "$C"; }
plan() { rm -f "$FK"/gh.*.n; err="$(FT_RECLAIM_REPOS="$RA:$RB" bash "$TOOL" plan "$W/out" 2>&1 >/dev/null)"; rc=$?; }
plan
chk "②plan rc 0" "$rc" 0
chk "②squash 착지 → 후보 · 꼬리 squash PR #2" "$(line worktree "$WT/s2")" "repo=$RA squash PR #2"
chk "②PR 이 지운 파일 양쪽 다 없음 → 후보" "$(line worktree "$WT/s2d")" "repo=$RA squash PR #21"
chk "③PR 파일 더 고친 커밋 → hold 조상 아님" "$(line hold "$WT/s3")" "조상 아님"
chk "④착지 커밋 로컬 없음 → hold 조상 아님" "$(line hold "$WT/s4")" "조상 아님"
chk "⑤같은 가지 MERGED PR 2건 → hold 조상 아님" "$(line hold "$WT/s5")" "조상 아님"
chk "⑥목록에 없음(OPEN · CLOSED) → hold 조상 아님" "$(line hold "$WT/s6")" "조상 아님"
chk "⑦detached → hold 조상 아님" "$(line hold "$WT/s7")" "조상 아님"
chk "⑨squash 길 + 수정 파일 → hold 수정 파일 squash PR #9" "$(line hold "$WT/s9")" "수정 파일 squash PR #9"
chk "⑩착지 뒤 PR 밖 파일 커밋 push(HEAD ≠ headRefOid) → hold 조상 아님" "$(line hold "$WT/s10")" "조상 아님"
chk "ⓔbase ≠ main → hold 조상 아님" "$(line hold "$WT/s12")" "조상 아님"
chk "D1 리포마다 조회 1회 · --state merged · --limit" "$(cat "$FK/gh.rA.n" 2>/dev/null)|$(grep -c -- '--state merged --limit' "$FK/gh.rA.args" 2>/dev/null)" "1|1"
chk "D1 성공 → 판정 불가 줄 0" "$(printf '%s' "$err" | grep -c 'squash 길 판정 불가')" 0
chk "②리포 B 후보" "$(line worktree "$WT/s8")" "repo=$RB squash PR #8"

echo 1 > "$FK/gh.rB.rc"; plan; rm -f "$FK/gh.rB.rc"
chk "⑧gh rc 1 → 리포 B squash 길 0 · hold 조상 아님" "$rc|$(line hold "$WT/s8")" "0|조상 아님"
chk "⑧판정 불가 1줄 · rc 그대로 · 재시도 1" "$(printf '%s\n' "$err" | grep -c "^squash 길 판정 불가 $RB rc=1$")|$(cat "$FK/gh.rB.n" 2>/dev/null)" "1|2"
chk "⑧다른 리포 squash 길 그대로" "$(line worktree "$WT/s2")" "repo=$RA squash PR #2"
T2=$SECONDS

# apply 도 같은 squash 길로 다시 판정 → ② 지움 · ③ SKIP
grep -e "$WT/s2	" -e "^hold" "$C" > "$W/out/a.tsv"; printf 'worktree\t1\t%s\trepo=x\n' "$WT/s3" >> "$W/out/a.tsv"
FT_RECLAIM_REPOS="$RA:$RB" bash "$TOOL" apply "$W/out/a.tsv" > /dev/null 2>&1; rc=$?
chk "apply rc 0 · ② DELETED · ③ SKIP 조상 아님" "$rc|$([ -e "$WT/s2" ] && echo y || echo n)$([ -e "$WT/s3" ] && echo y || echo n)|$(grep -c $'^SKIP\tworktree\t'"$WT/s3"$'\t조상 아님$' "$W/out/deleted.log")" "0|ny|1"
T3=$SECONDS
echo "TIME 준비=$((T1-T0))s plan=$((T2-T1))s apply=$((T3-T2))s"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL count=$fail"
exit $(( fail > 0 ))
