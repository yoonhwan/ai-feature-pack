#!/usr/bin/env bash
# test_disk_reclaim_quarantine_r2301.sh — r2301 A2 · A2b · A3 · A4: worktree 지우기가 끊겨도 원래 자리에 반쯤 지운 것이 안 남는다.
#   ② 느린 지우기(시간 초과) → 원래 자리 0 · 격리 자리에만 남음 · 표식 1줄 / ③ 다음 apply 가 사람 손 없이 마무리
#   ③a .git 까지 지워진 꼴 = repair 뒤 DELETED · 남의 prunable 줄 그대로(prune 0) · repair 실패 꼴 = SKIP 조건 · 격리 경로에 git -C 0
#   ③b 격리 밖 «수정 파일» 은 기존대로 SKIP / ③c 표식 없는 격리 worktree = SKIP «표식 없음» / ③d ?? · HEAD≠표식 = SKIP 조건
#   ③e 표식 있음 ∧ 격리 폴더 없음 = «DONE 격리 폴더 없음» 1줄 · 표식 줄만 지움 / ④ 크기 상한 = MOVED · 다음 apply 가 지움
#   ⑤ 불변 = tmp 줄 그대로 · 판정 불가면 지우기 0 · ft-scratch-repo.sh diff 0
# 모든 입력은 mktemp 안: 임시 리포 · 가짜 lsof · tmux · df · du 를 PATH 앞에, git 은 호출 기록 + 느린 지우기/실패 repair 대역. 실 리포·실 사본 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="${FT_DISK_RECLAIM_BIN:-$HERE/../bin/ft-disk-reclaim.sh}"   # r2301: 기준판 사본을 같은 시험으로 돌려 Red 를 보이기 위한 갈래
[ -f "$TOOL" ] || { echo "FAIL 도구 없음: $TOOL"; exit 1; }
GITREAL="$(command -v git)"
W="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }         # <파일> <글자>
cnt() { local n; n="$(grep -cE -- "$1" "$2" 2>/dev/null)"; echo "${n:-0}"; }   # <정규식> <파일> — 없으면 0
ex()  { { [ -e "$1" ] || [ -L "$1" ]; } && echo yes || echo no; }
OLD="$(date -v-8d +%Y%m%d%H%M)"
T0=$SECONDS
bash -n "$TOOL" && ok "bash -n" || bad "bash -n"

# ── 가짜 명령 — git 은 호출 기록 + 조건부 대역(느린 지우기 · 실패 repair · 실패 move)
FK="$W/fake"; mkdir -p "$FK/bin"
cat > "$FK/bin/git" <<EOF
#!/bin/bash
echo "\$*" >> "$FK/git.calls"
case " \$* " in
  *" worktree remove "*)
    if [ -f "$FK/slowremove" ]; then
      p="\${@: -1}"
      [ -d "\$p" ] && find "\$p" -mindepth 1 -maxdepth 1 ! -name .git -exec /bin/rm -rf {} + 2>/dev/null
      sleep 5
    fi;;
  *" worktree repair "*) [ -f "$FK/failrepair" ] && { echo "repair 대역 실패" >&2; exit 1; } ;;
  *" worktree move "*) [ -f "$FK/failmove" ] && { echo "move 대역 실패" >&2; exit 1; } ;;
esac
exec "$GITREAL" "\$@"
EOF
printf '#!/bin/bash\ncat "%s/panes" 2>/dev/null; exit 0\n' "$FK" > "$FK/bin/tmux"
printf '#!/bin/bash\n[ -f "%s/lsof.rc" ] && exit "$(cat "%s/lsof.rc")"; echo p1; cat "%s/lsof.out" 2>/dev/null; exit 0\n' "$FK" "$FK" "$FK" > "$FK/bin/lsof"
printf '#!/bin/bash\necho "Filesystem 1024-blocks Used Available Capacity Mounted"; echo "/dev/x 9 9 $(cat "%s/df.v" 2>/dev/null || echo 1048576) 99%% /"\n' "$FK" > "$FK/bin/df"
chmod +x "$FK/bin/"*
: > "$FK/git.calls"; : > "$FK/panes"; echo 1048576 > "$FK/df.v"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = t\n\temail = t@t\n[protocol "file"]\n\tallow = always\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
TR="$W/tmp"; CR="$W/cache"; WT="$W/wts"; mkdir -p "$TR" "$CR" "$WT"

mkrepo() { git init -q --bare "$W/o$1" && git clone -q "$W/o$1" "$W/r$1" 2>/dev/null && echo f > "$W/r$1/f" && git -C "$W/r$1" add f && git -C "$W/r$1" commit -qm c1 && git -C "$W/r$1" push -q origin main; }
wt() { git -C "$W/r$1" worktree add -q --detach "$WT/$2" "${3:-main}" 2>/dev/null; }
gcd() { git -C "$1" rev-parse --path-format=absolute --git-common-dir; }
ageidx() { local i; for i in "$1"/.git/worktrees/*/; do touch -t "$OLD" "$i/index"; done; }
export PATH="$FK/bin:$PATH" FT_RECLAIM_TMP_ROOT="$TR" FT_RECLAIM_CACHE_ROOT="$CR" FT_RECLAIM_DF_PATH=/
ap() { local repo="$1" tsv="$2"; shift 2; env FT_RECLAIM_REPOS="$repo" "$@" bash "$TOOL" apply "$tsv" > "$W/out.txt" 2>&1; echo $?; }   # <리포> <목록> [ENV=…]
row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
T1=$SECONDS

# ── ② 느린 지우기 → 원래 자리 0 · 격리 자리로 · 표식 1줄
mkrepo A; RA="$W/rA"; GA="$(gcd "$RA")"; QA="$GA/ft-reclaim-q"; MA="$GA/ft-reclaim-q.tsv"
wt A q1; ageidx "$RA"
mkdir -p "$W/outA1"; row worktree 1 "$WT/q1" "repo=$RA" > "$W/outA1/candidates.tsv"
: > "$FK/git.calls"; touch "$FK/slowremove"
rc="$(ap "$RA" "$W/outA1/candidates.tsv" FT_RECLAIM_TIMEOUT=1)"; rm -f "$FK/slowremove"
chk "②apply rc 0(끊긴 줄은 SKIP)" "$rc" 0
chk "②원래 자리 폴더 0" "$(ex "$WT/q1")" no
chk "②리포 worktree 목록에 원래 경로 0" "$(git -C "$RA" worktree list --porcelain | grep -cx "worktree $WT/q1")" 0
chk "②로그 = SKIP 시간 초과" "$(has "$W/outA1/deleted.log" $'SKIP\tworktree\t'"$WT/q1"$'\t시간 초과')" yes
chk "②격리 자리에만 남음(폴더 + .git)" "$(ex "$QA/q1")$(ex "$QA/q1/.git")" yesyes
chk "②표식 1줄 = 4칸 · 원래경로 · 격리경로 · HEAD 40자 · 시각" \
  "$(awk -F'\t' 'NF==4' "$MA" | wc -l | tr -d ' ')|$(awk -F'\t' '{printf "%s|%s|%d", $1, $2, length($3)}' "$MA")|$(awk -F'\t' '{print ($4 ~ /^[0-9]+$/) ? "num" : "x"}' "$MA")" \
  "1|$WT/q1|$QA/q1|40|num"
chk "②반쯤 지운 꼴 = D 줄뿐" "$(git -C "$QA/q1" status --porcelain | awk '{print $1}' | sort -u | tr '\n' ',')" "D,"
T2=$SECONDS

# ── ③ 다음 apply(표식 파일 먼저 훑기) = 사람 손 없이 마무리
mkdir -p "$W/outA2"; : > "$W/outA2/candidates.tsv"   # 들어온 목록 0줄 — 표식만으로 마무리해야 한다
: > "$FK/git.calls"
rc="$(ap "$RA" "$W/outA2/candidates.tsv")"
chk "③apply rc 0" "$rc" 0
chk "③격리 자리 0" "$(ex "$QA/q1")" no
chk "③리포 worktree 목록에 격리 경로도 0" "$(git -C "$RA" worktree list --porcelain | grep -cx "worktree $QA/q1")" 0
chk "③DELETED 1 · 원래 경로로 기록" "$(grep -c "^DELETED"$'\t'"worktree"$'\t'"-"$'\t'"$WT/q1\$" "$W/outA2/deleted.log")" 1
chk "③표식 줄 0" "$(cnt . "$MA")" 0
T3=$SECONDS

# ── ③a·③c·③d·③e 한 apply 에 모아 — repair 성공 · 남의 prunable 유지 · 표식 없음 · 조건 어긋남 · 끝난 꼴
mkrepo B; RB="$W/rB"; GB="$(gcd "$RB")"; QB="$GB/ft-reclaim-q"; MB="$GB/ft-reclaim-q.tsv"; mkdir -p "$QB"
wt B dirty; echo y >> "$WT/dirty/f"                        # ③b: 격리 밖 «수정 파일»
wt B pruneme; rm -f "$WT/pruneme/.git"                     # ③a: 남의 prunable 줄 (prune 0 확인용)
git -C "$RB" worktree add -q --detach "$QB/rep1" main; rm -f "$QB/rep1/.git"      # repair 성공 꼴
git -C "$RB" worktree add -q --detach "$QB/rep3" main; echo u > "$QB/rep3/u"      # ?? 1줄
git -C "$RB" worktree add -q --detach "$QB/rep5" main                             # HEAD ≠ 표식
git -C "$RB" worktree add -q --detach "$QB/hand1" main                            # 표식 없는 격리 worktree
HB="$(git -C "$RB" rev-parse main)"; Z40="0000000000000000000000000000000000000000"
{ row "$WT/gone1" "$QB/rep1" "$HB" 0; row "$WT/gone3" "$QB/rep3" "$HB" 0; row "$WT/gone5" "$QB/rep5" "$Z40" 0; row "$WT/gone9" "$QB/nope" "$HB" 0; } > "$MB"
mkdir -p "$W/outB"; row worktree 1 "$WT/dirty" "repo=$RB" > "$W/outB/candidates.tsv"
: > "$FK/git.calls"
rc="$(ap "$RB" "$W/outB/candidates.tsv")"
chk "③a·④apply rc 0" "$rc" 0
chk "③a .git 지워진 꼴 = repair 뒤 DELETED" "$(grep -c "^DELETED"$'\t'"worktree"$'\t'"-"$'\t'"$WT/gone1\$" "$W/outB/deleted.log")$(ex "$QB/rep1")" "1no"
chk "③a repair 를 불렀다" "$(has "$FK/git.calls" "worktree repair $QB/rep1")" yes
chk "③a 남의 prunable 줄 그대로(prune 0)" "$(git -C "$RB" worktree list --porcelain | grep -cx "worktree $WT/pruneme")" 1
chk "③b 격리 밖 수정 파일 = 기존 SKIP «수정 파일» · 폴더 그대로" "$(has "$W/outB/deleted.log" $'SKIP\tworktree\t'"$WT/dirty"$'\t수정 파일')$(ex "$WT/dirty")" "yesyes"
chk "③c 표식 없는 격리 worktree = SKIP «표식 없음» · 폴더 그대로 · --force 0" \
  "$(has "$W/outB/deleted.log" $'SKIP\tworktree\t'"$QB/hand1"$'\t표식 없음')$(ex "$QB/hand1")$(has "$FK/git.calls" "worktree remove --force $QB/hand1")" "yesyesno"
chk "③d ?? 1줄 = SKIP «격리 마무리 조건» · 그대로 · --force 0" \
  "$(has "$W/outB/deleted.log" $'SKIP\tworktree\t'"$WT/gone3"$'\t격리 마무리 조건')$(ex "$QB/rep3")$(has "$FK/git.calls" "worktree remove --force $QB/rep3")" "yesyesno"
chk "③d HEAD ≠ 표식 = SKIP «격리 마무리 조건» · 그대로" \
  "$(has "$W/outB/deleted.log" $'SKIP\tworktree\t'"$WT/gone5"$'\t격리 마무리 조건')$(ex "$QB/rep5")" "yesyes"
chk "③e 표식 있음 ∧ 격리 폴더 없음 = «DONE 격리 폴더 없음» 1줄 · 그 줄만 지움 · --force 0" \
  "$(grep -c "DONE.*격리 폴더 없음.*$WT/gone9$" "$W/outB/deleted.log")|$(grep -c "$WT/gone9" "$MB")|$(has "$FK/git.calls" "worktree remove --force $QB/nope")" "1|0|no"
mkdir -p "$W/outB2"; : > "$W/outB2/candidates.tsv"
rc="$(ap "$RB" "$W/outB2/candidates.tsv")"
chk "③e 다음 apply 같은 DONE 줄 0" "$(cnt '^DONE' "$W/outB2/deleted.log")" 0
T4=$SECONDS

# ── ③a repair 실패 꼴 — .git 이 안 살아나면 SKIP «격리 마무리 조건» · 격리 경로에 git -C 0
mkrepo C; RC2="$W/rC"; GC="$(gcd "$RC2")"; QC="$GC/ft-reclaim-q"; MC="$GC/ft-reclaim-q.tsv"; mkdir -p "$QC"
git -C "$RC2" worktree add -q --detach "$QC/repf" main; rm -f "$QC/repf/.git"
HC="$(git -C "$RC2" rev-parse main)"; row "$WT/goneF" "$QC/repf" "$HC" 0 > "$MC"
mkdir -p "$W/outC"; : > "$W/outC/candidates.tsv"; : > "$FK/git.calls"; touch "$FK/failrepair"
rc="$(ap "$RC2" "$W/outC/candidates.tsv")"; rm -f "$FK/failrepair"
chk "③a repair 실패 → SKIP «격리 마무리 조건» · 폴더 그대로 · 표식 그대로" \
  "$(has "$W/outC/deleted.log" $'SKIP\tworktree\t'"$WT/goneF"$'\t격리 마무리 조건')$(ex "$QC/repf")$(grep -c . "$MC")" "yesyes1"
chk "③a repair 실패 → 격리 경로에 git -C 0 (isfile 먼저)" "$(has "$FK/git.calls" "-C $QC/repf")" no
chk "③a repair 실패 → --force 0" "$(has "$FK/git.calls" "worktree remove --force")" no
T5=$SECONDS

# ── ④ 크기 상한 = 지우기 시작 0 · MOVED 1줄 · 다음 apply 가 지움 · 표식은 리포 고정 파일(격리 worktree 안 0)
mkrepo E; RE="$W/rE"; GE="$(gcd "$RE")"; QE="$GE/ft-reclaim-q"; ME="$GE/ft-reclaim-q.tsv"
wt E c1; ageidx "$RE"; mkdir -p "$W/outE1"; row worktree 200000 "$WT/c1" "repo=$RE" > "$W/outE1/candidates.tsv"
rc="$(ap "$RE" "$W/outE1/candidates.tsv" FT_RECLAIM_MOVE_ONLY_KIB=1)"
chk "④apply rc 0" "$rc" 0
chk "④상한 넘는 줄 = MOVED 1줄 · 지우기 다음 차례" "$(grep -c "^MOVED"$'\t'"worktree"$'\t'"200000"$'\t'"$WT/c1"$'\t지우기 다음 차례' "$W/outE1/deleted.log")" 1
chk "④원래 자리 0 · 격리 자리에 그대로 · DELETED 0" "$(ex "$WT/c1")$(ex "$QE/c1")$(grep -c '^DELETED' "$W/outE1/deleted.log")" "noyes0"
chk "④표식 = 리포 고정 파일 · 격리 worktree 안에 0" "$(ex "$ME")$(ex "$QE/c1/ft-reclaim-q.tsv")" "yesno"
mkdir -p "$W/outE2"; : > "$W/outE2/candidates.tsv"
rc="$(ap "$RE" "$W/outE2/candidates.tsv")"
chk "④다음 apply 가 지움(DELETED 1 · 격리 0)" "$(grep -c '^DELETED' "$W/outE2/deleted.log")$(ex "$QE/c1")|$rc" "1no|0"
T6=$SECONDS

# ── ⑤ 불변 — tmp 줄은 그대로 지운다 · 판정 불가면 지우기 0 · 게이트 글자 0
mkdir -p "$TR/t1"; touch -t "$OLD" "$TR/t1"/* 2>/dev/null; touch -t "$OLD" "$TR/t1"
mkrepo F; RF="$W/rF"; mkdir -p "$W/outF"; row tmp 1 "$TR/t1" "조건 전부" > "$W/outF/candidates.tsv"
rc="$(ap "$RF" "$W/outF/candidates.tsv")"
chk "⑤tmp 줄 그대로 지움" "$(cnt "^DELETED"$'\t'"tmp" "$W/outF/deleted.log")|$(ex "$TR/t1")|$rc" "1|no|0"
mkdir -p "$TR/t2" "$W/outF2"; touch -t "$OLD" "$TR/t2"; row tmp 1 "$TR/t2" "조건 전부" > "$W/outF2/candidates.tsv"
echo 1 > "$FK/lsof.rc"; rc="$(ap "$RF" "$W/outF2/candidates.tsv")"; rm -f "$FK/lsof.rc"
chk "⑤판정 불가 lsof → ABORT · rc≠0 · 지우기 0" "$([ "$rc" != 0 ] && echo y)$(ex "$TR/t2")$(cnt '^ABORT' "$W/outF2/deleted.log")" "yyes1"
chk "⑤plan 목록 꼴 4칸 그대로" "$(env FT_RECLAIM_ONLY="$TR" FT_RECLAIM_REPOS="$RF" bash "$TOOL" plan "$W/outF3" >/dev/null 2>&1; awk -F'\t' 'NF!=4' "$W/outF3/candidates.tsv" | wc -l | tr -d ' ')" 0
chk "⑤게이트(ft-scratch-repo.sh) 글자 0" "$(cnt . <(git -C "$HERE" diff --name-only -- '*ft-scratch-repo.sh'))" 0
T7=$SECONDS

# ── ⑥ 회귀: 기존 ft-disk-reclaim 시험 그대로 rc0 · 70초 안
s=$SECONDS; o="$(bash "$HERE/test_disk_reclaim_r2107.sh" 2>&1 | tail -1)"; e=$((SECONDS-s))
{ [ $e -lt 70 ] && grep -q 'ALL PASS' <<<"$o"; } && ok "⑥ 기존 ft-disk-reclaim 시험 rc0 (${e}s)" || bad "⑥ 기존 시험 ${e}s tail=[$o]"
T8=$SECONDS
echo "TIME 준비=$((T1-T0))s ②=$((T2-T1))s ③=$((T3-T2))s ③a~③e=$((T4-T3))s repair실패=$((T5-T4))s ④=$((T6-T5))s ⑤=$((T7-T6))s ⑥=$((T8-T7))s 합=$((T8-T0))s"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL count=$fail"
exit $(( fail > 0 ))
